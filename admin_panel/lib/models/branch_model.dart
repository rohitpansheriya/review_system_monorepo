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

  // ── Pre-aggregated Stats Summary ───────────────────────────────────────────
  final int totalScans;
  final int googleReviewsOpened;
  final Map<String, int> starDistribution;

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
    this.standeeStatus = AppConstants.standeeNotOrdered,
    this.standeeStatusUpdatedAt,
    this.whatsappMonitoredBy = '',
    this.totalScans = 0,
    this.googleReviewsOpened = 0,
    this.starDistribution = const {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
  });

  factory BranchModel.fromDoc(DocumentSnapshot doc, {required String businessId}) {
    final d = doc.data() as Map<String, dynamic>;
    final rawRouting = d['star_routing_config'] as Map<String, dynamic>? ?? {};
    final stats = d['stats_summary'] as Map<String, dynamic>? ?? {};
    final rawStars = stats['star_counts'] as Map<String, dynamic>? ?? stats['star_distribution'] as Map<String, dynamic>? ?? {};

    final starsMap = <String, int>{
      '1': (rawStars['1'] as num? ?? 0).toInt(),
      '2': (rawStars['2'] as num? ?? 0).toInt(),
      '3': (rawStars['3'] as num? ?? 0).toInt(),
      '4': (rawStars['4'] as num? ?? 0).toInt(),
      '5': (rawStars['5'] as num? ?? 0).toInt(),
    };

    return BranchModel(
      id:               doc.id,
      businessId:       businessId,
      branchName:       d['branch_name']       as String? ?? '',
      address:          d['address']            as String? ?? '',
      whatsappNumber:   d['whatsapp_number']    as String? ?? '',
      placeId:          d['place_id']           as String?,
      googleReviewLink: d['google_review_link'] as String?,
      starRoutingConfig: rawRouting.map((k, v) => MapEntry(k, v as String)),
      qrCodeId:         d['qr_code_id']         as String?,
      nfcTagId:         d['nfc_tag_id']         as String?,
      plainQrStoragePath:     d['plain_qr_storage_path'] as String?,
      standeeStatus:          d['standee_status']        as String?
                                  ?? AppConstants.standeeNotOrdered,
      standeeStatusUpdatedAt: (d['standee_status_updated_at'] as Timestamp?)?.toDate(),
      whatsappMonitoredBy:    d['whatsapp_monitored_by'] as String? ?? '',
      totalScans:             (stats['total_scans'] as num? ?? 0).toInt(),
      googleReviewsOpened:    (stats['monthly_google_reviews'] as num? ?? stats['total_reviews_redirected'] as num? ?? 0).toInt(),
      starDistribution:       starsMap,
    );
  }

  BranchModel copyWith({
    String? branchName,
    String? address,
    String? whatsappNumber,
    Map<String, String>? starRoutingConfig,
    String? standeeStatus,
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
      totalScans: totalScans,
      googleReviewsOpened: googleReviewsOpened,
      starDistribution: starDistribution,
    );
  }
}
