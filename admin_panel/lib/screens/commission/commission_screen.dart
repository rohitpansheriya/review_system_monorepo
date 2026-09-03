// lib/screens/commission/commission_screen.dart
// Employee commission tracker — read-only view from employee_commissions collection.
// No "Log Cash Payment" action — employees don't handle cash.
// Styling: all Colors.* replaced with AppTheme semantic tokens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/employee_commission_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/commission_provider.dart';
import '../../widgets/app_animated_loader.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommissionProvider>();
    final scheme   = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title:   const Text('My Commissions'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
      ),

      body: provider.loading
          ? const Center(
              child: AppAnimatedLoader.card(
                message: 'Loading commissions…',
              ),
            )
          : Column(
              children: [
                // ── Summary Cards ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _StatCard(
                        title: 'Total Earned',
                        value: '₹${provider.totalAll.toStringAsFixed(0)}',
                        icon: Icons.account_balance_wallet,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: 'Pending',
                        value: '₹${provider.totalPending.toStringAsFixed(0)}',
                        icon: Icons.schedule,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: 'Paid',
                        value: '₹${provider.totalPaid.toStringAsFixed(0)}',
                        icon: Icons.check_circle,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),

                // ── Filter Chips ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: provider.statusFilter == null,
                        onTap: () => provider.setStatusFilter(null),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Pending',
                        selected: provider.statusFilter == 'pending',
                        onTap: () => provider.setStatusFilter('pending'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Paid',
                        selected: provider.statusFilter == 'paid',
                        onTap: () => provider.setStatusFilter('paid'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── Commission List ─────────────────────────────────────
                Expanded(
                  child: provider.records.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long, size: 64,
                                  color: scheme.primary.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Text(
                                'No commissions yet',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Commissions are created when your enrolled businesses activate.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: provider.records.length,
                          itemBuilder: (context, index) {
                            final rec = provider.records[index];
                            return _CommissionRow(record: rec);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  final EmployeeCommissionModel record;
  const _CommissionRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPaid = record.isPaid;
    final dateFormat = DateFormat.yMMMd();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isPaid
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPaid
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
            isPaid ? Icons.check_circle : Icons.schedule,
            color: isPaid ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(
          record.businessName.isNotEmpty ? record.businessName : record.businessId,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.createdAt != null)
              Text('Activated: ${dateFormat.format(record.createdAt!)}'),
            Text('Month: ${record.activationMonth}'),
            if (isPaid && record.payoutReference != null)
              Text(
                'UTR: ${record.payoutReference}',
                style: const TextStyle(fontSize: 11),
              ),
            if (isPaid && record.paidAt != null)
              Text(
                'Paid on: ${dateFormat.format(record.paidAt!)}',
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${record.amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isPaid ? Colors.green : scheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isPaid
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
