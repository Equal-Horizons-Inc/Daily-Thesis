import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _ShimmerPainter extends CustomPainter {
  final double progress;
  final Color base;
  final Color highlight;
  _ShimmerPainter(this.progress, this.base, this.highlight);

  @override
  void paint(Canvas canvas, Size size) {
    final shimmerX = size.width * (progress * 2 - 0.5);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [base, highlight, base],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(shimmerX - 150, 0, 300, size.height));

    void drawBar(double y, double w, double h, double radius) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y, w, h),
        Radius.circular(radius),
      );
      canvas.drawRRect(rect, paint);
    }

    drawBar(0, 90, 12, 4);
    drawBar(24, size.width * 0.95, 24, 4);
    drawBar(56, size.width * 0.80, 24, 4);
    drawBar(96, size.width * 0.45, 14, 4);
    drawBar(122, size.width * 0.30, 12, 4);
    drawBar(156, size.width, 1, 0);
    drawBar(180, 70, 12, 4);
    for (int i = 0; i < 6; i++) {
      final w = i == 5
          ? size.width * 0.5
          : size.width * (0.92 + (i % 2) * 0.04);
      drawBar(210.0 + i * 26, w, 14, 4);
    }
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.progress != progress ||
      old.base != base ||
      old.highlight != highlight;
}

class ShimmerLoader extends StatefulWidget {
  const ShimmerLoader({super.key});

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _ShimmerPainter(
            _ctrl.value,
            palette.shimmerBase,
            palette.shimmerHighlight,
          ),
          size: const Size(double.infinity, 450),
        ),
      ),
    );
  }
}
