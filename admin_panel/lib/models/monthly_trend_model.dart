// lib/models/monthly_trend_model.dart

class MonthlyTrendData {
  final String monthKey; // e.g. "2026-09"
  final String label; // Short label e.g. "Sep" or "Sep 26"
  final String fullLabel; // Full label e.g. "September 2026"
  final int scans;
  final int reviews;
  final int positiveCount; // Good reviews (4–5 stars)
  final int negativeCount; // Intercepted / Private feedback (1–3 stars)
  final double positiveRate;

  const MonthlyTrendData({
    required this.monthKey,
    required this.label,
    required this.fullLabel,
    required this.scans,
    required this.reviews,
    required this.positiveCount,
    required this.negativeCount,
    required this.positiveRate,
  });

  bool get hasData => scans > 0 || reviews > 0 || positiveCount > 0 || negativeCount > 0;
  int get totalFeedback => positiveCount + negativeCount;
}
