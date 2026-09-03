// lib/widgets/app_animated_loader.dart
//
// High-performance, branded, sleek animated loader widget.
// Replaces boring standard CircularProgressIndicator across the app.

import 'dart:math' as math;
import 'package:flutter/material.dart';

enum AppLoaderVariant { fullScreen, card, inline }

class AppAnimatedLoader extends StatefulWidget {
  final AppLoaderVariant variant;
  final double size;
  final String? message;
  final Color? color;
  final Color? secondaryColor;

  const AppAnimatedLoader({
    super.key,
    this.variant = AppLoaderVariant.card,
    this.size = 40,
    this.message,
    this.color,
    this.secondaryColor,
  });

  const AppAnimatedLoader.fullScreen({
    super.key,
    this.size = 52,
    this.message = 'Loading workspace…',
    this.color,
    this.secondaryColor,
  }) : variant = AppLoaderVariant.fullScreen;

  const AppAnimatedLoader.card({
    super.key,
    this.size = 40,
    this.message,
    this.color,
    this.secondaryColor,
  }) : variant = AppLoaderVariant.card;

  const AppAnimatedLoader.inline({
    super.key,
    this.size = 18,
    this.message,
    this.color,
    this.secondaryColor,
  }) : variant = AppLoaderVariant.inline;

  @override
  State<AppAnimatedLoader> createState() => _AppAnimatedLoaderState();
}

class _AppAnimatedLoaderState extends State<AppAnimatedLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.color ?? const Color(0xFF4F46E5);
    final secondary = widget.secondaryColor ?? const Color(0xFF06B6D4);

    final loaderWidget = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _SleekDualRingPainter(
                  progress: _controller.value,
                  primaryColor: primary,
                  secondaryColor: secondary,
                  strokeWidth: widget.variant == AppLoaderVariant.inline
                      ? 2.0
                      : (widget.size > 48 ? 3.0 : 2.4),
                ),
              ),
              if (widget.size >= 36)
                Transform.scale(
                  scale: 0.8 + 0.2 * math.sin(_controller.value * math.pi * 2),
                  child: Container(
                    width: widget.size * 0.22,
                    height: widget.size * 0.22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    if (widget.variant == AppLoaderVariant.inline) {
      return loaderWidget;
    }

    if (widget.variant == AppLoaderVariant.fullScreen) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primary.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              loaderWidget,
              if (widget.message != null) ...[
                const SizedBox(height: 16),
                Text(
                  widget.message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Default: Card / Section
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loaderWidget,
            if (widget.message != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SleekDualRingPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final double strokeWidth;

  _SleekDualRingPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (math.min(size.width, size.height) - strokeWidth * 2) / 2;

    if (outerRadius <= 0) return;

    // Track circle
    final trackPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8;
    canvas.drawCircle(center, outerRadius, trackPaint);

    // Outer rotating arc (Clockwise)
    final outerAngle = progress * 2 * math.pi;
    final outerArcPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.5),
          primaryColor,
        ],
        transform: GradientRotation(outerAngle),
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      outerAngle,
      math.pi * 1.3,
      false,
      outerArcPaint,
    );

    // Inner counter-rotating arc for larger sizes
    if (size.width >= 32) {
      final innerRadius = outerRadius * 0.65;
      final innerAngle = -progress * 2.2 * math.pi;
      final innerArcPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            secondaryColor.withValues(alpha: 0.0),
            secondaryColor.withValues(alpha: 0.6),
            secondaryColor,
          ],
          transform: GradientRotation(innerAngle),
        ).createShader(Rect.fromCircle(center: center, radius: innerRadius))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth * 0.8;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerRadius),
        innerAngle,
        math.pi * 1.1,
        false,
        innerArcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SleekDualRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
