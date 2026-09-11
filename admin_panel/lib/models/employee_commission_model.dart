// lib/models/employee_commission_model.dart
// Employee commission ledger model (Build B).
// Tracks per-activation employee earnings. NEVER deleted.

import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeCommissionModel {
  final String id;
  final String employeeId;
  final String businessId;
  final String businessName;
  final double amount;
  final String status; // 'pending' | 'paid'
  final DateTime? createdAt;
  final String activationMonth; // 'YYYY-MM'
  final DateTime? paidAt;
  final String? paidBy;
  final String? payoutReference;

  const EmployeeCommissionModel({
    required this.id,
    required this.employeeId,
    required this.businessId,
    required this.businessName,
    required this.amount,
    required this.status,
    this.createdAt,
    required this.activationMonth,
    this.paidAt,
    this.paidBy,
    this.payoutReference,
  });

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    return null;
  }

  factory EmployeeCommissionModel.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final d = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    return EmployeeCommissionModel(
      id:              doc.id,
      employeeId:      d['employee_id']?.toString() ?? '',
      businessId:      d['business_id']?.toString() ?? '',
      businessName:    d['business_name']?.toString() ?? '',
      amount:          (d['amount'] as num?)?.toDouble() ?? 0.0,
      status:          d['status']?.toString() ?? 'pending',
      createdAt:       _parseDate(d['created_at']),
      activationMonth: d['activation_month']?.toString() ?? '',
      paidAt:          _parseDate(d['paid_at']),
      paidBy:          d['paid_by']?.toString(),
      payoutReference: d['payout_reference']?.toString(),
    );
  }
}
