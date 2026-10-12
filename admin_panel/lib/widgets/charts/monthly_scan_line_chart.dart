// lib/widgets/charts/monthly_scan_line_chart.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/monthly_trend_model.dart';

class MonthlyScanLineChart extends StatefulWidget {
  final List<MonthlyTrendData> trends;
  final String title;
  final String badgeText;

  const MonthlyScanLineChart({
    super.key,
    required this.trends,
    this.title = 'QR Scans (Monthly)',
    this.badgeText = 'MONTHLY VIEWS',
  });

  @override
  State<MonthlyScanLineChart> createState() => _MonthlyScanLineChartState();
}

class _MonthlyScanLineChartState extends State<MonthlyScanLineChart> {
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
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Text(
                    widget.badgeText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Interactive Chart Area ─────────────────────────────────────
            SizedBox(
              height: 200,
              width: double.infinity,
              child: widget.trends.isEmpty
                  ? const Center(
                      child: Text(
                        'No scan data available',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return MouseRegion(
                          onHover: (event) {
                            final boxWidth = constraints.maxWidth;
                            if (widget.trends.length <= 1) {
                              setState(() => _hoveredIndex = 0);
                              return;
                            }
                            final paddingH = 32.0;
                            final usableWidth = boxWidth - (paddingH * 2);
                            final segmentWidth = usableWidth / (widget.trends.length - 1);
                            final localX = (event.localPosition.dx - paddingH).clamp(0.0, usableWidth);
                            final index = (localX / segmentWidth).round().clamp(0, widget.trends.length - 1);
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
                                painter: _LineChartPainter(
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
                    final paddingH = 32.0;
                    final usableWidth = boxWidth - (paddingH * 2);
                    final count = widget.trends.length;
                    const labelWidth = 60.0;

                    return Stack(
                      children: widget.trends.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final isHovered = _hoveredIndex == idx;

                        final pointX = count == 1
                            ? paddingH + usableWidth / 2
                            : paddingH + (usableWidth / (count - 1)) * idx;

                        final leftPos = (pointX - (labelWidth / 2)).clamp(0.0, boxWidth - labelWidth);

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
                                  ? const Color(0xFF2563EB)
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
    final paddingH = 32.0;
    final usableWidth = totalWidth - (paddingH * 2);
    final segmentWidth = totalCount > 1 ? usableWidth / (totalCount - 1) : 0.0;
    final pointX = paddingH + (segmentWidth * index);

    final tooltipLeft = (pointX - 55).clamp(8.0, totalWidth - 118.0);

    return Positioned(
      left: tooltipLeft,
      top: 8,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                data.fullLabel.isNotEmpty ? data.fullLabel : data.label,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${data.scans} Scans',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<MonthlyTrendData> trends;
  final int? hoveredIndex;
  final bool isDark;

  _LineChartPainter({
    required this.trends,
    required this.hoveredIndex,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trends.isEmpty) return;

    final paddingH = 32.0;
    final paddingTop = 36.0;
    final paddingBottom = 16.0;

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

    // ── 2. Determine max scans with headroom ────────────────────────────────
    int maxScans = trends.map((t) => t.scans).fold(0, (max, v) => v > max ? v : max);
    if (maxScans == 0) maxScans = 10;
    final yMax = (maxScans * 1.25).ceilToDouble();

    // ── 3. Calculate data point coordinates ─────────────────────────────────
    final points = <Offset>[];
    for (int i = 0; i < trends.length; i++) {
      final x = trends.length == 1
          ? paddingH + chartWidth / 2
          : paddingH + (chartWidth / (trends.length - 1)) * i;
      final scans = trends[i].scans.toDouble();
      final normalizedY = scans / yMax;
      final y = paddingTop + chartHeight - (normalizedY * chartHeight);
      points.add(Offset(x, y));
    }

    // ── 4. Build smooth Bezier Curve ────────────────────────────────────────
    final path = Path();
    final fillPath = Path();

    if (points.length == 1) {
      path.moveTo(paddingH, points[0].dy);
      path.lineTo(size.width - paddingH, points[0].dy);

      fillPath.moveTo(paddingH, size.height - paddingBottom);
      fillPath.lineTo(paddingH, points[0].dy);
      fillPath.lineTo(size.width - paddingH, points[0].dy);
      fillPath.lineTo(size.width - paddingH, size.height - paddingBottom);
      fillPath.close();
    } else {
      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, size.height - paddingBottom);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p0 = i > 0 ? points[i - 1] : points[i];
        final p1 = points[i];
        final p2 = points[i + 1];
        final p3 = i + 2 < points.length ? points[i + 2] : p2;

        final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
        fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }

      fillPath.lineTo(points.last.dx, size.height - paddingBottom);
      fillPath.close();
    }

    // ── 5. Render Gradient Fill under Curve ─────────────────────────────────
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF2563EB).withValues(alpha: 0.18),
          const Color(0xFF3B82F6).withValues(alpha: 0.06),
          const Color(0xFF3B82F6).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, paddingTop, size.width, chartHeight + paddingBottom));

    canvas.drawPath(fillPath, fillPaint);

    // ── 6. Render Smooth Line Stroke ────────────────────────────────────────
    final strokePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    // ── 7. Render Hover Guide & Point ──────────────────────────────────────
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < points.length) {
      final hp = points[hoveredIndex!];

      // Vertical guide line
      final hoverLinePaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.3)
        ..strokeWidth = 1.5;
      _drawDashedVerticalLine(canvas, hp.dx, paddingTop, size.height - paddingBottom, hoverLinePaint);

      // Outer halo
      final haloPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 9, haloPaint);

      // Blue dot
      final dotPaint = Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 5.5, dotPaint);

      // White center
      final centerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 2.5, centerPaint);
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

  void _drawDashedVerticalLine(Canvas canvas, double x, double y1, double y2, Paint paint) {
    const dashHeight = 4.0;
    const dashSpace = 3.0;
    double startY = y1;
    while (startY < y2) {
      canvas.drawLine(Offset(x, startY), Offset(x, math.min(startY + dashHeight, y2)), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.trends != trends ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.isDark != isDark;
  }
}
