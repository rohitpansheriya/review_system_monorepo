// lib/screens/admin/admin_commission_queue_stub.dart
//
// ============================================================================
// STUB: Admin Commission Verification Queue (Doc 04 — Admin Panel)
// ============================================================================
//
// This UI screen will be built in 04-admin-panel.md.
// The backend service methods, security rules, and data models are fully built
// and tested in 06-commission-tracking.md.
//
// Architecture & Service Contract:
// 1. Data Query:
//    - FirestoreService.watchCommissionVerificationQueue()
//    - Reads commission_records where payment_mode == 'cash' AND status in ['pending', 'disputed'].
//
// 2. Admin Actions:
//    - FirestoreService.adminConfirmCashPayment(recordId, adminUid, notes)
//      Confirms physical receipt of cash. Flips record to 'verified' if owner has also confirmed.
//    - FirestoreService.markCommissionPaid(recordId, payoutReference, adminUid)
//      Flips 'verified' record to 'paid' when payout is disbursed.
//
// 3. UI Requirements for Doc 04:
//    - Table/List showing:
//        * Business Name & ID
//        * Employee Name & ID
//        * Amount (₹)
//        * Date Claimed
//        * Owner Confirmation Status (✓ Confirmed / ⏳ Pending / ⚠️ Disputed)
//        * Admin Confirmation Status (✓ Received / ⏳ Pending)
//        * Actions: [Confirm Cash Received], [View Dispute Details], [Mark Paid]

import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../models/commission_record_model.dart';
import '../../core/theme.dart';

class AdminCommissionQueueStubScreen extends StatelessWidget {
  final FirestoreService _firestoreService;

  AdminCommissionQueueStubScreen({
    super.key,
    FirestoreService? firestoreService,
  }) : _firestoreService = firestoreService ?? FirestoreService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Commission Verification Queue (STUB - Doc 04)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.primary),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Two-Step Cash Fraud Gate — Admin Queue (Doc 04 / 06)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cash payments logged by employees require (A) Admin confirmation of physical receipt AND (B) Business owner confirmation before flipping from "pending" to "verified".',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Active Verification Queue (Live Stream)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<CommissionRecordModel>>(
                stream: _firestoreService.watchCommissionVerificationQueue(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return Center(
                      child: Text(
                        'No pending cash records in the verification queue.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, idx) {
                      final r = records[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: r.isDisputed
                              ? AppColors.commDisputedBg
                              : AppColors.commPendingBg,
                          child: Icon(
                            r.isDisputed ? Icons.warning_amber : Icons.money,
                            color: r.isDisputed ? AppColors.commDisputedFg : AppColors.commPendingFg,
                          ),
                        ),
                        title: Text('${r.businessName ?? r.businessId} — ₹${r.amount.toStringAsFixed(0)}'),
                        subtitle: Text(
                          'Employee: ${r.employeeId}\n'
                          'Owner Status: ${r.ownerConfirmed == true ? "✓ Confirmed" : r.isDisputed ? "⚠️ Disputed" : "Pending"} | '
                          'Admin Status: ${r.adminConfirmed ? "✓ Confirmed" : "Pending"}',
                        ),
                        trailing: Text(
                          r.status.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: r.isDisputed ? AppColors.commDisputedFg : AppColors.commPendingFg,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
