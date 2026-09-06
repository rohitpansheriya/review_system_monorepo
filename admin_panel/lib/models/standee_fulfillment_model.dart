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

  // Enrolling employee info (for batch delivery to employee)
  final String? enrolledBy;
  String? enrolledByName;
  String? enrolledByPhone;
  String? enrolledByAddress;

  // Courier & Delivery details
  String? courierName;
  String? courierAwb;
  DateTime? shippedAt;
  DateTime? deliveredAt;
  String? deliveredVia; // 'first_scan_detected' | 'manual_admin'

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
    this.enrolledBy,
    this.enrolledByName,
    this.enrolledByPhone,
    this.enrolledByAddress,
    this.courierName,
    this.courierAwb,
    this.shippedAt,
    this.deliveredAt,
    this.deliveredVia,
  });

  factory StandeeFulfillmentModel.fromDoc({
    required String businessId,
    required String businessName,
    required String categoryType,
    String? ownerPhone,
    String? ownerEmail,
    String? enrolledBy,
    String? enrolledByName,
    String? enrolledByPhone,
    String? enrolledByAddress,
    required DocumentSnapshot branchDoc,
  }) {
    final d = branchDoc.data() as Map<String, dynamic>? ?? {};
    final branchEnrolledBy = d['enrolled_by'] as String? ?? enrolledBy;

    return StandeeFulfillmentModel(
      businessId: businessId,
      businessName: businessName,
      categoryType: categoryType,
      ownerPhone: ownerPhone,
      ownerEmail: ownerEmail,
      branchId: branchDoc.id,
      branchName: d['branch_name'] as String? ?? businessName,
      address: d['address'] as String? ?? '',
      standeeStatus: d['standee_status'] as String? ?? AppConstants.standeeOrdered,
      standeeStatusUpdatedAt: (d['standee_status_updated_at'] as Timestamp?)?.toDate(),
      qrCodeId: d['qr_code_id'] as String?,
      plainQrStoragePath: d['plain_qr_storage_path'] as String?,
      enrolledBy: branchEnrolledBy,
      enrolledByName: enrolledByName,
      enrolledByPhone: enrolledByPhone,
      enrolledByAddress: enrolledByAddress,
      courierName: d['courier_name'] as String?,
      courierAwb: d['courier_awb'] as String?,
      shippedAt: (d['shipped_at'] as Timestamp?)?.toDate(),
      deliveredAt: (d['delivered_at'] as Timestamp?)?.toDate(),
      deliveredVia: d['delivered_via'] as String?,
    );
  }
}
