// lib/screens/owner/owner_home_tab.dart
//
// Dashboard Home Tab for Business Owner.
// Displays pre-aggregated stats (total scans, star distribution, conversion rate)
// with single-branch stats vs multi-branch aggregated view.
// Also displays Cash Payment Confirmation requests (Doc 06 fraud gate).
//
// SCALABILITY RULE #1/#2:
// Reads PRE-AGGREGATED stats_summary fields ONLY.
// DOES NOT QUERY RAW scan_logs COLLECTION.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/owner_dashboard_provider.dart';
import '../../models/commission_record_model.dart';
import '../../core/theme.dart';

class OwnerHomeTab extends StatelessWidget {
  const OwnerHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final biz = provider.business;

    if (biz == null) {
      return const Center(child: Text('No business details found.'));
    }

    final stats = provider.getAggregatedStats();
    final totalScans = (stats['total_scans'] as num? ?? 0).toInt();
    final googleOpened = (stats['google_reviews_opened'] as num? ?? 0).toInt();
    final starMap = stats['star_distribution'] as Map<String, dynamic>? ?? {};

    final conversionRate = totalScans > 0
        ? ((googleOpened / totalScans) * 100).toStringAsFixed(1)
        : '0.0';

    return RefreshIndicator(
      onRefresh: () async {
        if (biz.ownerAuthUid != null) {
          await provider.loadOwnerData(biz.ownerAuthUid!);
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 0. Cash Payment Confirmation Requests (Doc 06 fraud gate) ───
            if (provider.pendingCashConfirmations.isNotEmpty) ...[
              for (final record in provider.pendingCashConfirmations)
                _buildCashConfirmationCard(context, provider, record),
              const SizedBox(height: 12),
            ],

            // ── 1. Renewal Reminder Banner (Doc 08) ─────────────────────────
            if (provider.isGracePeriod)
              _buildGraceBanner(context, provider, biz.gracePeriodEnds)
            else if (biz.renewalDate != null &&
                biz.renewalDate!.difference(DateTime.now()).inDays <= 30)
              _buildUpcomingRenewalBanner(context, provider, biz.renewalDate!),

            const SizedBox(height: 16),

            // ── 2. Header & Branch Switcher (Multi-branch support) ───────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biz.brandName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Overview & Customer Review Analytics',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (!provider.isSingleBranch)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: provider.selectedBranchId,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(Icons.storefront, size: 18),
                                SizedBox(width: 8),
                                Text('All Branches (Aggregated)',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          ...provider.branches.map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text(b.branchName),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            provider.setSelectedBranch(val);
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 3. High-Level Metrics (Total Scans, Google Reviews, Conversion Rate)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final cards = [
                  _buildStatCard(
                    context,
                    title: 'Total QR Scans',
                    value: '$totalScans',
                    subtitle: 'Customer interactions',
                    icon: Icons.qr_code_scanner,
                    color: colorScheme.primary,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Google Reviews Prompted',
                    value: '$googleOpened',
                    subtitle: '4★ and 5★ review redirects',
                    icon: Icons.rate_review,
                    color: AppColors.activeFg,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Conversion Rate',
                    value: '$conversionRate%',
                    subtitle: 'Scans converted to reviews',
                    icon: Icons.trending_up,
                    color: AppColors.star,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: cards.map((c) => Expanded(child: c)).toList(),
                  );
                }
                return Column(
                  children: cards
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: c,
                          ))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── 4. Star-Rating Distribution ──────────────────────────────────
            Card(
              elevation: 0,
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
                      children: [
                        const Icon(Icons.bar_chart, color: AppColors.star),
                        const SizedBox(width: 8),
                        Text(
                          'Star Rating Distribution',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pre-aggregated rating breakdown across selected view',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),

                    ...List.generate(5, (idx) {
                      final starNum = 5 - idx;
                      final count = (starMap['$starNum'] as num? ?? 0).toInt();
                      final pct = totalScans > 0 ? (count / totalScans) : 0.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Text(
                                '$starNum ★',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.star,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 12,
                                  backgroundColor: colorScheme.surfaceContainerHighest,
                                  color: starNum >= 4
                                      ? colorScheme.primary
                                      : starNum == 3
                                          ? AppColors.star
                                          : colorScheme.error,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '$count',
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cash Confirmation Card (Doc 06) ─────────────────────────────────────────
  Widget _buildCashConfirmationCard(
    BuildContext context,
    OwnerDashboardProvider provider,
    CommissionRecordModel record,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateStr = record.dateClaimed != null
        ? record.dateClaimed!.toLocal().toString().split(' ')[0]
        : 'recently';

    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.35),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cash Payment Verification Required',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.star.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pending Confirmation',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Our records show a cash payment of ₹${record.amount.toStringAsFixed(0)} was collected for your enrollment/renewal on $dateStr.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Did you pay ₹${record.amount.toStringAsFixed(0)} in cash?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await provider.confirmCashPayment(
                      recordId: record.id,
                      confirmed: false,
                      disputeReason: 'Owner responded NO to payment confirmation.',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment disputed. Admin has been notified for investigation.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('No, I Did Not Pay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await provider.confirmCashPayment(
                      recordId: record.id,
                      confirmed: true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Cash payment confirmed successfully!'),
                          backgroundColor: AppColors.activeFg,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Yes, I Paid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.activeFg,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraceBanner(
      BuildContext context, OwnerDashboardProvider provider, DateTime? graceEnds) {
    final scheme = Theme.of(context).colorScheme;
    final daysLeft = graceEnds != null ? graceEnds.difference(DateTime.now()).inDays : 0;

    return Card(
      color: scheme.errorContainer,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subscription Expired (Grace Period Active)',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your QR customer review links are temporarily paused. You have $daysLeft days remaining to renew before data deletion.',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingRenewalBanner(
      BuildContext context, OwnerDashboardProvider provider, DateTime renewalDate) {
    final scheme = Theme.of(context).colorScheme;
    final daysLeft = renewalDate.difference(DateTime.now()).inDays;

    return Card(
      color: scheme.tertiaryContainer,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: scheme.onTertiaryContainer, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Renewal Notice: Your annual subscription renews in $daysLeft days. Keep your review collection active!',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
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
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
