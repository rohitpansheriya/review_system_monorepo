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
    final starMap = stats['star_distribution'] as Map<String, dynamic>? ?? {};

    final s5 = (starMap['5'] as num? ?? 0).toInt();
    final s4 = (starMap['4'] as num? ?? 0).toInt();
    final s3 = (starMap['3'] as num? ?? 0).toInt();
    final s2 = (starMap['2'] as num? ?? 0).toInt();
    final s1 = (starMap['1'] as num? ?? 0).toInt();

    final totalRated = s5 + s4 + s3 + s2 + s1;
    final avgRating = totalRated > 0
        ? ((5 * s5 + 4 * s4 + 3 * s3 + 2 * s2 + 1 * s1) / totalRated).toStringAsFixed(1)
        : (totalScans > 0 ? '5.0' : '0.0');

    // Dynamically compute Google vs Private based on actual star_routing_config
    int googleReviews = 0;
    int privateIssues = 0;
    final googleStars = <String>[];
    final privateStars = <String>[];
    final bool isAllBranches = provider.selectedBranchId == 'all' && provider.branches.length > 1;
    final bool isUniform = provider.areBranchRoutingsUniform;

    if (isAllBranches) {
      // Aggregate true counts across each individual branch according to that branch's own routing config
      for (final branch in provider.branches) {
        final bRouting = branch.starRoutingConfig;
        final bStats = provider.selectedMonth == 'all'
            ? branch.starDistribution
            : (branch.monthlyStats[provider.selectedMonth]?['star_distribution'] as Map<String, dynamic>?) ?? {};
        for (final star in ['1', '2', '3', '4', '5']) {
          final count = (bStats[star] as num? ?? 0).toInt();
          final action = bRouting[star] ?? (int.parse(star) >= 4 ? 'google' : 'whatsapp');
          if (action == 'google') {
            googleReviews += count;
          } else {
            privateIssues += count;
          }
        }
      }

      if (isUniform) {
        final routing = provider.getEffectiveStarRouting();
        for (final star in ['1', '2', '3', '4', '5']) {
          final action = routing[star] ?? (int.parse(star) >= 4 ? 'google' : 'whatsapp');
          if (action == 'google') {
            googleStars.add('$star★');
          } else {
            privateStars.add('$star★');
          }
        }
      }
    } else {
      final routing = provider.getEffectiveStarRouting();
      final starValues = {'1': s1, '2': s2, '3': s3, '4': s4, '5': s5};
      for (final star in ['1', '2', '3', '4', '5']) {
        final action = routing[star] ?? (int.parse(star) >= 4 ? 'google' : 'whatsapp');
        if (action == 'google') {
          googleReviews += starValues[star]!;
          googleStars.add('$star★');
        } else {
          privateIssues += starValues[star]!;
          privateStars.add('$star★');
        }
      }
    }

    final String googleSubtitle;
    final String privateSubtitle;
    final String routingImpactNote;

    if (isAllBranches && !isUniform) {
      googleSubtitle = 'Directed to Maps (varies by branch)';
      privateSubtitle = 'Kept off Maps (varies by branch)';
      routingImpactNote = 'AppNexa Smart Routing protects your Google rating according to each branch\'s custom star-routing configuration.';
    } else {
      googleSubtitle = googleStars.isNotEmpty
          ? '${googleStars.join(' & ')} directed to Maps'
          : 'No stars routed to Google';
      privateSubtitle = privateStars.isNotEmpty
          ? '${privateStars.join(' & ')} kept off Google Maps'
          : 'No stars routed to WhatsApp';

      if (googleStars.isNotEmpty && privateStars.isNotEmpty) {
        routingImpactNote = 'AppNexa Smart Routing protects your Google rating: ${googleStars.join(' & ')} reviewers are routed to Google Maps, while ${privateStars.join(' & ')} concerns are routed directly to your private WhatsApp.';
      } else if (googleStars.isNotEmpty) {
        routingImpactNote = 'AppNexa Smart Routing active: All ratings (${googleStars.join(' & ')}) are directed to Google Maps.';
      } else {
        routingImpactNote = 'AppNexa Smart Routing active: All ratings (${privateStars.join(' & ')}) are directed to your private WhatsApp.';
      }
    }

    // Customer sentiment is strictly based on ratings (4★ & 5★), independent of routing destination
    final positiveRatings = s5 + s4;
    final positivePercent = totalRated > 0
        ? ((positiveRatings / totalRated) * 100).toStringAsFixed(1)
        : (totalScans > 0 ? '100.0' : '0.0');

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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          biz.brandName,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (biz.businessCode != null || biz.isTestAccount) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: biz.isTestAccount ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: biz.isTestAccount ? AppColors.warning : AppColors.primary.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              biz.displayCode,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: biz.isTestAccount ? AppColors.warning : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Overview & Customer Review Analytics',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Timeframe / Month Filter
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: provider.selectedMonth,
                              items: provider.availableMonths
                                  .map((m) => DropdownMenuItem(
                                        value: m.key,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calendar_month_outlined, size: 16),
                                            const SizedBox(width: 8),
                                            Text(m.label),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  provider.setSelectedMonth(val);
                                }
                              },
                            ),
                          ),
                        ),

                        // Branch Switcher (Multi-branch)
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
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 3. High-Level ROI Metrics Grid (Responsive GridView) ──────────
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 950
                    ? 4
                    : (constraints.maxWidth > 540 ? 2 : 1);
                final ratio = constraints.maxWidth > 950
                    ? 2.2
                    : (constraints.maxWidth > 540 ? 2.5 : 3.0);

                return GridView.count(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  shrinkWrap: true,
                  childAspectRatio: ratio,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStatCard(
                      context,
                      title: 'Total QR Scans',
                      value: '$totalScans',
                      subtitle: provider.selectedMonth == 'all'
                          ? 'Customer interactions'
                          : 'Scans in selected period',
                      icon: Icons.qr_code_scanner,
                      color: colorScheme.primary,
                    ),
                    _buildStatCard(
                      context,
                      title: 'Google Reviews Boosted',
                      value: '+$googleReviews',
                      subtitle: googleSubtitle,
                      icon: Icons.rate_review,
                      color: AppColors.activeFg,
                    ),
                    _buildStatCard(
                      context,
                      title: 'Private Issues Intercepted',
                      value: '$privateIssues',
                      subtitle: privateSubtitle,
                      icon: Icons.shield_outlined,
                      color: const Color(0xFFE11D48),
                    ),
                    _buildStatCard(
                      context,
                      title: 'Positive Sentiment Rate',
                      value: '$positivePercent%',
                      subtitle: totalRated > 0
                          ? '$positiveRatings of $totalRated ratings (4–5★)'
                          : 'No ratings submitted yet',
                      icon: Icons.auto_graph,
                      color: AppColors.star,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // ── 4. Month-over-Month Performance & Review Growth Trends ────────
            _buildMonthlyTrendsCard(context, provider),

            const SizedBox(height: 24),

            // ── 5. Visual Star-Rating Breakdown ──────────────────────────────
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bar_chart_rounded, color: AppColors.star, size: 26),
                            const SizedBox(width: 8),
                            Text(
                              'Customer Rating Breakdown',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 18),
                              const SizedBox(width: 4),
                              Text(
                                '$avgRating / 5.0 ($totalRated ratings)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aggregated star distribution from live QR interactions across your business',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    ...List.generate(5, (idx) {
                      final starNum = 5 - idx;
                      final count = (starMap['$starNum'] as num? ?? 0).toInt();
                      final pct = totalRated > 0 ? (count / totalRated) : 0.0;
                      final pctText = (pct * 100).toStringAsFixed(0);

                      final barColor = starNum >= 4
                          ? const Color(0xFF10B981)
                          : starNum == 3
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFEF4444);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 50,
                              child: Row(
                                children: [
                                  Text(
                                    '$starNum',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.star_rounded, size: 16, color: AppColors.star),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 14,
                                  backgroundColor: colorScheme.surfaceContainerHighest,
                                  color: barColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 90,
                              child: Text(
                                '$pctText% ($count)',
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // ROI Impact Note
                    Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            routingImpactNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Cash Confirmation Card REMOVED — cash is admin-only now.
  // Owner is not part of the confirmation gate.

  Widget _buildGraceBanner(
      BuildContext context, OwnerDashboardProvider provider, DateTime? graceEnds) {
    final daysLeft = graceEnds != null ? graceEnds.difference(DateTime.now()).inDays : 0;
    final isDesktop = MediaQuery.of(context).size.width > 700;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '⚠️ Subscription Expired — Physical QR Standees & Review Links Inactive',
          style: TextStyle(
            color: Color(0xFF991B1B),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Customer review collection on your physical QR standees is currently unavailable. You have $daysLeft days of grace period remaining before account and data deletion. Renew today to instantly reactivate your standees and protect your review flow.',
          style: const TextStyle(
            color: Color(0xFFB91C1C),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );

    final renewBtn = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => provider.setTabIndex(3),
      icon: const Icon(Icons.payment_rounded, size: 18),
      label: const Text(
        'Renew Now (₹999)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    return Card(
      color: const Color(0xFFFEF2F2),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFDC2626), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  renewBtn,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFDC2626), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '⚠️ Standees & Review Links Inactive',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Customer review collection on your physical QR standees is currently unavailable ($daysLeft days of grace period remaining).',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: renewBtn),
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildMonthlyTrendsCard(BuildContext context, OwnerDashboardProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final trends = provider.getMonthlyTrends();
    final maxScans = trends.map((t) => t.scans).fold<int>(1, (max, v) => v > max ? v : max);

    return Card(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights_rounded, color: AppColors.secondary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Monthly Review Growth & Historical Performance',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Last 6 Months',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Month-over-month customer footfall scans and 5-star Google review redirection trends',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Horizontal / stacked monthly comparison bars
            ...trends.map((t) {
              final scanRatio = maxScans > 0 ? (t.scans / maxScans).clamp(0.0, 1.0) : 0.0;
              final isCurrent = provider.selectedMonth == t.monthKey ||
                  (provider.selectedMonth == 'all' && t.monthKey == trends.last.monthKey);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                        : colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? colorScheme.primary.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: isCurrent ? 1.2 : 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                t.label,
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                  color: isCurrent ? colorScheme.primary : null,
                                ),
                              ),
                              if (isCurrent && provider.selectedMonth != 'all') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Viewing',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                '${t.scans} scans',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.activeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${t.reviews} Google Reviews',
                                  style: const TextStyle(
                                    color: AppColors.activeFg,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: scanRatio > 0.05 ? scanRatio : 0.05,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary,
                                    AppColors.secondary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
