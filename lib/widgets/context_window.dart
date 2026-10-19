import 'package:flutter/material.dart';
import '../services/context_window_service.dart';
import '../theme/app_theme.dart';
import 'math_text.dart';

/// A collapsible box shown just under a paper's title, letting readers
/// unfamiliar with the field opt into a plain-language summary and key
/// term definitions. Closed by default so it stays out of the way for
/// readers who don't need it; the content is only fetched (lazily) once
/// the user taps to expand.
class ContextWindow extends StatefulWidget {
  final String paperId;
  final String title;
  final String abstract;
  final String? field;

  /// When true, the box starts expanded — intended for papers outside
  /// the reader's declared field of interest, where the extra help is
  /// more likely to be wanted.
  final bool startExpanded;

  const ContextWindow({
    super.key,
    required this.paperId,
    required this.title,
    required this.abstract,
    this.field,
    this.startExpanded = false,
  });

  @override
  State<ContextWindow> createState() => _ContextWindowState();
}

enum _LoadState { idle, loading, loaded, error, unavailable }

class _ContextWindowState extends State<ContextWindow>
    with SingleTickerProviderStateMixin {
  final _service = ContextWindowService();

  bool _expanded = false;
  _LoadState _loadState = _LoadState.idle;
  PaperContext? _context;

  // Drives the skeleton loader only while it is actually visible. Keeping
  // this paused outside loading avoids an otherwise invisible 60fps ticker.
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _expanded = widget.startExpanded;
    if (_expanded) {
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant ContextWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new paper was scrolled to — reset so we don't show stale content.
    if (oldWidget.paperId != widget.paperId) {
      setState(() {
        _expanded = widget.startExpanded;
        _loadState = _LoadState.idle;
        _context = null;
      });
      if (_expanded) _fetch();
      if (!_expanded) _shimmerCtrl.stop();
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loadState == _LoadState.loading || _loadState == _LoadState.loaded) {
      return;
    }
    setState(() => _loadState = _LoadState.loading);
    if (_expanded) _shimmerCtrl.repeat(reverse: true);

    try {
      final result = await _service.fetchContext(
        paperId: widget.paperId,
        title: widget.title,
        abstract: widget.abstract,
        field: widget.field,
      );
      if (!mounted) return;
      setState(() {
        _context = result;
        _loadState = _LoadState.loaded;
      });
    } on ContextUnavailableException {
      if (!mounted) return;
      setState(() {
        _loadState = _LoadState.unavailable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    } finally {
      _shimmerCtrl.stop();
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _loadState == _LoadState.idle) {
      _fetch();
    } else if (_expanded && _loadState == _LoadState.loading) {
      _shimmerCtrl.repeat(reverse: true);
    } else if (!_expanded) {
      _shimmerCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderSoft, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(palette),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildBody(palette),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppPalette palette) {
    return InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 16,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _expanded ? 'Context Window' : _teaserText(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                  fontFamily: '-apple-system',
                ),
              ),
            ),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _teaserText() {
    return widget.field != null && widget.field!.isNotEmpty
        ? 'New to this field? Tap for background.'
        : 'Context Window — tap for a plain-language summary.';
  }

  Widget _buildBody(AppPalette palette) {
    switch (_loadState) {
      case _LoadState.idle:
        return const SizedBox.shrink();
      case _LoadState.loading:
        return _paddedBody(palette: palette, child: _buildSkeleton(palette));
      case _LoadState.error:
        return _paddedBody(
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: palette.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't load context. Tap to retry.",
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _loadState = _LoadState.idle);
                  _fetch();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
          palette: palette,
        );
      case _LoadState.unavailable:
        return _paddedBody(
          child: Text(
            'Context generation is temporarily unavailable — please try again in a bit.',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          palette: palette,
        );
      case _LoadState.loaded:
        final ctx = _context!;
        return _paddedBody(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MathText(
                ctx.summary,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: palette.textPrimary,
                ),
              ),
              if (ctx.keyTerms.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'KEY TERMS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: palette.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                ...ctx.keyTerms.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: palette.textSecondary,
                          fontFamily: '-apple-system',
                        ),
                        children: [
                          TextSpan(
                            text: '${t.term}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          TextSpan(text: t.definition),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  /// Placeholder shape mirroring the loaded layout: a few summary lines
  /// of decreasing width, followed by a smaller "key terms" block. Bars
  /// pulse in opacity via [_shimmerCtrl] to read clearly as "loading"
  /// rather than a rendering glitch.
  Widget _buildSkeleton(AppPalette palette) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmerCtrl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary lines
            _skeletonBar(palette, width: double.infinity, height: 13),
            const SizedBox(height: 8),
            _skeletonBar(palette, width: double.infinity, height: 13),
            const SizedBox(height: 8),
            _skeletonBar(palette, width: 160, height: 13),

            const SizedBox(height: 18),

            // "KEY TERMS" label placeholder
            _skeletonBar(palette, width: 68, height: 9),
            const SizedBox(height: 10),

            // Key term rows (label + definition line)
            _skeletonBar(palette, width: 90, height: 12),
            const SizedBox(height: 6),
            _skeletonBar(palette, width: double.infinity, height: 12),
            const SizedBox(height: 14),
            _skeletonBar(palette, width: 110, height: 12),
            const SizedBox(height: 6),
            _skeletonBar(palette, width: 200, height: 12),
          ],
        ),
        builder: (context, child) {
          final opacity = 0.3 + (0.35 * _shimmerCtrl.value);
          return Opacity(opacity: opacity, child: child);
        },
      ),
    );
  }

  Widget _skeletonBar(
    AppPalette palette, {
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.textTertiary,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _paddedBody({required Widget child, required AppPalette palette}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.borderSoft, width: 1)),
      ),
      child: Padding(padding: const EdgeInsets.only(top: 12), child: child),
    );
  }
}
