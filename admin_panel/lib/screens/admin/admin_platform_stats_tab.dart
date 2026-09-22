// lib/screens/admin/admin_platform_stats_tab.dart
//
// Platform-Wide Stats Tab (Doc 04 Admin Panel).
// Renders total businesses, scans, renewals due (grouped 30/15/7/1 days),
// revenue snapshot using Firestore count() aggregation queries (Scalability Rule #3).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/business_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_kpi_card.dart';
import '../../widgets/app_search_bar.dart';
import '../../providers/auth_provider.dart';

class AdminPlatformStatsTab extends StatelessWidget {
  const AdminPlatformStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isDesktop = MediaQuery.of(context).size.width > 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Platform-Wide Analytics',
                    style: (isDesktop ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aggregated via Firestore count() queries (Scalability Rule #3).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton.filledTonal(
                onPressed:
                    provider.loading
                        ? null
                        : () async {
                          await provider.loadAdminData(forceReload: true);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Platform stats and revenue refreshed!',
                                ),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                icon:
                    provider.loading
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh),
                tooltip: 'Refresh Stats & Revenue',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Stat KPI Cards Grid ───────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount =
                  constraints.maxWidth > 900
                      ? 4
                      : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: constraints.maxWidth > 900
                    ? 1.45
                    : (constraints.maxWidth > 600 ? 1.7 : 2.5),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  AppKpiCard(
                    label: 'Total Paying Businesses',
                    value: '${provider.totalBusinessesCount}',
                    subtitle:
                        '${provider.totalActiveBranches} active location${provider.totalActiveBranches == 1 ? '' : 's'} across ${provider.totalBusinessesCount} brand${provider.totalBusinessesCount == 1 ? '' : 's'}${provider.testBusinessesCount > 0 ? ' • ${provider.testBusinessesCount} test' : ''}',
                    icon: Icons.store_rounded,
                    color: colorScheme.primary,
                  ),
                  AppKpiCard(
                    label: 'Active Subscriptions',
                    value: '${provider.activeBusinessesCount}',
                    subtitle:
                        provider.testBusinessesCount > 0
                            ? '${provider.totalActiveBranches} active paid branch${provider.totalActiveBranches == 1 ? '' : 'es'} • ${provider.testBusinessesCount} test'
                            : '${provider.totalActiveBranches} active paid branch${provider.totalActiveBranches == 1 ? '' : 'es'}',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.activeFg,
                  ),
                  AppKpiCard(
                    label: 'Grace Period',
                    value: '${provider.graceBusinessesCount}',
                    subtitle: 'Requires renewal',
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.graceFg,
                  ),
                  AppKpiCard(
                    label: 'Active Locations',
                    value: '${provider.totalActiveBranches}',
                    subtitle: 'Live review routing branches',
                    icon: Icons.location_on_rounded,
                    color: colorScheme.secondary,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Revenue, Payment Collections & Renewals Breakdown ────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 960;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card 1: Payment Collections & Revenue
                  Expanded(
                    flex: isWide ? 1 : 0,
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Revenue & Collections',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                // ── Month Selector Dropdown ──
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00458B).withValues(alpha: 0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value: provider.selectedRevenueMonth,
                                      dropdownColor: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      elevation: 8,
                                      isDense: true,
                                      icon: const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 18,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('All Time'),
                                        ),
                                        ...provider.availableRevenueMonths.map((
                                          m,
                                        ) {
                                          String label = m;
                                          try {
                                            label = DateFormat(
                                              'MMMM yyyy',
                                            ).format(DateTime.parse('$m-01'));
                                          } catch (_) {}
                                          return DropdownMenuItem<String?>(
                                            value: m,
                                            child: Text(label),
                                          );
                                        }),
                                      ],
                                      onChanged: (val) {
                                        provider.setSelectedRevenueMonth(val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '₹${provider.revenueSnapshot.toStringAsFixed(0)}',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  provider.selectedRevenueMonth != null
                                      ? '(${DateFormat('MMMM yyyy').format(DateTime.parse('${provider.selectedRevenueMonth}-01'))})'
                                      : '(All-Time Total)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── Revenue Streams (New Enrollments vs Annual Renewals) ──
                            Text(
                              'REVENUE STREAMS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildPaymentMethodRow(
                              context,
                              label: 'New Client Enrollments (₹1,999)',
                              amount: provider.newEnrollmentsRevenue,
                              count: provider.newEnrollmentsCount,
                              icon: Icons.person_add_alt_1_outlined,
                              color: const Color(0xFF16A34A),
                            ),
                            const SizedBox(height: 6),
                            _buildPaymentMethodRow(
                              context,
                              label: 'Annual Subscriptions (₹999)',
                              amount: provider.renewalsRevenue,
                              count: provider.renewalsCount,
                              icon: Icons.autorenew_rounded,
                              color: const Color(0xFF2563EB),
                            ),

                            const Divider(height: 20),

                            // ── Payment Methods (Online vs Cash) ──
                            Text(
                              'PAYMENT CHANNELS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildPaymentMethodRow(
                              context,
                              label: 'Online (Razorpay)',
                              amount: provider.onlineRevenue,
                              count: provider.onlinePaymentsCount,
                              icon: Icons.credit_card,
                              color: Colors.blue,
                            ),
                            const SizedBox(height: 6),
                            _buildPaymentMethodRow(
                              context,
                              label: 'Cash (Admin Verified)',
                              amount: provider.cashRevenue,
                              count: provider.cashPaymentsCount,
                              icon: Icons.payments_outlined,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),

                  // Card 2: Branch Locations Overview
                  Expanded(
                    flex: isWide ? 1 : 0,
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
                                Icon(
                                  Icons.location_city_outlined,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Branch Locations Health',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Text(
                              '${provider.totalActiveBranches} Active',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildBranchStatusRow(
                              context,
                              label: 'Active Branches (Paid / Live)',
                              count: provider.totalActiveBranches,
                              icon: Icons.check_circle_outline,
                              color: Colors.green,
                            ),
                            const SizedBox(height: 8),
                            _buildBranchStatusRow(
                              context,
                              label: 'Pending Payment Branches',
                              count: provider.totalPendingBranches,
                              icon: Icons.hourglass_top_outlined,
                              color: Colors.amber[800]!,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),

                  // Card 3: Renewals Due Breakdown
                  Expanded(
                    flex: isWide ? 1 : 0,
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
                                Icon(
                                  Icons.calendar_month,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Upcoming Renewals',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _buildRenewalRow(
                              context,
                              'Due in 30 Days',
                              provider.renewalsDue30,
                              Colors.blue,
                            ),
                            const SizedBox(height: 6),
                            _buildRenewalRow(
                              context,
                              'Due in 15 Days',
                              provider.renewalsDue15,
                              Colors.amber,
                            ),
                            const SizedBox(height: 6),
                            _buildRenewalRow(
                              context,
                              'Due in 7 Days',
                              provider.renewalsDue7,
                              Colors.deepOrange,
                            ),
                            const SizedBox(height: 6),
                            _buildRenewalRow(
                              context,
                              'Due Today / Tomorrow',
                              provider.renewalsDue1,
                              Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // ── All Enrolled Businesses Table & Admin Editing ─────────────────
          _AllBusinessesTableSection(),
        ],
      ),
    );
  }



  Widget _buildRenewalRow(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
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

  Widget _buildPaymentMethodRow(
    BuildContext context, {
    required String label,
    required double amount,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
            Text(
              '$count paid',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBranchStatusRow(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _AllBusinessesTableSection extends StatefulWidget {
  @override
  State<_AllBusinessesTableSection> createState() =>
      _AllBusinessesTableSectionState();
}

class _AllBusinessesTableSectionState
    extends State<_AllBusinessesTableSection> {
  String _filterStatus = 'all';
  String _searchQuery = '';

  void _showConvertToLiveDialog(BuildContext context, BusinessModel biz) {
    final provider = context.read<AdminDashboardProvider>();
    final stats = provider.businessBranchStats[biz.id];
    final isCurrentlyActive = biz.subscriptionStatus == 'active' || (stats != null && stats.active > 0);
    final activeBranchCount = stats?.active ?? 1;

    String selectedMode = 'cash';
    bool isProcessing = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: !isProcessing,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AppModalDialog(
            maxWidth: 520,
            icon: Icons.rocket_launch_rounded,
            iconColor: const Color(0xFFD97706),
            title: 'Convert to Live Business',
            subtitle: biz.brandName,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Converting this business to Live will keep the permanent Business ID (${biz.displayCode}) and all Branch IDs intact. Already printed QR standees and review URLs will continue working seamlessly.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF92400E),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Payment Method for Live Account:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 10),

                // Cash Option
                InkWell(
                  onTap: isProcessing ? null : () => setDialogState(() => selectedMode = 'cash'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedMode == 'cash' ? AppColors.activeBg : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedMode == 'cash' ? AppColors.activeFg : Colors.grey.shade300,
                        width: selectedMode == 'cash' ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<String>(
                          value: 'cash',
                          groupValue: selectedMode,
                          activeColor: AppColors.activeFg,
                          onChanged: isProcessing ? null : (val) => setDialogState(() => selectedMode = val!),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cash Payment (Keep Active & Count in Revenue)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCurrentlyActive
                                    ? 'No change required for payment method. It will remain active and immediately add ₹${(biz.amountPaid ?? (activeBranchCount * 1999)).toStringAsFixed(0)} to platform revenue and active subscriptions.'
                                    : 'Activates the business as paid via cash and adds setup fee to live platform revenue.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Online Option
                InkWell(
                  onTap: isProcessing ? null : () => setDialogState(() => selectedMode = 'online'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedMode == 'online' ? AppColors.primary.withValues(alpha: 0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedMode == 'online' ? AppColors.primary : Colors.grey.shade300,
                        width: selectedMode == 'online' ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<String>(
                          value: 'online',
                          groupValue: selectedMode,
                          activeColor: AppColors.primary,
                          onChanged: isProcessing ? null : (val) => setDialogState(() => selectedMode = val!),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Online Payment (Razorpay Payment Link)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCurrentlyActive
                                    ? 'Converts active business into Pending Payment so you or the employee can generate and send an official Razorpay online payment link to the owner.'
                                    : 'Already in Pending Payment status. Converts to live account ready for online Razorpay collection without changing activation status.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isProcessing
                    ? null
                    : () async {
                        setDialogState(() {
                          isProcessing = true;
                          errorMessage = null;
                        });
                        try {
                          final auth = context.read<AppAuthProvider>();
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          await provider.convertTestBusinessToLive(
                            businessId: biz.id,
                            paymentMode: selectedMode,
                            isCurrentlyActive: isCurrentlyActive,
                            activeBranchCount: activeBranchCount,
                            adminUid: auth.uid,
                          );
                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                          }
                          if (mounted) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text('🎉 "${biz.brandName}" converted to Live Business successfully!'),
                                backgroundColor: AppColors.activeFg,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isProcessing = false;
                            errorMessage = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                icon: isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(isProcessing ? 'Converting...' : 'Convert to Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditBusinessDialog(BuildContext context, BusinessModel biz) {
    final brandCtrl = TextEditingController(text: biz.brandName);
    final catCtrl = TextEditingController(text: biz.categoryType);
    final ownerNameCtrl = TextEditingController(text: biz.ownerName ?? '');
    final ownerEmailCtrl = TextEditingController(text: biz.ownerEmail ?? '');
    final ownerPhoneCtrl = TextEditingController(text: biz.ownerPhone ?? '');
    String status = biz.subscriptionStatus;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setDialogState) => AppModalDialog(
                  headerIcon: Icons.storefront_rounded,
                  title: 'Edit Business Details',
                  subtitle: biz.brandName.isNotEmpty ? biz.brandName : biz.id,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: brandCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Brand Name',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: catCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Category Type',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Owner Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerEmailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Owner Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Owner Phone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: status,
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 8,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        decoration: const InputDecoration(
                          labelText: 'Subscription Status',
                          prefixIcon: Icon(Icons.shield_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'pending_payment',
                            child: Text('Pending Payment'),
                          ),
                          DropdownMenuItem(
                            value: 'grace_period',
                            child: Text('Grace Period'),
                          ),
                          DropdownMenuItem(
                            value: 'suspended',
                            child: Text('Suspended'),
                          ),
                          DropdownMenuItem(
                            value: 'deleted',
                            child: Text('Deleted'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => status = v);
                        },
                      ),
                    ],
                  ),
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
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
                            const SnackBar(
                              content: Text('Business details updated.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save Changes'),
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

    final filtered =
        allBiz.where((b) {
          final branchStats = provider.businessBranchStats[b.id];
          final hasPendingBranch = (branchStats?.pending ?? 0) > 0;
          final statusMatch =
              _filterStatus == 'all'
                  ? true
                  : (_filterStatus == 'live_only'
                      ? !b.isTestAccount
                      : (_filterStatus == 'test_only'
                          ? b.isTestAccount
                          : (_filterStatus == 'has_pending_branch'
                              ? hasPendingBranch
                              : b.subscriptionStatus == _filterStatus)));
          final brandName = b.brandName.toLowerCase();
          final ownerEmail = (b.ownerEmail ?? '').toLowerCase();
          final q = _searchQuery.toLowerCase().trim();
          final queryMatch =
              q.isEmpty || brandName.contains(q) || ownerEmail.contains(q);
          return statusMatch && queryMatch;
        }).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? 24.0 : 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Text(
                  provider.testBusinessesCount > 0
                      ? 'All Enrolled Businesses (${filtered.length}) • ${provider.totalBusinessesCount} Live, ${provider.testBusinessesCount} Test'
                      : 'All Enrolled Businesses (${filtered.length})',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppSearchBar(
                      width: MediaQuery.of(context).size.width > 500 ? 230 : double.infinity,
                      hintText: 'Search brand / email…',
                      initialValue: _searchQuery,
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                          value: _filterStatus,
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
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All Statuses'),
                            ),
                            DropdownMenuItem(
                              value: 'live_only',
                              child: Text('Live Businesses Only 🟢'),
                            ),
                            DropdownMenuItem(
                              value: 'test_only',
                              child: Text('Test Accounts Only 🧪'),
                            ),
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: 'has_pending_branch',
                              child: Text('Has Pending Branch ⚠️'),
                            ),
                            DropdownMenuItem(
                              value: 'pending_payment',
                              child: Text('Pending Payment'),
                            ),
                            DropdownMenuItem(
                              value: 'grace_period',
                              child: Text('Grace Period'),
                            ),
                            DropdownMenuItem(
                              value: 'suspended',
                              child: Text('Suspended / Lapsed'),
                            ),
                            DropdownMenuItem(
                              value: 'deleted',
                              child: Text('Deleted'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _filterStatus = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),

            if (filtered.isEmpty)
              const AppEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No Matching Businesses Found',
                message: 'No enrolled businesses match your current search query or filter selection.',
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
                    DataColumn(label: Text('Branches / Locations')),
                    DataColumn(label: Text('Managed By')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows:
                      filtered.map((b) {
                        final status = b.subscriptionStatus;
                        final stats = provider.businessBranchStats[b.id];
                        final hasPending = (stats?.pending ?? 0) > 0;
                        final hasSuspended = (stats?.suspended ?? 0) > 0 || status == 'suspended';

                        return DataRow(
                          cells: [
                            DataCell(
                              InkWell(
                                onTap:
                                    () => context.push(
                                      '/business/${b.id}',
                                      extra: b,
                                    ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (b.isTestAccount) ...[
                                      AppBadge(
                                        label: 'TEST',
                                        backgroundColor: const Color(0xFFFEF3C7),
                                        foregroundColor: const Color(0xFFD97706),
                                        icon: Icons.science_rounded,
                                        fontSize: 10,
                                      ),
                                      const SizedBox(width: 6),
                                    ] else if (b.businessCode != null) ...[
                                      AppBadge.code(
                                        b.businessCode!,
                                        isTest: false,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      b.brandName.isNotEmpty
                                          ? b.brandName
                                          : '—',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: b.isTestAccount ? const Color(0xFFD97706) : Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.open_in_new,
                                      size: 14,
                                      color: b.isTestAccount ? const Color(0xFFD97706) : Colors.blue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                b.categoryType.isNotEmpty
                                    ? b.categoryType
                                    : '—',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${b.ownerName ?? '—'}\n${b.ownerEmail ?? ''}',
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppBadge.subscription(status),
                                  if (b.isTestAccount) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFFDE68A)),
                                      ),
                                      child: const Text(
                                        'Test',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            DataCell(
                              stats == null
                                  ? const Text('1 Location')
                                  : (hasSuspended
                                      ? AppBadge(
                                          label: '${(stats.suspended > 0 ? stats.suspended : stats.total)} Suspended',
                                          backgroundColor: const Color(0xFFFEE2E2),
                                          foregroundColor: const Color(0xFFDC2626),
                                          icon: Icons.pause_circle_outline_rounded,
                                          fontSize: 11,
                                          onTap: () => context.push('/business/${b.id}', extra: b),
                                        )
                                      : (stats.grace > 0 || status == 'grace_period'
                                          ? AppBadge(
                                              label: '${stats.grace > 0 ? stats.grace : stats.total} in Grace',
                                              backgroundColor: AppColors.graceBg,
                                              foregroundColor: AppColors.graceFg,
                                              icon: Icons.warning_amber_rounded,
                                              fontSize: 11,
                                              onTap: () => context.push('/business/${b.id}', extra: b),
                                            )
                                          : (hasPending
                                              ? AppBadge(
                                                  label: stats.active > 0
                                                      ? '${stats.active} Active, ${stats.pending} Pending'
                                                      : '${stats.pending} Pending',
                                                  backgroundColor: AppColors.pendingBg,
                                                  foregroundColor: AppColors.pendingFg,
                                                  icon: Icons.hourglass_top_rounded,
                                                  fontSize: 11,
                                                  onTap: () => context.push('/business/${b.id}', extra: b),
                                                )
                                              : AppBadge.count(
                                                  label: '${stats.active} Active ${stats.active == 1 ? "Location" : "Locations"}',
                                                  color: AppColors.activeFg,
                                                  backgroundColor: AppColors.activeBg,
                                                  icon: Icons.check_circle_rounded,
                                                )))),
                            ),
                            DataCell(
                              Text(
                                provider.resolveEmployeeName(
                                  b.currentlyManagedBy,
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (b.isTestAccount)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.rocket_launch_rounded,
                                        color: Color(0xFFD97706),
                                      ),
                                      tooltip: 'Convert to Live Business',
                                      onPressed:
                                          () =>
                                              _showConvertToLiveDialog(context, b),
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_forward,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'View Business Details',
                                    onPressed:
                                        () => context.push(
                                          '/business/${b.id}',
                                          extra: b,
                                        ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Edit Business Details',
                                    onPressed:
                                        () =>
                                            _showEditBusinessDialog(context, b),
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
