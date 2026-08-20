// lib/models/commission_record_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CommissionRecordModel {
  final String id;
  final String employeeId;
  final String businessId;
  final double amount;
  final String paymentMode; // "online" | "cash"
  final String status;      // "pending" | "verified" | "paid" | "disputed"
  final DateTime? dateClaimed;
  final DateTime? dateVerified;
  final DateTime? datePaid;
  final String? payoutReference;

  // Two-step verification fraud-gate fields (doc 06)
  // New flow: Employee collects cash → Admin confirms deposit → Business activates.
  // Owner is NOT part of the cash confirmation gate.
  final bool employeeCollected;
  final bool adminConfirmed;
  final String? adminConfirmedBy;
  final DateTime? adminConfirmedAt;
  final bool? ownerConfirmed;      // Legacy — kept for reading old records
  final DateTime? ownerConfirmedAt; // Legacy
  final String? ownerResponse;     // Legacy
  final bool disputed;
  final String? disputeReason;

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
    this.datePaid,
    this.payoutReference,
    this.employeeCollected = false,
    this.adminConfirmed = false,
    this.adminConfirmedBy,
    this.adminConfirmedAt,
    this.ownerConfirmed,
    this.ownerConfirmedAt,
    this.ownerResponse,
    this.disputed = false,
    this.disputeReason,
    this.businessName,
  });

  bool get isCash => paymentMode == 'cash';
  bool get isOnline => paymentMode == 'online';
  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isPaid => status == 'paid';
  bool get isDisputed => status == 'disputed' || disputed;

  factory CommissionRecordModel.fromDoc(DocumentSnapshot doc, {String? businessName}) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return CommissionRecordModel(
      id:               doc.id,
      employeeId:       d['employee_id'] as String? ?? '',
      businessId:       d['business_id'] as String? ?? '',
      amount:           (d['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode:      d['payment_mode'] as String? ?? 'cash',
      status:           d['status'] as String? ?? 'pending',
      dateClaimed:      (d['date_claimed'] as Timestamp?)?.toDate(),
      dateVerified:     (d['date_verified'] as Timestamp?)?.toDate(),
      datePaid:         (d['date_paid'] as Timestamp?)?.toDate(),
      payoutReference:  d['payout_reference'] as String?,
      employeeCollected: (d['employee_collected'] as bool?) ?? false,
      adminConfirmed:   (d['admin_confirmed'] as bool?) ?? false,
      adminConfirmedBy: d['admin_confirmed_by'] as String?,
      adminConfirmedAt: (d['admin_confirmed_at'] as Timestamp?)?.toDate(),
      ownerConfirmed:   d['owner_confirmed'] as bool?,
      ownerConfirmedAt: (d['owner_confirmed_at'] as Timestamp?)?.toDate(),
      ownerResponse:    d['owner_response'] as String?,
      disputed:         (d['disputed'] as bool?) ?? false,
      disputeReason:    d['dispute_reason'] as String?,
      businessName:     businessName,
    );
  }

  // newCashRecord() REMOVED — employees no longer create cash payment records.
  // Cash payments are now handled as a view on businesses (Build A).
  // Commission entries are created by the onBusinessActivated CF (Build B).
}
