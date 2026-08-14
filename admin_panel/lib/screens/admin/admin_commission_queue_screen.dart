// lib/screens/admin/admin_commission_queue_screen.dart
//
// Commission Verification Queue & Payout Screen for Admin (Doc 04 / Doc 06).
// Features:
//   - Lists cash pending & disputed commission records.
//   - Admin confirms physical cash receipt via adminConfirmCashPayment.
//   - Enforces two-step verification gate: record flips to "verified" ONLY when BOTH admin + owner confirm.
//   - Mark Paid action for verified records requiring payout reference.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/commission_record_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';

class AdminCommissionQueueScreen extends StatelessWidget {
  const AdminCommissionQueueScreen({super.key});

  void _showMarkPaidDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    CommissionRecordModel record,
    String adminUid,
  ) {
    final refCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark Commission Paid — ₹${record.amount.toStringAsFixed(0)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee: ${record.employeeId}'),
            Text('Business: ${record.businessName ?? record.businessId}'),
            const SizedBox(height: 16),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'Payout Reference (UTR / Transaction ID) *',
                hintText: 'e.g. UTR_1234567890',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (refCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payout reference is required.')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              try {
                await provider.markCommissionPaid(
                  recordId: record.id,
                  payoutReference: refCtrl.text.trim(),
                  adminUid: adminUid,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Commission marked as paid!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Confirm Payout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final auth = context.watch<AppAuthProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final adminUid = auth.uid ?? 'admin';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info box
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
                        'Two-Step Cash Fraud Gate — Admin Verification Queue (Doc 04 / 06)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cash payment verification requires BOTH (A) Admin confirmation of physical receipt AND (B) Business owner independent confirmation before flipping to "verified". Neither admin nor owner alone can verify.',
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
            'Cash Payment Verification & Payout Queue',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          StreamBuilder<List<CommissionRecordModel>>(
            stream: provider.watchCommissionQueue(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data ?? [];
              if (records.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No pending cash records requiring admin verification.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }

              final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final r = records[idx];
                  final dateStr = r.dateClaimed != null ? dateFormat.format(r.dateClaimed!) : 'Unknown date';

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: r.isDisputed ? scheme.error : scheme.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${r.businessName ?? r.businessId} — ₹${r.amount.toStringAsFixed(0)}',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Chip(
                                label: Text(r.status.toUpperCase()),
                                backgroundColor: r.isDisputed
                                    ? AppColors.commDisputedBg
                                    : (r.isVerified ? AppColors.commVerifiedBg : AppColors.commPendingBg),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: r.isDisputed
                                      ? AppColors.commDisputedFg
                                      : (r.isVerified ? AppColors.commVerifiedFg : AppColors.commPendingFg),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Logged by Employee: ${r.employeeId} on $dateStr'),
                          const SizedBox(height: 8),

                          // Status Badges
                          Row(
                            children: [
                              _buildStatusBadge(
                                context,
                                label: 'Admin Cash Received',
                                confirmed: r.adminConfirmed,
                              ),
                              const SizedBox(width: 12),
                              _buildStatusBadge(
                                context,
                                label: 'Owner Confirmation',
                                confirmed: r.ownerConfirmed == true,
                                isDisputed: r.isDisputed,
                              ),
                            ],
                          ),

                          if (r.isDisputed) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '⚠️ Owner Reported Dispute: ${r.disputeReason ?? "Payment not received by owner."}',
                                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!r.adminConfirmed)
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await provider.adminConfirmCashPayment(
                                      recordId: r.id,
                                      adminUid: adminUid,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Admin cash receipt confirmed.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Confirm Cash Received (Admin)'),
                                ),
                              if (r.isVerified) ...[
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _showMarkPaidDialog(context, provider, r, adminUid),
                                  icon: const Icon(Icons.payments, size: 16),
                                  label: const Text('Mark Paid'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    BuildContext context, {
    required String label,
    required bool confirmed,
    bool isDisputed = false,
  }) {
    Color bg = Colors.orange.withValues(alpha: 0.15);
    Color fg = Colors.orange;
    String statusText = 'Pending';

    if (isDisputed) {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red;
      statusText = 'Disputed';
    } else if (confirmed) {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green;
      statusText = 'Confirmed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(confirmed ? Icons.check_circle : (isDisputed ? Icons.warning : Icons.schedule), size: 14, color: fg),
          const SizedBox(width: 6),
          Text('$label: $statusText', style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}
