// lib/models/business_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String id;
  final String? businessCode;
  final int? businessNumber;
  final bool isTestAccount;
  final String brandName;
  final String logoUrl;
  final String categoryType;
  final String? defaultCategoryTemplateId;
  final String enrolledBy;
  final String enrolledByOriginal;
  final String currentlyManagedBy;
  final String subscriptionStatus;
  final String paymentMode;
  final DateTime? renewalDate;
  final DateTime? gracePeriodEnds;
  final String? ownerAuthUid;
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerPhone;
  final DateTime? createdAt;
  final Map<String, bool> activeCategories;

  final double? amountPaid;
  final double? setupFeePaid;
  final double? renewalAmountPaid;
  final String? lastPaymentLinkUrl;
  final String? lastRenewalLinkUrl;

  // ── Pre-aggregated Stats Summary (Business Rollup) ─────────────────────────
  final int totalScans;
  final int googleReviewsOpened;
  final Map<String, int> starDistribution;
  final Map<String, Map<String, dynamic>> monthlyStats;

  const BusinessModel({
    required this.id,
    this.businessCode,
    this.businessNumber,
    this.isTestAccount = false,
    required this.brandName,
    required this.logoUrl,
    required this.categoryType,
    this.defaultCategoryTemplateId,
    required this.enrolledBy,
    required this.enrolledByOriginal,
    required this.currentlyManagedBy,
    required this.subscriptionStatus,
    this.paymentMode = 'pending',
    this.renewalDate,
    this.gracePeriodEnds,
    this.ownerAuthUid,
    this.ownerEmail,
    this.ownerName,
    this.ownerPhone,
    this.createdAt,
    this.activeCategories = const {},
    this.amountPaid,
    this.setupFeePaid,
    this.renewalAmountPaid,
    this.lastPaymentLinkUrl,
    this.lastRenewalLinkUrl,
    this.totalScans = 0,
    this.googleReviewsOpened = 0,
    this.starDistribution = const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
    this.monthlyStats = const {},
  });

  factory BusinessModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawActive = d['active_categories'] as Map<String, dynamic>? ?? {};
    final stats = d['stats_summary'] as Map<String, dynamic>? ?? {};
    final rawStars = stats['star_counts'] as Map<String, dynamic>? ?? stats['star_distribution'] as Map<String, dynamic>? ?? {};

    final starsMap = <String, int>{
      '1': (rawStars['1'] as num? ?? 0).toInt(),
      '2': (rawStars['2'] as num? ?? 0).toInt(),
      '3': (rawStars['3'] as num? ?? 0).toInt(),
      '4': (rawStars['4'] as num? ?? 0).toInt(),
      '5': (rawStars['5'] as num? ?? 0).toInt(),
    };

    final rawMonthly = d['monthly_stats'] as Map<String, dynamic>? ?? {};
    final parsedMonthly = <String, Map<String, dynamic>>{};
    rawMonthly.forEach((mKey, val) {
      if (val is Map<String, dynamic>) {
        final mStars = val['star_counts'] as Map<String, dynamic>? ??
            val['star_distribution'] as Map<String, dynamic>? ?? {};
        parsedMonthly[mKey] = {
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

    return BusinessModel(
      id:                         doc.id,
      businessCode:               d['business_code']                 as String?,
      businessNumber:             d['business_number']               as int?,
      isTestAccount:              d['is_test_account']               as bool? ?? false,
      brandName:                  d['brand_name']                    as String? ?? '',
      logoUrl:                    d['logo_url']                      as String? ?? '',
      categoryType:               d['category_type']                 as String? ?? '',
      defaultCategoryTemplateId:  d['default_category_template_id']  as String?,
      enrolledBy:                 d['enrolled_by']                   as String? ?? '',
      enrolledByOriginal:         d['enrolled_by_original']          as String? ?? '',
      currentlyManagedBy:         d['currently_managed_by']          as String? ?? '',
      subscriptionStatus:         d['subscription_status']           as String? ?? 'active',
      paymentMode:                d['payment_mode']                  as String? ?? 'pending',
      renewalDate:                (d['renewal_date']    as Timestamp?)?.toDate(),
      gracePeriodEnds:            (d['grace_period_ends'] as Timestamp?)?.toDate(),
      ownerAuthUid:               d['owner_auth_uid']                as String?,
      ownerEmail:                 d['owner_email']                   as String?,
      ownerName:                  d['owner_name']                    as String?,
      ownerPhone:                 d['owner_phone']                   as String?,
      createdAt:                  (d['created_at']      as Timestamp?)?.toDate(),
      activeCategories:           rawActive.map((k, v) => MapEntry(k, v as bool? ?? true)),
      amountPaid:                 (d['amount_paid']     as num?)?.toDouble(),
      setupFeePaid:               (d['setup_fee_paid']  as num?)?.toDouble(),
      renewalAmountPaid:          (d['renewal_amount_paid'] as num?)?.toDouble(),
      lastPaymentLinkUrl:         d['last_payment_link_url'] as String?,
      lastRenewalLinkUrl:         d['last_renewal_link_url'] as String?,
      totalScans:                 (stats['total_scans'] as num? ?? 0).toInt(),
      googleReviewsOpened:        (stats['total_reviews_redirected'] as num? ?? stats['google_reviews_opened'] as num? ?? 0).toInt(),
      starDistribution:           starsMap,
      monthlyStats:               parsedMonthly,
    );
  }

  /// Human-friendly display code: APT-01001, TEST-00001, or fallback to short ID.
  String get displayCode => businessCode ?? (isTestAccount ? 'TEST' : (id.length > 8 ? id.substring(0, 8) : id));

  bool get isPendingPayment => subscriptionStatus == 'pending_payment';
  bool get isActive => subscriptionStatus == 'active';
  bool get isGracePeriod => subscriptionStatus == 'grace_period';

  /// Returns true if renewal is within [days] days from now.
  bool isDueSoon(int days) {
    if (renewalDate == null) return false;
    final diff = renewalDate!.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= days;
  }

  bool get isReassigned => false;

  /// Creates a copy with specified fields replaced.
  BusinessModel copyWith({
    String?   businessCode,
    int?      businessNumber,
    bool?     isTestAccount,
    String?   brandName,
    String?   logoUrl,
    String?   categoryType,
    String?   defaultCategoryTemplateId,
    String?   enrolledBy,
    String?   enrolledByOriginal,
    String?   currentlyManagedBy,
    String?   subscriptionStatus,
    String?   paymentMode,
    DateTime? renewalDate,
    DateTime? gracePeriodEnds,
    String?   ownerAuthUid,
    String?   ownerEmail,
    String?   ownerName,
    String?   ownerPhone,
    DateTime? createdAt,
    Map<String, bool>? activeCategories,
    double?   amountPaid,
    double?   setupFeePaid,
    double?   renewalAmountPaid,
    String?   lastPaymentLinkUrl,
    String?   lastRenewalLinkUrl,
  }) => BusinessModel(
    id:                        id,
    businessCode:              businessCode ?? this.businessCode,
    businessNumber:            businessNumber ?? this.businessNumber,
    isTestAccount:             isTestAccount ?? this.isTestAccount,
    brandName:                 brandName ?? this.brandName,
    logoUrl:                   logoUrl   ?? this.logoUrl,
    categoryType:              categoryType ?? this.categoryType,
    defaultCategoryTemplateId: defaultCategoryTemplateId ?? this.defaultCategoryTemplateId,
    enrolledBy:                enrolledBy ?? this.enrolledBy,
    enrolledByOriginal:        enrolledByOriginal ?? this.enrolledByOriginal,
    currentlyManagedBy:        currentlyManagedBy ?? this.currentlyManagedBy,
    subscriptionStatus:        subscriptionStatus ?? this.subscriptionStatus,
    paymentMode:               paymentMode ?? this.paymentMode,
    renewalDate:               renewalDate ?? this.renewalDate,
    gracePeriodEnds:           gracePeriodEnds ?? this.gracePeriodEnds,
    ownerAuthUid:              ownerAuthUid ?? this.ownerAuthUid,
    ownerEmail:                ownerEmail ?? this.ownerEmail,
    ownerName:                 ownerName  ?? this.ownerName,
    ownerPhone:                ownerPhone ?? this.ownerPhone,
    createdAt:                 createdAt ?? this.createdAt,
    activeCategories:          activeCategories ?? this.activeCategories,
    amountPaid:                amountPaid ?? this.amountPaid,
    setupFeePaid:              setupFeePaid ?? this.setupFeePaid,
    renewalAmountPaid:         renewalAmountPaid ?? this.renewalAmountPaid,
    lastPaymentLinkUrl:        lastPaymentLinkUrl ?? this.lastPaymentLinkUrl,
    lastRenewalLinkUrl:        lastRenewalLinkUrl ?? this.lastRenewalLinkUrl,
    totalScans:                totalScans,
    googleReviewsOpened:       googleReviewsOpened,
    starDistribution:          starDistribution,
    monthlyStats:              monthlyStats,
  );
}
