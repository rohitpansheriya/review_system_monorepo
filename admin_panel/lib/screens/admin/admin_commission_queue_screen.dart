// lib/screens/admin/admin_commission_queue_screen.dart
//
// Employee Commission Ledger:
//   • Commission payout tracking (pending vs paid)
//   • Filter by employee, payment status, and month
//   • Bulk monthly payouts & individual payout UTR entry

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/employee_commission_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';

class AdminCommissionQueueScreen extends StatefulWidget {
  const AdminCommissionQueueScreen({super.key});

  @override
  State<AdminCommissionQueueScreen> createState() =>
      _AdminCommissionQueueScreenState();
}

class _AdminCommissionQueueScreenState
    extends State<AdminCommissionQueueScreen> {
  String? _selectedEmployeeId;
  String _statusFilter = 'all'; // 'all', 'pending', 'paid'
  String? _monthFilter;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final adminUid = context.read<AppAuthProvider>().uid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final employees = provider.employees;

    // Generate month options (last 12 months)
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    return Column(
      children: [
        // ── Filters ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              // Employee filter
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: _selectedEmployeeId,
                  decoration: const InputDecoration(
                    labelText: 'Employee',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Employees'),
                    ),
                    ...employees.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.uid,
                        child: Text(e.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedEmployeeId = v),
                ),
              ),
              // Status filter
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                ),
              ),
              // Month filter
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  value: _monthFilter,
                  decoration: const InputDecoration(
                    labelText: 'Month',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Months'),
                    ),
                    ...months.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m,
                        child: Text(
                          DateFormat.yMMM().format(DateTime.parse('$m-01')),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _monthFilter = v),
                ),
              ),
            ],
          ),
        ),

        // ── One-Click Payout Button ─────────────────────────────────
        if (_selectedEmployeeId != null && _monthFilter != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    () => _showBulkPayoutDialog(
                      context,
                      provider,
                      adminUid,
                      _selectedEmployeeId!,
                      _monthFilter!,
                    ),
                icon: const Icon(Icons.payments),
                label: Text(
                  'Pay All Pending for ${_getEmployeeName(employees, _selectedEmployeeId!)} — '
                  '${DateFormat.yMMM().format(DateTime.parse('$_monthFilter-01'))}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // ── Commission List ───────────────────────────────────────
        Expanded(child: _buildCommissionStream(context, provider, scheme)),
      ],
    );
  }

  Widget _buildCommissionStream(
    BuildContext context,
    AdminDashboardProvider provider,
    ColorScheme scheme,
  ) {
    // Choose the right stream based on filters
    final Stream<List<EmployeeCommissionModel>> stream;
    if (_selectedEmployeeId != null) {
      stream = provider.watchEmployeeCommissions(
        _selectedEmployeeId!,
        statusFilter: _statusFilter == 'all' ? null : _statusFilter,
        monthFilter: _monthFilter,
      );
    } else {
      if (_statusFilter == 'pending') {
        stream = provider.watchAllPendingCommissions(monthFilter: _monthFilter);
      } else {
        // For 'all' or 'paid' without employee selection, we need to
        // use a broader query. Use pending stream for now and filter client-side.
        stream = provider.watchAllPendingCommissions(monthFilter: _monthFilter);
      }
    }

    return StreamBuilder<List<EmployeeCommissionModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final commissions = snapshot.data ?? [];

        // Calculate summary
        final totalPending = commissions
            .where((c) => c.isPending)
            .fold<double>(0, (sum, c) => sum + c.amount);
        final totalPaid = commissions
            .where((c) => c.isPaid)
            .fold<double>(0, (sum, c) => sum + c.amount);

        if (commissions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 64,
                  color: scheme.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No commission records found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Commissions are created when employee-enrolled businesses activate.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Summary badges
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 16,
                children: [
                  _SummaryBadge(
                    label: 'Total Records',
                    value: '${commissions.length}',
                    color: scheme.primary,
                  ),
                  _SummaryBadge(
                    label: 'Pending Payout',
                    value: '₹${totalPending.toStringAsFixed(0)}',
                    color: Colors.orange,
                  ),
                  _SummaryBadge(
                    label: 'Paid Out',
                    value: '₹${totalPaid.toStringAsFixed(0)}',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: commissions.length,
                itemBuilder: (context, index) {
                  final c = commissions[index];
                  return _CommissionCard(commission: c);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _getEmployeeName(List employees, String uid) {
    final emp = employees.where((e) => e.uid == uid);
    return emp.isNotEmpty ? emp.first.name : uid;
  }

  void _showBulkPayoutDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String adminUid,
    String employeeId,
    String month,
  ) {
    final payoutCtrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Bulk Payout — Mark All Pending as Paid'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Employee: ${_getEmployeeName(provider.employees, employeeId)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Month: ${DateFormat.yMMM().format(DateTime.parse('$month-01'))}',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: payoutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payout Reference (UTR / Transaction ID)',
                      hintText: 'e.g., UTIB1234567890',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final ref = payoutCtrl.text.trim();
                  if (ref.isEmpty) return;
                  Navigator.of(ctx).pop();
                  try {
                    final result = await provider.markCommissionsPaidBulk(
                      employeeId: employeeId,
                      month: month,
                      payoutReference: ref,
                      adminUid: adminUid,
                    );
                    final count = result['count'] ?? 0;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$count commissions marked as paid.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Mark All as Paid'),
              ),
            ],
          ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _CommissionCard extends StatelessWidget {
  final EmployeeCommissionModel commission;
  const _CommissionCard({required this.commission});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPaid = commission.isPaid;
    final dateFormat = DateFormat.yMMMd();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color:
              isPaid
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isPaid
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
            isPaid ? Icons.check_circle : Icons.schedule,
            color: isPaid ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(
          commission.businessName.isNotEmpty
              ? commission.businessName
              : commission.businessId,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee: ${context.watch<AdminDashboardProvider>().resolveEmployeeName(commission.employeeId)}',
            ),
            if (commission.createdAt != null)
              Text('Activated: ${dateFormat.format(commission.createdAt!)}'),
            if (isPaid && commission.payoutReference != null)
              Text(
                'UTR: ${commission.payoutReference}',
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${commission.amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isPaid ? Colors.green : scheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isPaid
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isPaid ? 'PAID' : 'PENDING',
                style: TextStyle(
                  color: isPaid ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
