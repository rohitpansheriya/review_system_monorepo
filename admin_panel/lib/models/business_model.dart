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
  final String? managerWhatsapp;
  final DateTime? createdAt;
  final Map<String, bool> activeCategories;

  // ── Business-Specific Custom Review Phrase Pool, Services & 3-Step Chips ────
  final bool hasCustomPhrases;
  final DateTime? phrasesCustomizedAt;
  final List<Map<String, dynamic>> customCategories;
  final List<Map<String, dynamic>>? services;
  final Map<String, List<String>>? stepCategories;
  final List<String>? negativeFeedbackChips;
  final String? archetype;
  final String reviewLanguagePreference;

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
    this.managerWhatsapp,
    this.createdAt,
    this.activeCategories = const {},
    this.hasCustomPhrases = false,
    this.phrasesCustomizedAt,
    this.customCategories = const [],
    this.services,
    this.stepCategories,
    this.negativeFeedbackChips,
    this.archetype,
    this.reviewLanguagePreference = 'english',
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

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    return null;
  }

  factory BusinessModel.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final d = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};

    final rawActive = d['active_categories'];
    final activeMap = <String, bool>{};
    if (rawActive is Map) {
      rawActive.forEach((k, v) {
        if (k != null) {
          activeMap[k.toString()] = v == true;
        }
      });
    }

    final rawCustom = d['custom_categories'];
    final parsedCustomCats = <Map<String, dynamic>>[];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map) {
          parsedCustomCats.add(Map<String, dynamic>.from(item));
        }
      }
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

    final rawStepCats = d['step_categories'] ?? d['custom_step_categories'];
    Map<String, List<String>>? parsedStepCats;
    if (rawStepCats is Map) {
      parsedStepCats = {};
      rawStepCats.forEach((k, v) {
        if (k != null && v is List) {
          parsedStepCats![k.toString()] = v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        }
      });
    }

    final hasCustom = d['has_custom_phrases'] as bool? ??
        (parsedCustomCats.isNotEmpty || (parsedStepCats != null && parsedStepCats.values.any((l) => l.isNotEmpty)));

    final rawNegative = d['negative_feedback_chips'];
    List<String>? parsedNegative;
    if (rawNegative is List) {
      parsedNegative = rawNegative.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final rawServices = d['services'];
    List<Map<String, dynamic>>? parsedServices;
    if (rawServices is List) {
      parsedServices = [];
      for (final item in rawServices) {
        if (item is Map) {
          parsedServices.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return BusinessModel(
      id:                         doc.id,
      businessCode:               d['business_code']?.toString(),
      businessNumber:             (d['business_number'] as num?)?.toInt(),
      isTestAccount:              d['is_test_account'] as bool? ?? false,
      brandName:                  d['brand_name']?.toString() ?? '',
      logoUrl:                    d['logo_url']?.toString() ?? '',
      categoryType:               d['category_type']?.toString() ?? '',
      defaultCategoryTemplateId:  d['default_category_template_id']?.toString(),
      enrolledBy:                 d['enrolled_by']?.toString() ?? '',
      enrolledByOriginal:         d['enrolled_by_original']?.toString() ?? '',
      currentlyManagedBy:         d['currently_managed_by']?.toString() ?? '',
      subscriptionStatus:         d['subscription_status']?.toString() ?? 'active',
      paymentMode:                d['payment_mode']?.toString() ?? 'pending',
      renewalDate:                _parseDate(d['renewal_date']),
      gracePeriodEnds:            _parseDate(d['grace_period_ends']),
      ownerAuthUid:               d['owner_auth_uid']?.toString(),
      ownerEmail:                 d['owner_email']?.toString(),
      ownerName:                  d['owner_name']?.toString(),
      ownerPhone:                 d['owner_phone']?.toString(),
      managerWhatsapp:            d['manager_whatsapp']?.toString() ?? d['managerWhatsapp']?.toString(),
      createdAt:                  _parseDate(d['created_at']),
      activeCategories:           activeMap,
      hasCustomPhrases:           hasCustom,
      phrasesCustomizedAt:        _parseDate(d['phrases_customized_at']),
      customCategories:           parsedCustomCats,
      services:                   parsedServices,
      stepCategories:             parsedStepCats,
      negativeFeedbackChips:      parsedNegative,
      archetype:                  d['archetype']?.toString(),
      reviewLanguagePreference:   d['review_language_preference']?.toString() ?? 'english',
      amountPaid:                 (d['amount_paid']     as num?)?.toDouble(),
      setupFeePaid:               (d['setup_fee_paid']  as num?)?.toDouble(),
      renewalAmountPaid:          (d['renewal_amount_paid'] as num?)?.toDouble(),
      lastPaymentLinkUrl:         d['last_payment_link_url']?.toString(),
      lastRenewalLinkUrl:         d['last_renewal_link_url']?.toString(),
      totalScans:                 (stats['total_scans'] as num? ?? d['stats_summary.total_scans'] as num? ?? d['total_scans'] as num? ?? 0).toInt(),
      googleReviewsOpened:        (stats['google_reviews_opened'] as num? ?? stats['total_reviews_redirected'] as num? ?? stats['monthly_google_reviews'] as num? ?? d['stats_summary.google_reviews_opened'] as num? ?? 0).toInt(),
      starDistribution:           starsMap,
      monthlyStats:               parsedMonthly,
    );
  }

  /// Human-friendly display code: APT-01001, TEST-00001, or fallback to short ID.
  String get displayCode => businessCode ?? (isTestAccount ? 'TEST' : (id.length > 8 ? id.substring(0, 8) : id));

  /// Total count of phrases across all custom categories.
  int get totalCustomPhrases {
    int count = 0;
    for (final cat in customCategories) {
      final pool = cat['phrase_pool'];
      if (pool is List) count += pool.length;
    }
    return count;
  }

  /// Total count of chips across all 3 steps.
  int get totalStepChips {
    if (stepCategories == null) return 0;
    int count = 0;
    for (final list in stepCategories!.values) {
      count += list.length;
    }
    return count;
  }

  bool get hasStepCategories =>
      stepCategories != null &&
      (stepCategories!['step1']?.isNotEmpty == true ||
          stepCategories!['step2']?.isNotEmpty == true ||
          stepCategories!['step3']?.isNotEmpty == true);

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
    bool?     hasCustomPhrases,
    DateTime? phrasesCustomizedAt,
    List<Map<String, dynamic>>? customCategories,
    Map<String, List<String>>? stepCategories,
    List<String>? negativeFeedbackChips,
    String?   archetype,
    String?   reviewLanguagePreference,
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
    hasCustomPhrases:          hasCustomPhrases ?? this.hasCustomPhrases,
    phrasesCustomizedAt:       phrasesCustomizedAt ?? this.phrasesCustomizedAt,
    customCategories:          customCategories ?? this.customCategories,
    stepCategories:            stepCategories ?? this.stepCategories,
    negativeFeedbackChips:     negativeFeedbackChips ?? this.negativeFeedbackChips,
    archetype:                 archetype ?? this.archetype,
    reviewLanguagePreference:  reviewLanguagePreference ?? this.reviewLanguagePreference,
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
