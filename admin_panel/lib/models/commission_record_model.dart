// lib/models/commission_record_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CommissionRecordModel {
  final String id;
  final String employeeId;
  final String businessId;
  final double amount;
  final String paymentMode; // "online" | "cash"
  final String status;      // "pending" | "verified" | "paid"
  final DateTime? dateClaimed;
  final DateTime? dateVerified;

  // Populated client-side after joining with businesses collection
  final String? businessName;

  const CommissionRecordModel({
    required this.id,
    required this.employeeId,
    required this.businessId,
    required this.amount,
    required this.paymentMode,
    required this.status,
    this.dateClaimed,
    this.dateVerified,
    this.businessName,
  });

  factory CommissionRecordModel.fromDoc(DocumentSnapshot doc, {String? businessName}) {
    final d = doc.data() as Map<String, dynamic>;
    return CommissionRecordModel(
      id:           doc.id,
      employeeId:   d['employee_id'] as String? ?? '',
      businessId:   d['business_id'] as String? ?? '',
      amount:       (d['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode:  d['payment_mode'] as String? ?? '',
      status:       d['status'] as String? ?? '',
      dateClaimed:  (d['date_claimed'] as Timestamp?)?.toDate(),
      dateVerified: (d['date_verified'] as Timestamp?)?.toDate(),
      businessName: businessName,
    );
  }

  static Map<String, dynamic> newCashRecord({
    required String employeeId,
    required String businessId,
    required double amount,
  }) => {
    'employee_id':   employeeId,
    'business_id':   businessId,
    'amount':        amount,
    'payment_mode':  'cash',
    'status':        'pending',  // doc 06 two-step verification handles the rest
    'date_claimed':  Timestamp.now(),
    'date_verified': null,
  };
}
