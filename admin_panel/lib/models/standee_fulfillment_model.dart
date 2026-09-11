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

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    return null;
  }

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
    final rawData = branchDoc.data();
    final d = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    final branchEnrolledBy = d['enrolled_by']?.toString() ?? enrolledBy;

    return StandeeFulfillmentModel(
      businessId: businessId,
      businessName: businessName,
      categoryType: categoryType,
      ownerPhone: ownerPhone,
      ownerEmail: ownerEmail,
      branchId: branchDoc.id,
      branchName: d['branch_name']?.toString() ?? businessName,
      address: d['address']?.toString() ?? '',
      standeeStatus: d['standee_status']?.toString() ?? AppConstants.standeeOrdered,
      standeeStatusUpdatedAt: _parseDate(d['standee_status_updated_at']),
      qrCodeId: d['qr_code_id']?.toString(),
      plainQrStoragePath: d['plain_qr_storage_path']?.toString(),
      enrolledBy: branchEnrolledBy,
      enrolledByName: enrolledByName,
      enrolledByPhone: enrolledByPhone,
      enrolledByAddress: enrolledByAddress,
      courierName: d['courier_name']?.toString(),
      courierAwb: d['courier_awb']?.toString(),
      shippedAt: _parseDate(d['shipped_at']),
      deliveredAt: _parseDate(d['delivered_at']),
      deliveredVia: d['delivered_via']?.toString(),
    );
  }
}
