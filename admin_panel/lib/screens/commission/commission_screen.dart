// lib/screens/commission/commission_screen.dart
// Commission tracker: totals, record list, Log Cash Payment action.

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
        provider: context.read<CommissionProvider>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AppAuthProvider>();
    final provider = context.watch<CommissionProvider>();
    final employee = auth.employee;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commission Tracker'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLogCashDialog,
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Log Cash Payment'),
      ),

      body: Column(
        children: [
          // ── Summary bar ─────────────────────────────────────────────────
          if (employee != null)
            Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.business_outlined,
                      label: 'Total enrolled',
                      value: '${employee.totalEnrollments}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.calendar_month_outlined,
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
                    ? Center(child: Text('Error: ${provider.error}'))
                    : provider.records.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            itemCount: provider.records.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
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
    final statusColor = AppTheme.commissionStatusColor(record.status);
    final dateStr = record.dateClaimed != null
        ? DateFormat('d MMM yyyy').format(record.dateClaimed!)
        : '—';
    final amountStr = '₹${record.amount.toStringAsFixed(0)}';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: record.paymentMode == 'cash'
              ? Colors.orange.shade50
              : Colors.blue.shade50,
          child: Icon(
            record.paymentMode == 'cash'
                ? Icons.money_outlined
                : Icons.credit_card_outlined,
            color: record.paymentMode == 'cash'
                ? Colors.orange.shade700
                : Colors.blue.shade700,
          ),
        ),
        title: Text(
          record.businessName ?? record.businessId,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$amountStr · ${record.paymentMode} · $dateStr',
                style: const TextStyle(fontSize: 12)),
            if (record.status == 'pending')
              const Text(
                '⏳ Pending admin verification (doc 06)',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 0.8),
          ),
          child: Text(
            record.status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

// ── Log cash payment dialog ───────────────────────────────────────────────────
class _LogCashDialog extends StatefulWidget {
  final String employeeId;
  final List<BusinessModel> businesses;
  final CommissionProvider provider;

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
  final _amountCtrl = TextEditingController();
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
          content: Text('✅ Cash payment logged (pending verification)'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = widget.provider.submitting;

    return AlertDialog(
      title: const Text('Log Cash Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount collected (₹)',
                  prefixText: '₹ ',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 8),
              const Text(
                // [NOTE] Two-step verification (doc 06) is not yet built.
                // This record stays "pending" until admin verifies.
                '⚠️ This creates a pending record. '
                'Admin will verify the payment before it counts as commission.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
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
  final String label, value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
            ],
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text('No commission records yet.',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
}
