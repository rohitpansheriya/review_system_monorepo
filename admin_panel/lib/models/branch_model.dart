// lib/models/branch_model.dart
//
// Schema additions (00-architecture-and-schema.md, branches/{id}):
//
//   plain_qr_storage_path   — Storage path of plain printable QR PNG (Change 1).
//                             Null until activation webhook generates it.
//   standee_status          — Fulfillment lifecycle: "not_ordered" | "printed" |
//                             "shipped" | "delivered" (Change 2).
//   standee_status_updated_at — Timestamp of last standee_status change (Change 2).
//   whatsapp_monitored_by   — Free-text: who watches this branch's WhatsApp
//                             channel for 1–3 star messages (Change 5).

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

  // ── Change 1: plain printable QR ────────────────────────────────────────────
  /// Firebase Storage path for the plain printable QR PNG.
  /// Null if the branch has not yet been activated (pending_payment draft).
  final String? plainQrStoragePath;

  // ── Change 2: standee fulfillment ───────────────────────────────────────────
  /// Current standee fulfillment state. One of AppConstants.standeeStatuses.
  /// Defaults to "not_ordered" at activation; employee updates on-site.
  final String standeeStatus;

  /// Timestamp of the last standee_status update. Null before first change.
  final DateTime? standeeStatusUpdatedAt;

  // ── Change 5: WhatsApp monitor ──────────────────────────────────────────────
  /// Free-text field: who is responsible for monitoring the WhatsApp number
  /// on this branch for incoming 1–3 star feedback messages.
  final String whatsappMonitoredBy;

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
    // Change 1
    this.plainQrStoragePath,
    // Change 2
    this.standeeStatus = AppConstants.standeeNotOrdered,
    this.standeeStatusUpdatedAt,
    // Change 5
    this.whatsappMonitoredBy = '',
  });

  factory BranchModel.fromDoc(DocumentSnapshot doc, {required String businessId}) {
    final d = doc.data() as Map<String, dynamic>;
    final rawRouting = d['star_routing_config'] as Map<String, dynamic>? ?? {};
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
      // Change 1
      plainQrStoragePath:     d['plain_qr_storage_path'] as String?,
      // Change 2
      standeeStatus:          d['standee_status']        as String?
                                  ?? AppConstants.standeeNotOrdered,
      standeeStatusUpdatedAt: (d['standee_status_updated_at'] as Timestamp?)?.toDate(),
      // Change 5
      whatsappMonitoredBy:    d['whatsapp_monitored_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toEditableFields() => {
    'branch_name':            branchName,
    'address':                address,
    'whatsapp_number':        whatsappNumber,
    'whatsapp_monitored_by':  whatsappMonitoredBy,
    'place_id':               placeId,
    'google_review_link':     googleReviewLink,
    'star_routing_config':    starRoutingConfig,
    'standee_status':         standeeStatus,
    'standee_status_updated_at': standeeStatusUpdatedAt,
  };

  Map<String, dynamic> toCreateMap() => {
    'branch_name':            branchName,
    'address':                address,
    'whatsapp_number':        whatsappNumber,
    'whatsapp_monitored_by':  whatsappMonitoredBy,    // Change 5
    'place_id':               placeId,
    'google_review_link':     googleReviewLink,
    'star_routing_config':    starRoutingConfig,
    'category_override_id':   null,
    'qr_code_id':             null,
    'nfc_tag_id':             null,
    'plain_qr_storage_path':  null,                  // Change 1: set on activation
    'standee_status':         AppConstants.standeeNotOrdered, // Change 2: default
    'standee_status_updated_at': null,               // Change 2: set on first change
    'stats_summary': {
      'total_scans':              0,
      'total_reviews_redirected': 0,
      'last_updated':             null,
    },
  };
}
