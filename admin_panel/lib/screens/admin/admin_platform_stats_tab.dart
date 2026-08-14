// lib/screens/admin/admin_platform_stats_tab.dart
//
// Platform-Wide Stats Tab (Doc 04 Admin Panel).
// Renders total businesses, scans, renewals due (grouped 30/15/7/1 days),
// revenue snapshot using Firestore count() aggregation queries (Scalability Rule #3).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
              Column(
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
