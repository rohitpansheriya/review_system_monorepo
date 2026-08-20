// lib/screens/admin/admin_platform_stats_tab.dart
//
// Platform-Wide Stats Tab (Doc 04 Admin Panel).
// Renders total businesses, scans, renewals due (grouped 30/15/7/1 days),
// revenue snapshot using Firestore count() aggregation queries (Scalability Rule #3).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminPlatformStatsTab extends StatelessWidget {
  const AdminPlatformStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform-Wide Analytics',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aggregated via Firestore count() queries (Scalability Rule #3). Excludes pending_payment drafts.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => provider.refreshPlatformStats(),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Stats',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Stat KPI Cards Grid ───────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: 1.5,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildKpiCard(
                    context,
                    title: 'Total Paying Businesses',
                    value: '${provider.totalBusinessesCount}',
                    subtitle: 'Active + Grace Period',
                    icon: Icons.store,
                    color: colorScheme.primary,
                  ),
                  _buildKpiCard(
                    context,
                    title: 'Active Subscriptions',
                    value: '${provider.activeBusinessesCount}',
                    subtitle: 'Full access active',
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                  _buildKpiCard(
                    context,
                    title: 'Grace Period',
                    value: '${provider.graceBusinessesCount}',
                    subtitle: 'Requires renewal',
                    icon: Icons.warning_amber,
                    color: Colors.orange,
                  ),
                  _buildKpiCard(
                    context,
                    title: 'Pending Payment Drafts',
                    value: '${provider.pendingDraftsCount}',
                    subtitle: 'Excluded from count',
                    icon: Icons.pending_actions,
                    color: colorScheme.secondary,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Revenue Snapshot & Renewals Due Breakdown ─────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.monetization_on_outlined, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Revenue Snapshot',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Text(
                          '₹${provider.revenueSnapshot.toStringAsFixed(0)}',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Calculated from setup fees (₹1999) + renewals (₹999).',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_month, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Upcoming Renewals Breakdown',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildRenewalRow(context, 'Due in 30 Days', provider.renewalsDue30, Colors.blue),
                        const SizedBox(height: 8),
                        _buildRenewalRow(context, 'Due in 15 Days', provider.renewalsDue15, Colors.amber),
                        const SizedBox(height: 8),
                        _buildRenewalRow(context, 'Due in 7 Days', provider.renewalsDue7, Colors.deepOrange),
                        const SizedBox(height: 8),
                        _buildRenewalRow(context, 'Due Tomorrow / Today', provider.renewalsDue1, Colors.red),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── All Enrolled Businesses Table & Admin Editing ─────────────────
          _AllBusinessesTableSection(),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 22),
              ],
            ),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildRenewalRow(BuildContext context, String label, int count, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _AllBusinessesTableSection extends StatefulWidget {
  @override
  State<_AllBusinessesTableSection> createState() => _AllBusinessesTableSectionState();
}

class _AllBusinessesTableSectionState extends State<_AllBusinessesTableSection> {
  String _filterStatus = 'all';
  String _searchQuery = '';

  void _showEditBusinessDialog(BuildContext context, BusinessModel biz) {
    final brandCtrl = TextEditingController(text: biz.brandName);
    final catCtrl = TextEditingController(text: biz.categoryType);
    final ownerNameCtrl = TextEditingController(text: biz.ownerName ?? '');
    final ownerEmailCtrl = TextEditingController(text: biz.ownerEmail ?? '');
    final ownerPhoneCtrl = TextEditingController(text: biz.ownerPhone ?? '');
    String status = biz.subscriptionStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Business — ${biz.brandName.isNotEmpty ? biz.brandName : biz.id}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: brandCtrl,
                    decoration: const InputDecoration(labelText: 'Brand Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: catCtrl,
                    decoration: const InputDecoration(labelText: 'Category Type'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ownerNameCtrl,
                    decoration: const InputDecoration(labelText: 'Owner Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ownerEmailCtrl,
                    decoration: const InputDecoration(labelText: 'Owner Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ownerPhoneCtrl,
                    decoration: const InputDecoration(labelText: 'Owner Phone'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Subscription Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'pending_payment', child: Text('Pending Payment')),
                      DropdownMenuItem(value: 'grace_period', child: Text('Grace Period')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => status = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final provider = context.read<AdminDashboardProvider>();
                await provider.updateBusinessDetailsAdmin(
                  businessId: biz.id,
                  brandName: brandCtrl.text.trim(),
                  categoryType: catCtrl.text.trim(),
                  ownerName: ownerNameCtrl.text.trim(),
                  ownerEmail: ownerEmailCtrl.text.trim(),
                  ownerPhone: ownerPhoneCtrl.text.trim(),
                  subscriptionStatus: status,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Business details updated.')),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allBiz = provider.allBusinesses;

    final filtered = allBiz.where((b) {
      final statusMatch = _filterStatus == 'all' || b.subscriptionStatus == _filterStatus;
      final brandName = b.brandName.toLowerCase();
      final ownerEmail = (b.ownerEmail ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase().trim();
      final queryMatch = q.isEmpty || brandName.contains(q) || ownerEmail.contains(q);
      return statusMatch && queryMatch;
    }).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'All Enrolled Businesses (${filtered.length})',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search brand / email…',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _filterStatus,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(value: 'pending_payment', child: Text('Pending Payment')),
                        DropdownMenuItem(value: 'grace_period', child: Text('Grace Period')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _filterStatus = v);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),

            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: Text('No enrolled businesses match the criteria.')),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Brand Name')),
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Owner Name / Email')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Managed By')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: filtered.map((b) {
                    final status = b.subscriptionStatus;
                    return DataRow(
                      cells: [
                        DataCell(
                          InkWell(
                            onTap: () => context.push('/business/${b.id}', extra: b),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  b.brandName.isNotEmpty ? b.brandName : '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text(b.categoryType.isNotEmpty ? b.categoryType : '—')),
                        DataCell(Text('${b.ownerName ?? '—'}\n${b.ownerEmail ?? ''}')),
                        DataCell(
                          Chip(
                            label: Text(status),
                            backgroundColor: status == 'active'
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                          ),
                        ),
                        DataCell(Text(provider.resolveEmployeeName(b.currentlyManagedBy))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_forward, color: Colors.blue),
                                tooltip: 'View Business Details',
                                onPressed: () => context.push('/business/${b.id}', extra: b),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_note, color: Colors.blue),
                                tooltip: 'Edit Business Details',
                                onPressed: () => _showEditBusinessDialog(context, b),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
