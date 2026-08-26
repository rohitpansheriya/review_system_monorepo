// lib/models/business_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String id;
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

  const BusinessModel({
    required this.id,
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
  });

  factory BusinessModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawActive = d['active_categories'] as Map<String, dynamic>? ?? {};
    return BusinessModel(
      id:                         doc.id,
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
    );
  }

  /// Returns true if renewal is within [days] days from now.
  bool isDueSoon(int days) {
    if (renewalDate == null) return false;
    final diff = renewalDate!.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= days;
  }

  bool get isReassigned => currentlyManagedBy == 'admin';

  /// Creates a copy with specified employee-editable fields replaced.
  BusinessModel copyWith({
    String?  brandName,
    String?  logoUrl,
    String?  categoryType,
    String?  defaultCategoryTemplateId,
    String?  ownerName,
    String?  ownerEmail,
    String?  ownerPhone,
    String?  paymentMode,
    Map<String, bool>? activeCategories,
  }) => BusinessModel(
    id:                        id,
    brandName:                 brandName ?? this.brandName,
    logoUrl:                   logoUrl   ?? this.logoUrl,
    categoryType:              categoryType ?? this.categoryType,
    defaultCategoryTemplateId: defaultCategoryTemplateId ?? this.defaultCategoryTemplateId,
    enrolledBy:                enrolledBy,
    enrolledByOriginal:        enrolledByOriginal,
    currentlyManagedBy:        currentlyManagedBy,
    subscriptionStatus:        subscriptionStatus,
    paymentMode:               paymentMode ?? this.paymentMode,
    renewalDate:               renewalDate,
    gracePeriodEnds:           gracePeriodEnds,
    ownerAuthUid:              ownerAuthUid,
    ownerEmail:                ownerEmail ?? this.ownerEmail,
    ownerName:                 ownerName  ?? this.ownerName,
    ownerPhone:                ownerPhone ?? this.ownerPhone,
    createdAt:                 createdAt,
    activeCategories:           activeCategories ?? this.activeCategories,
  );
}
