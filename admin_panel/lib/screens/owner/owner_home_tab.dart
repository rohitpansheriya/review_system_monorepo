// lib/screens/owner/owner_home_tab.dart
//
// Dashboard Home Tab for Business Owner.
// Displays pre-aggregated stats (total scans, star distribution, conversion rate)
// with single-branch stats vs multi-branch aggregated view.
//
// SCALABILITY RULE #1/#2:
// Reads PRE-AGGREGATED stats_summary fields ONLY.
// DOES NOT QUERY RAW scan_logs COLLECTION.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/owner_dashboard_provider.dart';
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

            // ── 3. Summary Stat Cards (Pre-aggregated) ──────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                return GridView.count(
                  crossAxisCount: isWide ? 3 : 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: isWide ? 2.2 : 2.8,
                  children: [
                    _buildStatCard(
                      context,
                      title: 'Total QR Scans',
                      value: '$totalScans',
                      subtitle: 'Pre-aggregated scan count',
                      icon: Icons.qr_code_scanner,
                      color: colorScheme.primary,
                    ),
                    _buildStatCard(
                      context,
                      title: 'Google Reviews Opened',
                      value: '$googleOpened',
                      subtitle: '$conversionRate% conversion rate',
                      icon: Icons.star_rate_rounded,
                      color: AppColors.star,
                    ),
                    _buildStatCard(
                      context,
                      title: 'Active Branches',
                      value: '${provider.branches.length}',
                      subtitle: provider.isSingleBranch ? 'Single location' : 'Multi-branch setup',
                      icon: Icons.location_city,
                      color: colorScheme.tertiary,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // ── 4. Star Rating Breakdown Card ────────────────────────────────
            Card(
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
                color: color.withOpacity(0.12),
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
