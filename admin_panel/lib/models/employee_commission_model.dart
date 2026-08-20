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

  factory EmployeeCommissionModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return EmployeeCommissionModel(
      id:              doc.id,
      employeeId:      d['employee_id'] as String? ?? '',
      businessId:      d['business_id'] as String? ?? '',
      businessName:    d['business_name'] as String? ?? '',
      amount:          (d['amount'] as num?)?.toDouble() ?? 0.0,
      status:          d['status'] as String? ?? 'pending',
      createdAt:       (d['created_at'] as Timestamp?)?.toDate(),
      activationMonth: d['activation_month'] as String? ?? '',
      paidAt:          (d['paid_at'] as Timestamp?)?.toDate(),
      paidBy:          d['paid_by'] as String?,
      payoutReference: d['payout_reference'] as String?,
    );
  }
}
