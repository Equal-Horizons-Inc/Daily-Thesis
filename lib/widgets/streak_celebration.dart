import 'dart:math';
import 'package:flutter/material.dart';

// ── Dialog Helper ─────────────────────────────────────────────────────────

/// A unified helper to reduce boilerplate for all streak popups.
Future<void> _showAnimatedDialog(
  BuildContext context, {
  required String label,
  required Widget child,
  Duration duration = const Duration(milliseconds: 350),
  Curve curve = Curves.easeOutBack,
  bool enableScale = true,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    transitionDuration: duration,
    pageBuilder: (_, _, _) => _StreakPopupShell(child: child),
    transitionBuilder: (context, anim, _, child) {
      final opacityWidget = Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: child,
      );
      if (!enableScale) return opacityWidget;

      final curved = CurvedAnimation(parent: anim, curve: curve);
      // Clamp the scale max to 1.3 to prevent extreme bouncing on elastic curves
      return Transform.scale(
        scale: curved.value.clamp(0.0, 1.3),
        child: opacityWidget,
      );
    },
  );
}

// ── Public API ────────────────────────────────────────────────────────────

/// Shown when a session crosses the 1-minute threshold and the streak ticks up.
Future<void> showStreakIncreasedPopup(
  BuildContext context, {
  required int oldStreak,
  required int newStreak,
}) {
  return _showAnimatedDialog(
    context,
    label: 'Streak increased',
    child: _FirePopupContent(oldStreak: oldStreak, newStreak: newStreak),
  );
}

/// Shown right after a missed day is auto-forgiven by a freeze.
Future<void> showFreezeUsedPopup(
  BuildContext context, {
  required int currentStreak,
}) {
  return _showAnimatedDialog(
    context,
    label: 'Freeze used',
    child: _FreezePopupContent(currentStreak: currentStreak),
  );
}

/// Shown when a gap was too large for freezes to cover and the streak reset.
Future<void> showStreakBrokenPopup(
  BuildContext context, {
  required int previousStreak,
}) {
  return _showAnimatedDialog(
    context,
    label: 'Streak broken',
    duration: const Duration(milliseconds: 300),
    enableScale: false, // Just fades in
    child: _BrokenPopupContent(previousStreak: previousStreak),
  );
}

/// Shown right after a milestone (7, 30, 100... days) is hit.
Future<void> showMilestonePopup(
  BuildContext context, {
  required int milestoneDays,
}) {
  return _showAnimatedDialog(
    context,
    label: 'Milestone reached',
    duration: const Duration(milliseconds: 400),
    curve: Curves.elasticOut, // Extra bouncy for milestones
    child: _MilestonePopupContent(milestoneDays: milestoneDays),
  );
}

// ── UI Shell ──────────────────────────────────────────────────────────────

class _StreakPopupShell extends StatelessWidget {
  final Widget child;
  const _StreakPopupShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          // BoxConstraints scale better than a hardcoded width
          constraints: const BoxConstraints(maxWidth: 300, minWidth: 260),
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color:
                Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Fire (streak increased) ───────────────────────────────────────────────

class _FirePopupContent extends StatefulWidget {
  final int oldStreak;
  final int newStreak;

  const _FirePopupContent({required this.oldStreak, required this.newStreak});

  @override
  State<_FirePopupContent> createState() => _FirePopupContentState();
}

class _FirePopupContentState extends State<_FirePopupContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _flicker,
          builder: (context, child) {
            final scale = 1.0 + (_flicker.value * 0.08);
            return Transform.scale(scale: scale, child: child);
          },
          child: const Icon(
            Icons.local_fire_department,
            color: Colors.deepOrange,
            size: 76,
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: widget.oldStreak, end: widget.newStreak),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, value, _) => Text(
            '$value',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          widget.newStreak == 1 ? 'day streak started!' : 'day streak!',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Nice'),
        ),
      ],
    );
  }
}

// ── Freeze (missed day auto-forgiven) ─────────────────────────────────────

class _FreezePopupContent extends StatefulWidget {
  final int currentStreak;
  const _FreezePopupContent({required this.currentStreak});

  @override
  State<_FreezePopupContent> createState() => _FreezePopupContentState();
}

class _FreezePopupContentState extends State<_FreezePopupContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shimmer,
          builder: (context, child) {
            // Slower, smoother wobble
            final wobble = sin(_shimmer.value * 2 * pi) * 0.05;
            return Transform.rotate(angle: wobble, child: child);
          },
          child: const Icon(Icons.ac_unit, color: Colors.lightBlue, size: 72),
        ),
        const SizedBox(height: 16),
        const Text(
          'Freeze used',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'A missed day was covered — your ${widget.currentStreak}-day streak is safe.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

// ── Broken streak ──────────────────────────────────────────────────────────

class _BrokenPopupContent extends StatelessWidget {
  final int previousStreak;
  const _BrokenPopupContent({required this.previousStreak});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.local_fire_department_outlined,
          color: Colors.grey,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          previousStreak > 0
              ? 'Your $previousStreak-day streak ended'
              : 'Streak reset',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "No worries, today's a fresh start.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Start again'),
        ),
      ],
    );
  }
}

// ── Milestone ───────────────────────────────────────────────────────────────

class _MilestonePopupContent extends StatelessWidget {
  final int milestoneDays;
  const _MilestonePopupContent({required this.milestoneDays});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('\u{1F389}', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        Text(
          '$milestoneDays days!',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Milestone reached — keep it going.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Nice'),
        ),
      ],
    );
  }
}
