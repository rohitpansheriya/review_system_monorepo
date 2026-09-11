// lib/models/branch_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

class BranchModel {
  final String  id;
  final String  businessId;
  final String  branchName;
  final String  address;
  final String  whatsappNumber;
  final String? placeId;
  final String? googleReviewLink;
  final Map<String, String> starRoutingConfig; // "1"–"5" → thankyou/whatsapp/google
  final String? qrCodeId;
  final String? nfcTagId;
  final String? plainQrStoragePath;
  final String standeeStatus;
  final DateTime? standeeStatusUpdatedAt;
  final String whatsappMonitoredBy;

  // ── Branch-Level Payment & Lifecycle ──────────────────────────────────────
  final String subscriptionStatus; // 'active' | 'pending_payment'
  final String paymentMode;        // 'online' | 'cash' | 'pending'
  final String? enrolledBy;
  final DateTime? cashConfirmedAt;
  final String? cashConfirmedByAdmin;
  final double? amountPaid;
  final double? setupFeePaid;
  final double? renewalAmountPaid;
  final DateTime? renewalDate;
  final DateTime? gracePeriodEnds;
  final String? lastRenewalLinkUrl;

  // ── Pre-aggregated Stats Summary ───────────────────────────────────────────
  final int totalScans;
  final int googleReviewsOpened;
  final Map<String, int> starDistribution;
  final Map<String, Map<String, dynamic>> monthlyStats;

  // ── Google Reputation Baseline & Growth ────────────────────────────────────
  final double? initialRating;
  final int? initialReviewCount;
  final DateTime? initialRatingCapturedAt;
  final double? currentRating;
  final int? currentReviewCount;
  final DateTime? lastRatingSyncAt;

  const BranchModel({
    required this.id,
    required this.businessId,
    required this.branchName,
    required this.address,
    required this.whatsappNumber,
    this.placeId,
    this.googleReviewLink,
    required this.starRoutingConfig,
    this.qrCodeId,
    this.nfcTagId,
    this.plainQrStoragePath,
    this.standeeStatus = AppConstants.standeeOrdered,
    this.standeeStatusUpdatedAt,
    this.whatsappMonitoredBy = '',
    this.subscriptionStatus = AppConstants.statusPendingPayment,
    this.paymentMode = 'pending',
    this.enrolledBy,
    this.cashConfirmedAt,
    this.cashConfirmedByAdmin,
    this.amountPaid,
    this.setupFeePaid,
    this.renewalAmountPaid,
    this.renewalDate,
    this.gracePeriodEnds,
    this.lastRenewalLinkUrl,
    this.totalScans = 0,
    this.googleReviewsOpened = 0,
    this.starDistribution = const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
    this.monthlyStats = const {},
    this.initialRating,
    this.initialReviewCount,
    this.initialRatingCapturedAt,
    this.currentRating,
    this.currentReviewCount,
    this.lastRatingSyncAt,
  });

  bool get isPendingPayment => subscriptionStatus == AppConstants.statusPendingPayment;
  bool get isActive => subscriptionStatus == AppConstants.statusActive;

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    return null;
  }

  factory BranchModel.fromDoc(DocumentSnapshot doc, {required String businessId}) {
    final rawData = doc.data();
    final d = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};

    final rawRouting = d['star_routing_config'] ?? d['starRoutingConfig'];
    final routingMap = <String, String>{
      '1': 'thankyou',
      '2': 'thankyou',
      '3': 'whatsapp',
      '4': 'google',
      '5': 'google',
    };
    if (rawRouting is Map) {
      rawRouting.forEach((k, v) {
        if (k != null && v != null) {
          routingMap[k.toString()] = v.toString();
        }
      });
    }

    final rawStats = d['stats_summary'];
    final stats = rawStats is Map ? Map<String, dynamic>.from(rawStats) : <String, dynamic>{};
    final rawStars = stats['star_counts'] is Map
        ? stats['star_counts'] as Map
        : (stats['star_distribution'] is Map ? stats['star_distribution'] as Map : const {});

    final starsMap = <String, int>{
      '1': (rawStars['1'] as num? ?? 0).toInt(),
      '2': (rawStars['2'] as num? ?? 0).toInt(),
      '3': (rawStars['3'] as num? ?? 0).toInt(),
      '4': (rawStars['4'] as num? ?? 0).toInt(),
      '5': (rawStars['5'] as num? ?? 0).toInt(),
    };

    final rawMonthly = d['monthly_stats'];
    final parsedMonthly = <String, Map<String, dynamic>>{};
    if (rawMonthly is Map) {
      rawMonthly.forEach((mKey, val) {
        if (val is Map) {
          final mStars = val['star_counts'] is Map
              ? val['star_counts'] as Map
              : (val['star_distribution'] is Map ? val['star_distribution'] as Map : const {});
          parsedMonthly[mKey.toString()] = {
            'total_scans': (val['total_scans'] as num? ?? 0).toInt(),
            'google_reviews_opened': (val['google_reviews_opened'] as num? ??
                val['total_reviews_redirected'] as num? ?? 0).toInt(),
            'private_issues': (val['private_issues'] as num? ?? 0).toInt(),
            'star_distribution': {
              '1': (mStars['1'] as num? ?? 0).toInt(),
              '2': (mStars['2'] as num? ?? 0).toInt(),
              '3': (mStars['3'] as num? ?? 0).toInt(),
              '4': (mStars['4'] as num? ?? 0).toInt(),
              '5': (mStars['5'] as num? ?? 0).toInt(),
            },
          };
        }
      });
    }

    return BranchModel(
      id:               doc.id,
      businessId:       businessId,
      branchName:       d['branch_name']?.toString() ?? d['name']?.toString() ?? '',
      address:          d['address']?.toString() ?? '',
      whatsappNumber:   d['whatsapp_number']?.toString() ?? '',
      placeId:          d['place_id']?.toString() ?? d['placeId']?.toString(),
      googleReviewLink: d['google_review_link']?.toString() ?? d['googleReviewLink']?.toString(),
      starRoutingConfig: routingMap,
      qrCodeId:         d['qr_code_id']?.toString(),
      nfcTagId:         d['nfc_tag_id']?.toString(),
      plainQrStoragePath:     d['plain_qr_storage_path']?.toString(),
      standeeStatus:          d['standee_status']?.toString() ?? AppConstants.standeeOrdered,
      standeeStatusUpdatedAt: _parseDate(d['standee_status_updated_at'] ?? d['standeeStatusUpdatedAt']),
      whatsappMonitoredBy:    d['whatsapp_monitored_by']?.toString() ?? d['whatsappMonitoredBy']?.toString() ?? '',
      subscriptionStatus:     d['subscription_status']?.toString() ?? AppConstants.statusPendingPayment,
      paymentMode:            d['payment_mode']?.toString() ?? 'pending',
      enrolledBy:             d['enrolled_by']?.toString(),
      cashConfirmedAt:        _parseDate(d['cash_payment_confirmed_at'] ?? d['cashConfirmedAt']),
      cashConfirmedByAdmin:   d['cash_confirmed_by_admin']?.toString(),
      amountPaid:             (d['amount_paid'] as num?)?.toDouble(),
      setupFeePaid:           (d['setup_fee_paid'] as num?)?.toDouble(),
      renewalAmountPaid:      (d['renewal_amount_paid'] as num?)?.toDouble(),
      renewalDate:            _parseDate(d['renewal_date'] ?? d['renewalDate']),
      gracePeriodEnds:        _parseDate(d['grace_period_ends'] ?? d['gracePeriodEnds']),
      lastRenewalLinkUrl:     d['last_renewal_link_url']?.toString(),
      totalScans:             (stats['total_scans'] as num? ?? d['stats_summary.total_scans'] as num? ?? d['total_scans'] as num? ?? 0).toInt(),
      googleReviewsOpened:    (stats['google_reviews_opened'] as num? ?? stats['total_reviews_redirected'] as num? ?? stats['monthly_google_reviews'] as num? ?? d['stats_summary.google_reviews_opened'] as num? ?? 0).toInt(),
      starDistribution:       starsMap,
      monthlyStats:           parsedMonthly,
      initialRating:          (d['initial_rating'] as num? ?? d['initialRating'] as num?)?.toDouble(),
      initialReviewCount:     (d['initial_review_count'] as num? ?? d['initialReviewCount'] as num?)?.toInt(),
      initialRatingCapturedAt: _parseDate(d['initial_rating_captured_at'] ?? d['initialRatingCapturedAt']),
      currentRating:          (d['current_rating'] as num? ?? d['currentRating'] as num?)?.toDouble(),
      currentReviewCount:     (d['current_review_count'] as num? ?? d['currentReviewCount'] as num?)?.toInt(),
      lastRatingSyncAt:       _parseDate(d['last_rating_sync_at'] ?? d['lastRatingSyncAt']),
    );
  }

  BranchModel copyWith({
    String? branchName,
    String? address,
    String? whatsappNumber,
    Map<String, String>? starRoutingConfig,
    String? standeeStatus,
    String? subscriptionStatus,
    String? paymentMode,
    DateTime? renewalDate,
    DateTime? gracePeriodEnds,
    double? renewalAmountPaid,
    String? lastRenewalLinkUrl,
    double? initialRating,
    int? initialReviewCount,
    DateTime? initialRatingCapturedAt,
    double? currentRating,
    int? currentReviewCount,
    DateTime? lastRatingSyncAt,
  }) {
    return BranchModel(
      id: id,
      businessId: businessId,
      branchName: branchName ?? this.branchName,
      address: address ?? this.address,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      placeId: placeId,
      googleReviewLink: googleReviewLink,
      starRoutingConfig: starRoutingConfig ?? this.starRoutingConfig,
      qrCodeId: qrCodeId,
      nfcTagId: nfcTagId,
      plainQrStoragePath: plainQrStoragePath,
      standeeStatus: standeeStatus ?? this.standeeStatus,
      standeeStatusUpdatedAt: standeeStatusUpdatedAt,
      whatsappMonitoredBy: whatsappMonitoredBy,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      paymentMode: paymentMode ?? this.paymentMode,
      enrolledBy: enrolledBy,
      cashConfirmedAt: cashConfirmedAt,
      cashConfirmedByAdmin: cashConfirmedByAdmin,
      amountPaid: amountPaid,
      setupFeePaid: setupFeePaid,
      renewalAmountPaid: renewalAmountPaid ?? this.renewalAmountPaid,
      renewalDate: renewalDate ?? this.renewalDate,
      gracePeriodEnds: gracePeriodEnds ?? this.gracePeriodEnds,
      lastRenewalLinkUrl: lastRenewalLinkUrl ?? this.lastRenewalLinkUrl,
      totalScans: totalScans,
      googleReviewsOpened: googleReviewsOpened,
      starDistribution: starDistribution,
      monthlyStats: monthlyStats,
      initialRating: initialRating ?? this.initialRating,
      initialReviewCount: initialReviewCount ?? this.initialReviewCount,
      initialRatingCapturedAt: initialRatingCapturedAt ?? this.initialRatingCapturedAt,
      currentRating: currentRating ?? this.currentRating,
      currentReviewCount: currentReviewCount ?? this.currentReviewCount,
      lastRatingSyncAt: lastRatingSyncAt ?? this.lastRatingSyncAt,
    );
  }
}
