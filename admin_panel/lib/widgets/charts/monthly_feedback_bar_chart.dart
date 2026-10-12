// lib/widgets/charts/monthly_feedback_bar_chart.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/monthly_trend_model.dart';

class MonthlyFeedbackBarChart extends StatefulWidget {
  final List<MonthlyTrendData> trends;
  final String title;
  final String badgeText;

  const MonthlyFeedbackBarChart({
    super.key,
    required this.trends,
    this.title = 'Feedback Performance',
    this.badgeText = 'SENTIMENT',
  });

  @override
  State<MonthlyFeedbackBarChart> createState() => _MonthlyFeedbackBarChartState();
}

class _MonthlyFeedbackBarChartState extends State<MonthlyFeedbackBarChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? theme.colorScheme.surface : Colors.white;
    final borderColor = isDark ? theme.colorScheme.outlineVariant : const Color(0xFFE2E8F0);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row: Title & Badge ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    widget.badgeText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF059669),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Legend Row ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Positive / Good Reviews
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'GOOD REVIEWS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Negative / Intercepted
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'INTERCEPTED (BAD)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Interactive Chart Area ─────────────────────────────────────
            SizedBox(
              height: 174,
              width: double.infinity,
              child: widget.trends.isEmpty
                  ? const Center(
                      child: Text(
                        'No feedback sentiment data available',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return MouseRegion(
                          onHover: (event) {
                            final boxWidth = constraints.maxWidth;
                            if (widget.trends.isEmpty) return;
                            final paddingH = 24.0;
                            final usableWidth = boxWidth - (paddingH * 2);
                            final segmentWidth = usableWidth / widget.trends.length;
                            final localX = (event.localPosition.dx - paddingH).clamp(0.0, usableWidth);
                            final index = (localX / segmentWidth).floor().clamp(0, widget.trends.length - 1);
                            if (_hoveredIndex != index) {
                              setState(() => _hoveredIndex = index);
                            }
                          },
                          onExit: (_) {
                            setState(() => _hoveredIndex = null);
                          },
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size(constraints.maxWidth, constraints.maxHeight),
                                painter: _GroupedBarChartPainter(
                                  trends: widget.trends,
                                  hoveredIndex: _hoveredIndex,
                                  isDark: isDark,
                                ),
                              ),
                              if (_hoveredIndex != null &&
                                  _hoveredIndex! >= 0 &&
                                  _hoveredIndex! < widget.trends.length)
                                _buildHoverTooltip(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                  widget.trends[_hoveredIndex!],
                                  _hoveredIndex!,
                                  widget.trends.length,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            // ── X-Axis Month Labels ────────────────────────────────────────
            if (widget.trends.isNotEmpty)
              SizedBox(
                height: 20,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxWidth = constraints.maxWidth;
                    final paddingH = 24.0;
                    final usableWidth = boxWidth - (paddingH * 2);
                    final count = widget.trends.length;
                    final groupWidth = usableWidth / count;
                    const labelWidth = 60.0;

                    return Stack(
                      children: widget.trends.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final isHovered = _hoveredIndex == idx;

                        final groupCenterX = paddingH + (groupWidth * idx) + (groupWidth / 2);
                        final leftPos = (groupCenterX - (labelWidth / 2)).clamp(0.0, boxWidth - labelWidth);

                        return Positioned(
                          left: leftPos,
                          width: labelWidth,
                          child: Text(
                            item.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                              color: isHovered
                                  ? const Color(0xFF0F172A)
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverTooltip(
    double totalWidth,
    double totalHeight,
    MonthlyTrendData data,
    int index,
    int totalCount,
  ) {
    final paddingH = 24.0;
    final usableWidth = totalWidth - (paddingH * 2);
    final groupWidth = usableWidth / totalCount;
    final groupCenterX = paddingH + (groupWidth * index) + (groupWidth / 2);

    final tooltipLeft = (groupCenterX - 65).clamp(8.0, totalWidth - 138.0);

    return Positioned(
      left: tooltipLeft,
      top: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  data.fullLabel.isNotEmpty ? data.fullLabel : data.label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Good (4-5★): ${data.positiveCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Intercepted: ${data.negativeCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedBarChartPainter extends CustomPainter {
  final List<MonthlyTrendData> trends;
  final int? hoveredIndex;
  final bool isDark;

  _GroupedBarChartPainter({
    required this.trends,
    required this.hoveredIndex,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trends.isEmpty) return;

    final paddingH = 24.0;
    final paddingTop = 16.0;
    final paddingBottom = 4.0;

    final chartWidth = size.width - (paddingH * 2);
    final chartHeight = size.height - paddingTop - paddingBottom;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // ── 1. Draw subtle dashed horizontal grid lines ─────────────────────────
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF334155).withValues(alpha: 0.4) : const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = paddingTop + (chartHeight / 3) * i;
      _drawDashedHorizontalLine(canvas, 0, size.width, y, gridPaint);
    }

    // ── 2. Determine max value for bars scaling ─────────────────────────────
    int maxVal = 0;
    for (final t in trends) {
      if (t.positiveCount > maxVal) maxVal = t.positiveCount;
      if (t.negativeCount > maxVal) maxVal = t.negativeCount;
    }
    if (maxVal == 0) maxVal = 5;
    final yMax = (maxVal * 1.2).ceilToDouble();

    // ── 3. Draw dual side-by-side bars for each month ───────────────────────
    final groupWidth = chartWidth / trends.length;
    final barGap = 3.0; // gap between positive and negative bars
    final maxSingleBarWidth = 14.0;
    final singleBarWidth = math.min(maxSingleBarWidth, (groupWidth - 12 - barGap) / 2).clamp(4.0, 16.0);

    for (int i = 0; i < trends.length; i++) {
      final t = trends[i];
      final isHovered = hoveredIndex == i;
      final groupCenterX = paddingH + (groupWidth * i) + (groupWidth / 2);

      // Highlight hover column background
      if (isHovered) {
        final colRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            groupCenterX - (groupWidth / 2) + 2,
            paddingTop - 4,
            groupWidth - 4,
            chartHeight + 8,
          ),
          const Radius.circular(8),
        );
        final bgHoverPaint = Paint()
          ..color = isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF8FAFC)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(colRect, bgHoverPaint);
      }

      // X coordinates for the two bars side-by-side
      final posBarX = groupCenterX - singleBarWidth - (barGap / 2);
      final negBarX = groupCenterX + (barGap / 2);

      // Bar heights
      final posRatio = (t.positiveCount / yMax).clamp(0.0, 1.0);
      final negRatio = (t.negativeCount / yMax).clamp(0.0, 1.0);

      final posHeight = t.positiveCount > 0 ? math.max(6.0, posRatio * chartHeight) : 2.0;
      final negHeight = t.negativeCount > 0 ? math.max(6.0, negRatio * chartHeight) : 2.0;

      final baseY = size.height - paddingBottom;

      // Draw Green Bar (Positive / Good Reviews)
      final posRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(posBarX, baseY - posHeight, singleBarWidth, posHeight),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      final posPaint = Paint()
        ..color = t.positiveCount > 0
            ? const Color(0xFF10B981)
            : const Color(0xFFCBD5E1).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(posRect, posPaint);

      // Draw Red Bar (Negative / Intercepted)
      final negRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(negBarX, baseY - negHeight, singleBarWidth, negHeight),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      final negPaint = Paint()
        ..color = t.negativeCount > 0
            ? const Color(0xFFEF4444)
            : const Color(0xFFCBD5E1).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(negRect, negPaint);
    }
  }

  void _drawDashedHorizontalLine(Canvas canvas, double x1, double x2, double y, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double startX = x1;
    while (startX < x2) {
      canvas.drawLine(Offset(startX, y), Offset(math.min(startX + dashWidth, x2), y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _GroupedBarChartPainter oldDelegate) {
    return oldDelegate.trends != trends ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.isDark != isDark;
  }
}
