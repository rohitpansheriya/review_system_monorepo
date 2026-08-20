// lib/models/standee_fulfillment_model.dart
// Form-state / view model representing one branch standee fulfillment row in Admin Panel.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

class StandeeFulfillmentModel {
  final String businessId;
  final String businessName;
  final String categoryType;
  final String? ownerPhone;
  final String? ownerEmail;
  final String branchId;
  final String branchName;
  final String address;
  String standeeStatus;
  DateTime? standeeStatusUpdatedAt;
  final String? qrCodeId;
  final String? plainQrStoragePath;

  StandeeFulfillmentModel({
    required this.businessId,
    required this.businessName,
    required this.categoryType,
    this.ownerPhone,
    this.ownerEmail,
    required this.branchId,
    required this.branchName,
    required this.address,
    required this.standeeStatus,
    this.standeeStatusUpdatedAt,
    this.qrCodeId,
    this.plainQrStoragePath,
  });

  factory StandeeFulfillmentModel.fromDoc({
    required String businessId,
    required String businessName,
    required String categoryType,
    String? ownerPhone,
    String? ownerEmail,
    required DocumentSnapshot branchDoc,
  }) {
    final d = branchDoc.data() as Map<String, dynamic>? ?? {};
    return StandeeFulfillmentModel(
      businessId: businessId,
      businessName: businessName,
      categoryType: categoryType,
      ownerPhone: ownerPhone,
      ownerEmail: ownerEmail,
      branchId: branchDoc.id,
      branchName: d['branch_name'] as String? ?? businessName,
      address: d['address'] as String? ?? '',
      standeeStatus: d['standee_status'] as String? ?? AppConstants.standeeNotOrdered,
      standeeStatusUpdatedAt: (d['standee_status_updated_at'] as Timestamp?)?.toDate(),
      qrCodeId: d['qr_code_id'] as String?,
      plainQrStoragePath: d['plain_qr_storage_path'] as String?,
    );
  }
}
