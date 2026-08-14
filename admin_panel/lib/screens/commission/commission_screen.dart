// lib/screens/commission/commission_screen.dart
// Commission tracker: totals, record list, Log Cash Payment action.
// Styling: all Colors.* replaced with AppTheme semantic tokens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/commission_record_model.dart';
import '../../models/business_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/commission_provider.dart';

class CommissionScreen extends StatefulWidget {
  const CommissionScreen({super.key});

  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AppAuthProvider>().uid;
      if (uid != null) {
        context.read<CommissionProvider>().startListening(uid);
      }
    });
  }

  void _showLogCashDialog() {
    showDialog(
      context: context,
      builder: (_) => _LogCashDialog(
        employeeId: context.read<AppAuthProvider>().uid!,
        businesses: context.read<CommissionProvider>().myBizList,
        provider:   context.read<CommissionProvider>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AppAuthProvider>();
    final provider = context.watch<CommissionProvider>();
    final employee = auth.employee;
    final scheme   = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title:   const Text('Commission Tracker'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLogCashDialog,
        icon:  const Icon(Icons.payments_outlined),
        label: const Text('Log Cash Payment'),
      ),

      body: Column(
        children: [
          // ── Summary bar ─────────────────────────────────────────────────
          if (employee != null)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.primaryContainer.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topLeft,
                  end:   Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon:  Icons.business_outlined,
                      label: 'Total enrolled',
                      value: '${employee.totalEnrollments}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon:  Icons.calendar_month_outlined,
                      label: 'This month',
                      value: '${employee.thisMonthEnrollments}',
                    ),
                  ),
                ],
              ),
            ),

          // ── Records list ────────────────────────────────────────────────
          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? _ErrorState(message: provider.error!)
                    : provider.records.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            itemCount: provider.records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (_, i) =>
                                _RecordCard(record: provider.records[i]),
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Commission record card ────────────────────────────────────────────────────
class _RecordCard extends StatelessWidget {
  final CommissionRecordModel record;
  const _RecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final statusBg = AppTheme.commissionStatusColor(record.status);
    final statusFg = AppTheme.commissionStatusForeground(record.status);
    final isCash   = record.paymentMode == 'cash';
    final dateStr  = record.dateClaimed != null
        ? DateFormat('d MMM yyyy').format(record.dateClaimed!)
        : '—';
    final amountStr = '₹${record.amount.toStringAsFixed(0)}';

    // Avatar colors: cash → amber semantic, online → primary brand
    final avatarBg = isCash ? AppColors.pendingBg  : AppColors.secondary.withValues(alpha: 0.12);
    final avatarFg = isCash ? AppColors.pendingFg  : AppColors.secondary;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: avatarBg,
          child: Icon(
            isCash ? Icons.money_outlined : Icons.credit_card_outlined,
            color: avatarFg,
          ),
        ),
        title: Text(
          record.businessName ?? record.businessId,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$amountStr · ${record.paymentMode.toUpperCase()} · $dateStr',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            if (isCash && record.status == 'pending') ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _VerificationChip(
                    label: 'Admin: ${record.adminConfirmed ? '✓ Received' : 'Pending'}',
                    confirmed: record.adminConfirmed,
                  ),
                  _VerificationChip(
                    label: 'Owner: ${record.ownerConfirmed == true ? '✓ Confirmed' : (record.disputed ? '⚠️ Disputed' : 'Pending')}',
                    confirmed: record.ownerConfirmed == true,
                    isDisputed: record.disputed,
                  ),
                ],
              ),
            ] else if (record.isDisputed) ...[
              Text(
                '⚠️ Disputed by business owner: ${record.disputeReason ?? "Payment unconfirmed"}',
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ] else if (record.isPaid && record.payoutReference != null) ...[
              Text(
                '✓ Payout Reference: ${record.payoutReference}',
                style: const TextStyle(fontSize: 11, color: AppColors.activeFg),
              ),
            ] else if (record.isVerified) ...[
              const Text(
                '✓ Verified (queued for payout)',
                style: TextStyle(fontSize: 11, color: AppColors.secondary),
              ),
            ],
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        statusBg,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border:       Border.all(color: statusFg.withValues(alpha: 0.4), width: 0.8),
          ),
          child: Text(
            record.status.toUpperCase(),
            style: TextStyle(
              fontSize:   10,
              fontWeight: FontWeight.w700,
              color:      statusFg,
            ),
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _VerificationChip extends StatelessWidget {
  final String label;
  final bool confirmed;
  final bool isDisputed;

  const _VerificationChip({
    required this.label,
    required this.confirmed,
    this.isDisputed = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDisputed
        ? Colors.red.withValues(alpha: 0.12)
        : confirmed
            ? AppColors.activeBg
            : AppColors.pendingBg;
    final fg = isDisputed
        ? Colors.red
        : confirmed
            ? AppColors.activeFg
            : AppColors.pendingFg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Log cash payment dialog ───────────────────────────────────────────────────
class _LogCashDialog extends StatefulWidget {
  final String             employeeId;
  final List<BusinessModel> businesses;
  final CommissionProvider  provider;

  const _LogCashDialog({
    required this.employeeId,
    required this.businesses,
    required this.provider,
  });

  @override
  State<_LogCashDialog> createState() => _LogCashDialogState();
}

class _LogCashDialogState extends State<_LogCashDialog> {
  String? _selectedBizId;
  final   _amountCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_selectedBizId == null) {
      setState(() => _error = 'Please select a business.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    setState(() => _error = null);

    final err = await widget.provider.logCashPayment(
      employeeId: widget.employeeId,
      businessId: _selectedBizId!,
      amount:     amount,
    );

    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:         Text('✅ Cash payment logged (verification request sent to owner)'),
          backgroundColor: AppColors.activeFg,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = widget.provider.submitting;
    final scheme     = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Log Cash Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize:        MainAxisSize.min,
          crossAxisAlignment:  CrossAxisAlignment.stretch,
          children: [
            if (widget.businesses.isEmpty)
              const Text('No businesses found. Enroll a business first.')
            else ...[
              DropdownButtonFormField<String>(
                value: _selectedBizId,
                decoration: const InputDecoration(labelText: 'Business'),
                hint: const Text('Select business'),
                items: widget.businesses
                    .map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(b.brandName, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBizId = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller:  _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText:  'Amount collected (₹)',
                  prefixText: '₹ ',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Two-Step Fraud Prevention Gate (Doc 06)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: scheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1. An automated verification notice is sent to the business owner.\n'
                      '2. Admin verifies physical cash receipt in the verification queue.\n'
                      'Status flips to "verified" only when BOTH confirmations are in.',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (submitting || widget.businesses.isEmpty) ? null : _submit,
          child: submitting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Log payment'),
        ),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.w700,
                color:      scheme.onPrimaryContainer,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:    scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color:        scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size:  44,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No commission records yet.',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Records appear here after you log a cash payment\nor after a successful Razorpay checkout.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Error: $message',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
