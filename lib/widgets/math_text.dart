import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// Renders [content] as flowing text, treating any `$...$` or `$$...$$`
/// segments as inline LaTeX rendered via flutter_math_fork, and any
/// bare URLs (common in CS paper abstracts linking to GitHub repos,
/// project pages, or datasets) as tappable links.
///
/// Unlike flutter_tex's TeXView, this never spins up a WebView — it's
/// pure Flutter canvas rendering, so it performs identically on iOS and
/// Android and has none of the WebView startup/teardown cost.
///
/// Falls back to plain text automatically if no math delimiters or URLs
/// are found, so it's a safe drop-in replacement for a plain Text widget.
class MathText extends StatefulWidget {
  final String content;
  final TextStyle style;
  final TextAlign textAlign;

  const MathText(
    this.content, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  State<MathText> createState() => _MathTextState();
}

class _MathTextState extends State<MathText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant MathText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.style != widget.style) {
      _disposeRecognizers();
    }
  }

  /// Matches `$$...$$` (display math) or `$...$` (inline math) and splits
  /// the surrounding plain text into separate spans.
  static final RegExp _mathPattern = RegExp(
    r'\$\$(.+?)\$\$|\$(.+?)\$',
    dotAll: true,
  );

  /// Matches bare http(s) URLs. Trailing punctuation commonly found at
  /// the end of a sentence (. , ) ] etc.) is trimmed off separately so
  /// "see https://github.com/foo/bar." doesn't swallow the period into
  /// the link.
  static final RegExp _urlPattern = RegExp(r'https?://[^\s<>"]+');

  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]}]+$');
  static final Map<String, Math> _parsedMath = {};

  @override
  Widget build(BuildContext context) {
    // _buildSpans creates recognizers for links. A theme update can rebuild
    // this widget without changing its content, so retire the previous set
    // on every build instead of retaining one set per theme switch.
    _disposeRecognizers();
    final palette = AppPalette.of(context);
    return Text.rich(
      TextSpan(children: _buildSpans(widget.content, widget.style, palette)),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _buildSpans(
    String text,
    TextStyle style,
    AppPalette palette,
  ) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _mathPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.addAll(
          _buildTextWithLinks(
            text.substring(lastEnd, match.start),
            style,
            palette,
          ),
        );
      }

      final tex = (match.group(1) ?? match.group(2) ?? '').trim();
      if (tex.isEmpty) {
        // Not real math (e.g. a lone "$5" price) — keep the raw text.
        spans.addAll(_buildTextWithLinks(match.group(0) ?? '', style, palette));
      } else {
        // Math.tex parses synchronously. Theme changes rebuild this widget
        // with a new text color, so reuse the parsed tree and pass the current
        // style to a fresh Math widget instead of parsing the expression again.
        if (!_parsedMath.containsKey(tex)) {
          if (_parsedMath.length >= 64) {
            _parsedMath.remove(_parsedMath.keys.first);
          }
          _parsedMath[tex] = Math.tex(tex, mathStyle: MathStyle.text);
        }
        final parsed = _parsedMath[tex]!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: Math(
                ast: parsed.ast,
                parseError: parsed.parseError,
                textStyle: style,
                mathStyle: MathStyle.text,
                onErrorFallback: (_) =>
                    Text(match.group(0) ?? '', style: style),
              ),
            ),
          ),
        );
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.addAll(
        _buildTextWithLinks(text.substring(lastEnd), style, palette),
      );
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
    }

    return spans;
  }

  /// Splits a plain-text (non-math) segment into regular text spans and
  /// tappable link spans wherever a bare URL appears.
  List<InlineSpan> _buildTextWithLinks(
    String text,
    TextStyle style,
    AppPalette palette,
  ) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _urlPattern.allMatches(text)) {
      var url = match.group(0)!;
      var end = match.end;

      // Trim trailing punctuation off the URL and put it back as plain text.
      final trailingMatch = _trailingPunctuation.firstMatch(url);
      if (trailingMatch != null) {
        final trimmed = trailingMatch.group(0)!;
        url = url.substring(0, url.length - trimmed.length);
        end -= trimmed.length;
      }

      if (url.isEmpty) continue;

      if (match.start > lastEnd) {
        spans.add(
          TextSpan(text: text.substring(lastEnd, match.start), style: style),
        );
      }

      final recognizer = TapGestureRecognizer()..onTap = () => _openLink(url);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: palette.link,
            decoration: TextDecoration.underline,
            decorationColor: palette.link,
          ),
          recognizer: recognizer,
        ),
      );

      lastEnd = end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: style));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
    }

    return spans;
  }

  Future<void> _openLink(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }
}
