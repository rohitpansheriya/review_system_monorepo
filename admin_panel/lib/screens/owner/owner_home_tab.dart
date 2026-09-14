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
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/owner_dashboard_provider.dart';
import '../../models/branch_model.dart';
import '../../core/theme.dart';
import '../../widgets/app_kpi_card.dart';
import '../../widgets/month_year_picker_dialog.dart';

class OwnerHomeTab extends StatefulWidget {
  const OwnerHomeTab({super.key});

  @override
  State<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

class _OwnerHomeTabState extends State<OwnerHomeTab> {
  bool _syncingRatings = false;

  Future<void> _handleSyncRatings(OwnerDashboardProvider provider) async {
    setState(() => _syncingRatings = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final count = await provider.syncGoogleRatings();
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? '🌟 Successfully synced Google ratings for $count branch location(s)! Your next update will unlock in 7 days.'
                : 'No Google Place IDs configured to sync.',
          ),
          backgroundColor: AppColors.activeFg,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(
          content: Text('Failed to sync Google ratings: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingRatings = false);
      }
    }
  }

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

    final isDesktop = MediaQuery.of(context).size.width > 700;

    return RefreshIndicator(
      onRefresh: () async {
        if (biz.ownerAuthUid != null) {
          await provider.loadOwnerData(biz.ownerAuthUid!);
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
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

            // ── 2. Top Header ───────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      biz.brandName,
                      style: (isDesktop ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (biz.businessCode != null || biz.isTestAccount)
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

            const SizedBox(height: 20),

            // ── 3. Google Reviews & Baseline Reputation Growth Card (ON TOP) ─
            _buildGoogleReputationGrowthCard(context, provider, isDesktop, googleReviews),

            const SizedBox(height: 28),

            // ── 4. Filter & Total Scan Analysis Section Header ───────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Scan Analysis & Interactions',
                        style: (isDesktop ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Filter interactions by timeframe and view live customer engagement',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Interactive Month Navigator with 1-click steppers
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00458B).withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Previous Month Step (‹)
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, size: 18),
                            tooltip: 'Previous Month',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            onPressed: provider.loading || provider.isAllTime
                                ? null
                                : () => provider.previousMonth(),
                          ),

                          // Center Interactive Month & Year Pill
                          InkWell(
                            onTap: () {
                              MonthYearPickerDialog.show(
                                context: context,
                                initialYear: provider.currentYear,
                                initialMonth: provider.currentMonth,
                                isAllTime: provider.isAllTime,
                                onMonthSelected: (year, month) => provider.setMonth(year, month),
                                onAllTimeSelected: () => provider.setAllTime(),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    provider.isAllTime ? Icons.all_inclusive_rounded : Icons.calendar_month_rounded,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    provider.selectedMonthLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.unfold_more_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),

                          // Next Month Step (›)
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, size: 18),
                            tooltip: 'Next Month',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            onPressed: provider.loading || provider.isAllTime
                                ? null
                                : () => provider.nextMonth(),
                          ),
                        ],
                      ),
                    ),

                    // Quick "This Month" reset chip if not on current month or if on All Time
                    if (provider.isAllTime ||
                        provider.currentYear != DateTime.now().year ||
                        provider.currentMonth != DateTime.now().month)
                      ActionChip(
                        avatar: const Icon(Icons.replay_rounded, size: 13, color: AppColors.primary),
                        label: const Text('This Month', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                        onPressed: () => provider.setThisMonth(),
                      ),

                    // Branch Switcher (Multi-branch)
                    if (!provider.isSingleBranch)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00458B).withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: provider.selectedBranchId,
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 8,
                            icon: const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Row(
                                  children: [
                                    Icon(Icons.storefront, size: 18, color: AppColors.primary),
                                    SizedBox(width: 8),
                                    Text('All Branches (Aggregated)',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              ...provider.branches.map((b) => DropdownMenuItem(
                                    value: b.id,
                                    child: Text(b.branchName, style: const TextStyle(fontWeight: FontWeight.w500)),
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

            const SizedBox(height: 16),

            // ── 5. High-Level ROI Metrics Grid (Total Scan Analysis) ──────────
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
                    AppKpiCard(
                      compact: true,
                      label: 'Total QR Scans',
                      value: '$totalScans',
                      subtitle: provider.selectedMonth == 'all'
                          ? 'Customer interactions'
                          : 'Scans in selected period',
                      icon: Icons.qr_code_scanner_rounded,
                      color: colorScheme.primary,
                    ),
                    AppKpiCard(
                      compact: true,
                      label: 'Google Reviews Boosted',
                      value: '+$googleReviews',
                      subtitle: googleSubtitle,
                      icon: Icons.rate_review_rounded,
                      color: AppColors.activeFg,
                    ),
                    AppKpiCard(
                      compact: true,
                      label: 'Private Issues Intercepted',
                      value: '$privateIssues',
                      subtitle: privateSubtitle,
                      icon: Icons.shield_outlined,
                      color: const Color(0xFFE11D48),
                    ),
                    AppKpiCard(
                      compact: true,
                      label: 'Positive Sentiment Rate',
                      value: '$positivePercent%',
                      subtitle: totalRated > 0
                          ? '$positiveRatings of $totalRated ratings (4–5★)'
                          : 'No ratings submitted yet',
                      icon: Icons.auto_graph_rounded,
                      color: AppColors.star,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // ── 5. Month-over-Month Performance & Review Growth Trends ────────
            _buildMonthlyTrendsCard(context, provider),

            const SizedBox(height: 24),

            // ── 6. Visual Star-Rating Breakdown ──────────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bar_chart_rounded, color: AppColors.star, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Customer Rating Breakdown',
                              style: (isDesktop ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 18),
                              const SizedBox(width: 4),
                              Text(
                                '$avgRating / 5.0 ($totalRated ratings)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                  fontSize: 12,
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



  Widget _buildMonthlyTrendsCard(BuildContext context, OwnerDashboardProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 700;
    final trends = provider.getMonthlyTrends();
    final maxScans = trends.map((t) => t.scans).fold<int>(1, (max, v) => v > max ? v : max);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insights_rounded, color: AppColors.secondary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isDesktop ? 'Monthly Review Growth & Historical Performance' : 'Monthly Review Growth',
                      style: (isDesktop ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
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
            const SizedBox(height: 20),

            // Horizontal / stacked monthly comparison bars
            ...trends.map((t) {
              final scanRatio = maxScans > 0 ? (t.scans / maxScans).clamp(0.0, 1.0) : 0.0;
              final isCurrent = provider.selectedMonth == t.monthKey ||
                  (provider.selectedMonth == 'all' && t.monthKey == trends.last.monthKey);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.label,
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                  color: isCurrent ? colorScheme.primary : null,
                                ),
                              ),
                              if (isCurrent && provider.selectedMonth != 'all') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Viewing',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${t.scans} scans',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.activeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '+${t.reviews} Reviews',
                                  style: const TextStyle(
                                    color: AppColors.activeFg,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
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

  // ── Google Reputation Baseline & Growth Card ──────────────────────────────
  Widget _buildGoogleReputationGrowthCard(
    BuildContext context,
    OwnerDashboardProvider provider,
    bool isDesktop,
    int googleReviewsBoosted,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final List<BranchModel> relevantBranches;
    if (provider.selectedBranchId == 'all') {
      relevantBranches = provider.branches.where((b) => (b.placeId ?? '').isNotEmpty).toList();
    } else {
      relevantBranches = provider.branches.where((b) => b.id == provider.selectedBranchId).toList();
    }

    final hasPlaceId = relevantBranches.any((b) => (b.placeId ?? '').isNotEmpty);
    final hasBaseline = relevantBranches.any((b) => b.initialRating != null || b.initialReviewCount != null);

    // Compute baseline averages / sums
    int totalBaselineReviews = 0;
    int baselineCountForAvg = 0;
    double sumBaselineRating = 0;

    int totalCurrentReviews = 0;
    int currentCountForAvg = 0;
    double sumCurrentRating = 0;
    DateTime? earliestCapturedAt;
    DateTime? latestSyncedAt;

    for (final b in relevantBranches) {
      if (b.initialReviewCount != null) totalBaselineReviews += b.initialReviewCount!;
      if (b.initialRating != null) {
        sumBaselineRating += b.initialRating!;
        baselineCountForAvg++;
      }
      if (b.initialRatingCapturedAt != null) {
        if (earliestCapturedAt == null || b.initialRatingCapturedAt!.isBefore(earliestCapturedAt)) {
          earliestCapturedAt = b.initialRatingCapturedAt;
        }
      }

      final cCount = b.currentReviewCount ?? b.initialReviewCount;
      if (cCount != null) totalCurrentReviews += cCount;

      final cRating = b.currentRating ?? b.initialRating;
      if (cRating != null) {
        sumCurrentRating += cRating;
        currentCountForAvg++;
      }

      if (b.lastRatingSyncAt != null) {
        if (latestSyncedAt == null || b.lastRatingSyncAt!.isAfter(latestSyncedAt)) {
          latestSyncedAt = b.lastRatingSyncAt;
        }
      }
    }

    final avgBaselineRating = baselineCountForAvg > 0 ? (sumBaselineRating / baselineCountForAvg) : 0.0;
    final avgCurrentRating = currentCountForAvg > 0 ? (sumCurrentRating / currentCountForAvg) : avgBaselineRating;

    final int reviewsGain = (totalCurrentReviews >= totalBaselineReviews)
        ? (totalCurrentReviews - totalBaselineReviews)
        : 0;
    final double ratingDelta = avgCurrentRating - avgBaselineRating;

    final dateFormat = DateFormat('dd MMM yyyy');

    // ── 7-Day Sync Cooldown Calculation ──────────────────────────────────────
    final lastSyncDate = latestSyncedAt ?? earliestCapturedAt;
    final now = DateTime.now();
    DateTime? nextEligibleSyncDate;
    bool isSyncCooldownActive = false;
    int daysUntilNextSync = 0;

    if (hasBaseline && lastSyncDate != null) {
      nextEligibleSyncDate = lastSyncDate.add(const Duration(days: 7));
      if (now.isBefore(nextEligibleSyncDate)) {
        isSyncCooldownActive = true;
        daysUntilNextSync = nextEligibleSyncDate.difference(now).inDays + 1;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasBaseline ? const Color(0xFF38BDF8).withValues(alpha: 0.4) : colorScheme.outlineVariant,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              const Color(0xFF0284C7).withValues(alpha: 0.04),
            ],
          ),
        ),
        padding: EdgeInsets.all(isDesktop ? 22.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.maps_home_work_rounded, color: Color(0xFF0284C7), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Google Reputation & Baseline Growth',
                            style: (isDesktop ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Google Places Sync',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Track your verified Google rating and review expansion since joining AppNexa',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasPlaceId)
                  Tooltip(
                    message: isSyncCooldownActive && nextEligibleSyncDate != null
                        ? 'Google updates are available once every 7 days. Next sync unlocks on ${dateFormat.format(nextEligibleSyncDate)} (${daysUntilNextSync == 1 ? "tomorrow" : "in $daysUntilNextSync days"}).'
                        : 'Click to fetch fresh rating and reviews from Google Places.',
                    child: ElevatedButton.icon(
                      onPressed: (_syncingRatings || isSyncCooldownActive) ? null : () => _handleSyncRatings(provider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFF1F5F9),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 16 : 10,
                          vertical: isDesktop ? 12 : 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: isSyncCooldownActive
                              ? const BorderSide(color: Color(0xFFE2E8F0))
                              : BorderSide.none,
                        ),
                      ),
                      icon: _syncingRatings
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              isSyncCooldownActive ? Icons.schedule_rounded : Icons.sync_rounded,
                              size: 16,
                            ),
                      label: Text(
                        _syncingRatings
                            ? 'Syncing…'
                            : (isSyncCooldownActive
                                ? 'Sync in ${daysUntilNextSync}d'
                                : (hasBaseline ? 'Sync Latest' : 'Fetch Google Rating')),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),

            // ── Sweet 7-Day Cooldown Notice Banner ────────────────────────────
            if (isSyncCooldownActive && nextEligibleSyncDate != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: Color(0xFF16A34A), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '🌟 Google reputation sync is available once every 7 days to give your business time to accumulate authentic new reviews. Next update unlocks on ${dateFormat.format(nextEligibleSyncDate)} (${daysUntilNextSync == 1 ? "tomorrow" : "in $daysUntilNextSync days"}). Keep collecting wonderful customer reviews!',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Missing Place ID or Missing Baseline Warning ──────────────────
            if (!hasPlaceId)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Google Place ID is not configured for this branch. Add a Google Place ID in Branch settings to enable automatic reputation tracking.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else if (!hasBaseline)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF0284C7), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Initial Google baseline has not been captured yet. Click "Fetch Google Rating" above to record your starting baseline and track growth.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF0369A1)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _syncingRatings ? null : () => _handleSyncRatings(provider),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                      child: const Text('Fetch Now', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              )
            else
              // ── 3-Column Metrics Comparison Grid ────────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 680;
                  final children = [
                    // Box 1: Starting Baseline
                    _buildReputationMetricBox(
                      context,
                      label: 'Starting Baseline',
                      tag: earliestCapturedAt != null ? dateFormat.format(earliestCapturedAt) : 'At Enrollment',
                      rating: avgBaselineRating > 0 ? avgBaselineRating.toStringAsFixed(1) : '—',
                      reviewCount: totalBaselineReviews,
                      icon: Icons.flag_outlined,
                      accentColor: const Color(0xFF64748B),
                    ),
                    // Box 2: Current Google Profile
                    _buildReputationMetricBox(
                      context,
                      label: 'Current Google Profile',
                      tag: latestSyncedAt != null ? 'Synced ${dateFormat.format(latestSyncedAt)}' : 'Live Sync',
                      rating: avgCurrentRating > 0 ? avgCurrentRating.toStringAsFixed(1) : '—',
                      reviewCount: totalCurrentReviews,
                      icon: Icons.check_circle_outline_rounded,
                      accentColor: const Color(0xFF0284C7),
                    ),
                    // Box 3: Growth Impact
                    _buildReputationImpactBox(
                      context,
                      reviewsGained: reviewsGain,
                      ratingDelta: ratingDelta,
                      googleBoosted: googleReviewsBoosted,
                    ),
                  ];

                  if (isCompact) {
                    return Column(
                      children: children
                          .map((w) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: w,
                              ))
                          .toList(),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: 14),
                      Expanded(child: children[1]),
                      const SizedBox(width: 14),
                      Expanded(child: children[2]),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReputationMetricBox(
    BuildContext context, {
    required String label,
    required String tag,
    required String rating,
    required int reviewCount,
    required IconData icon,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rating,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.star_rounded, color: AppColors.star, size: 20),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$reviewCount reviews',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReputationImpactBox(
    BuildContext context, {
    required int reviewsGained,
    required double ratingDelta,
    required int googleBoosted,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.activeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 16, color: AppColors.activeFg),
                  SizedBox(width: 6),
                  Text(
                    'AppNexa Impact',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.activeFg,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.activeFg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Verified ROI',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+$reviewsGained',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.activeFg,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Google Reviews',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.activeFg),
                ),
              ),
              const Spacer(),
              if (ratingDelta.abs() >= 0.05)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ratingDelta >= 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${ratingDelta >= 0 ? '+' : ''}${ratingDelta.toStringAsFixed(1)} ★',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: ratingDelta >= 0 ? const Color(0xFF065F46) : const Color(0xFF991B1B),
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
}
