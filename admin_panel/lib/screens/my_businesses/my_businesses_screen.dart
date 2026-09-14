// lib/screens/my_businesses/my_businesses_screen.dart
//
// Employee home screen: paginated + filtered list of enrolled businesses.
//
// Changes from previous version:
//   - SegmentedButton<PaymentFilter> filter bar (applied at query level)
//   - Date-window indicator with "Load older" button
//   - "Load more" at bottom of list for cursor pagination
//   - Delete button: visible ONLY for pending_payment drafts
//   - Edit button: visible for all (pending + active)
//   - Pull-to-refresh
//
// Styling: all Colors.* replaced with theme tokens and AppTheme semantic colors.
//   _StatusBadge bug fixed: foreground now uses AppTheme.statusForeground (was
//   incorrectly using statusColor which is the background tint).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../widgets/app_animated_loader.dart';
import '../../widgets/app_splash_screen.dart';
import '../../core/logout_helper.dart';
import '../../models/business_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/month_year_picker_dialog.dart';

class MyBusinessesScreen extends StatefulWidget {
  const MyBusinessesScreen({super.key});

  @override
  State<MyBusinessesScreen> createState() => _MyBusinessesScreenState();
}

class _MyBusinessesScreenState extends State<MyBusinessesScreen> {
  late final ScrollController _scrollCtrl;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AppAuthProvider>(context);
    final uid = auth.uid;
    if (!_initialized && uid != null && auth.status == AuthStatus.authenticated) {
      _initialized = true;
      final queryId = auth.isAdmin ? 'admin' : uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<MyBusinessesProvider>().loadFirst(queryId);
          if (!auth.isAdmin) {
            context.read<CommissionProvider>().startListening(uid);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AppAuthProvider>();
    final provider = context.watch<MyBusinessesProvider>();
    final commProvider = context.watch<CommissionProvider>();
    final employee = auth.employee;
    final scheme   = Theme.of(context).colorScheme;

    if (auth.status == AuthStatus.unknown || auth.loading) {
      return const AppSplashScreen(message: 'Authenticating…');
    }

    // Calculate live earnings this month for employee
    final currentMonthStr = DateFormat('yyyy-MM').format(DateTime.now());
    final currentMonthName = DateFormat('MMMM').format(DateTime.now());
    
    double thisMonthEarned = commProvider.records
        .where((r) => r.activationMonth == currentMonthStr)
        .fold(0.0, (sum, r) => sum + r.amount);

    if (thisMonthEarned == 0 && (employee?.thisMonthEnrollments ?? 0) > 0) {
      thisMonthEarned = (employee!.thisMonthEnrollments * AppConstants.commissionAmountPerActivation).toDouble();
    }

    // Dynamic gamified milestones
    double targetGoal = 5000.0;
    String milestoneTier = 'Rising Star';
    if (thisMonthEarned < 2500) {
      targetGoal = 2500.0;
      milestoneTier = 'Bronze Starter';
    } else if (thisMonthEarned < 5000) {
      targetGoal = 5000.0;
      milestoneTier = 'Silver Closer';
    } else if (thisMonthEarned < 10000) {
      targetGoal = 10000.0;
      milestoneTier = 'Gold Champion';
    } else {
      targetGoal = ((thisMonthEarned ~/ 5000) + 1) * 5000.0;
      milestoneTier = 'Platinum Legend';
    }

    final double meterProgress = (thisMonthEarned / targetGoal).clamp(0.0, 1.0);
    final int remainingToGoal = (targetGoal - thisMonthEarned).toInt();

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/appnexa-logo-white.png',
          height: 26,
          fit: BoxFit.contain,
        ),
        actions: [
          if (employee != null && MediaQuery.of(context).size.width > 480)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(
                avatar: Icon(Icons.person_outline,
                    size: 16, color: scheme.onPrimary),
                label: Text(employee.name,
                    style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                backgroundColor: scheme.primary.withValues(alpha: 0.5),
                side: BorderSide(color: scheme.onPrimary.withValues(alpha: 0.3)),
              ),
            ),
          IconButton(
            icon:    const Icon(Icons.account_circle_outlined),
            tooltip: 'My Profile & Payout Details',
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            icon:    const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => confirmAndSignOut(context),
          ),
        ],
      ),

      floatingActionButton: MediaQuery.of(context).size.width <= 720
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/enroll'),
              icon:  const Icon(Icons.add_business_outlined),
              label: const Text('Enroll New'),
            )
          : null,

      body: Column(
        children: [
          // ── Professional Page Title & Actions ───────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              MediaQuery.of(context).size.width > 600 ? 20 : 16,
              16,
              MediaQuery.of(context).size.width > 600 ? 20 : 16,
              12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enrolled Businesses',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Track and manage client business enrollments, branches, and live commissions',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (MediaQuery.of(context).size.width > 720)
                      FilledButton.icon(
                        onPressed: () => context.go('/enroll'),
                        icon: const Icon(Icons.add_business_outlined, size: 17),
                        label: const Text('Enroll New Business', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Executive KPI & Performance Cards ──────────────────────
                if (employee != null)
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      final isWide = constraints.maxWidth > 760;

                      final kpiCard = Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.storefront_rounded, size: 20, color: scheme.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${employee.totalEnrollments}',
                                          style: GoogleFonts.inter(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          'Total Enrolled',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 36,
                              width: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              color: const Color(0xFFCBD5E1),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.calendar_month_rounded, size: 20, color: Color(0xFF059669)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${employee.thisMonthEnrollments}',
                                          style: GoogleFonts.inter(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          'This Month',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );

                      final earningsCard = InkWell(
                        onTap: () => context.go('/commission'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.monetization_on_rounded, color: Color(0xFFD97706), size: 16),
                                      ),
                                      const SizedBox(width: 8),
                                      RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                                          children: [
                                            TextSpan(
                                              text: '₹${NumberFormat('#,##0').format(thisMonthEarned.toInt())} ',
                                              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF059669), fontSize: 16),
                                            ),
                                            TextSpan(
                                              text: 'earned in $currentMonthName',
                                              style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF64748B), fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      remainingToGoal > 0 ? '₹${NumberFormat('#,##0').format(remainingToGoal)} to next' : '🎯 Target Reached',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: meterProgress,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    meterProgress >= 1.0 ? const Color(0xFF10B981) : scheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${(meterProgress * 100).toInt()}% of ₹${NumberFormat('#,##0').format(targetGoal.toInt())} goal ($milestoneTier)',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('View Ledger', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                                      Icon(Icons.chevron_right, size: 13, color: scheme.primary),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(flex: 5, child: kpiCard),
                            const SizedBox(width: 12),
                            Expanded(flex: 6, child: earningsCard),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            kpiCard,
                            const SizedBox(height: 10),
                            earningsCard,
                          ],
                        );
                      }
                    },
                  ),
              ],
            ),
          ),

          // ── Filter & Period Controls Bar ────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Status Segmented Selector
                SegmentedButton<PaymentFilter>(
                  segments: PaymentFilter.values.map((f) => ButtonSegment(
                    value: f,
                    label: Text(f.label, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  selected: {provider.filter},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) provider.applyFilter(s.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),

                // Interactive Month Navigator with 1-click steppers
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
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
                            onCustomRangeSelected: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2024, 1, 1),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDateRange: provider.startDate != null && provider.endDate != null
                                    ? DateTimeRange(start: provider.startDate!, end: provider.endDate!)
                                    : DateTimeRange(
                                        start: DateTime(DateTime.now().year, DateTime.now().month, 1),
                                        end: DateTime.now(),
                                      ),
                                helpText: 'Select Date Range',
                              );
                              if (picked != null) {
                                provider.setDateRange(picked.start, picked.end);
                              }
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                provider.isAllTime ? Icons.all_inclusive_rounded : Icons.calendar_month_rounded,
                                size: 14,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                provider.dateLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(Icons.unfold_more_rounded, size: 14, color: scheme.onSurfaceVariant),
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

                // Custom Date Range Picker Button
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: provider.startDate != null && provider.endDate != null
                          ? DateTimeRange(start: provider.startDate!, end: provider.endDate!)
                          : DateTimeRange(
                              start: DateTime(DateTime.now().year, DateTime.now().month, 1),
                              end: DateTime.now(),
                            ),
                      helpText: 'Select Date Range',
                    );
                    if (picked != null) {
                      provider.setDateRange(picked.start, picked.end);
                    }
                  },
                  icon: const Icon(Icons.date_range_outlined, size: 13),
                  label: const Text('Date Range', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: provider.selectedMonthKey == null && !provider.isAllTime
                          ? scheme.primary
                          : scheme.outlineVariant,
                    ),
                  ),
                ),

                // Quick Reset to Current Month
                if (provider.selectedMonthKey != DateFormat('yyyy-MM').format(DateTime.now()))
                  ActionChip(
                    avatar: const Icon(Icons.refresh_rounded, size: 13),
                    label: const Text('This Month', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => provider.setThisMonth(),
                  ),
              ],
            ),
          ),

          // ── Pending activation banner ─────────────────────────────────
          if (provider.pendingActivationId != null)
            _FinalizingBanner(
              onDismiss: () => provider.clearPendingActivation(),
            ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: provider.loading
                ? const Center(
                    child: AppAnimatedLoader.card(
                      message: 'Loading enrolled businesses…',
                    ),
                  )
                : provider.error != null
                    ? _ErrorState(
                        message:  provider.error!,
                        onRetry: () {
                          final auth = context.read<AppAuthProvider>();
                          final uid = auth.uid;
                          if (uid != null) {
                            final queryId = auth.isAdmin ? 'admin' : uid;
                            provider.loadFirst(queryId);
                          }
                        },
                      )
                    : provider.businesses.isEmpty
                        ? _EmptyState(
                            filter:     provider.filter,
                            dateLabel:  provider.dateLabel,
                            isAllTime:  provider.isAllTime,
                            onEnroll:   () => context.go('/enroll'),
                          )
                        : RefreshIndicator(
                            onRefresh: () => provider.refresh(),
                            child: ListView.separated(
                              controller:    _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount:     provider.businesses.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (_, i) {
                                if (i == provider.businesses.length) {
                                  return _LoadMoreButton(provider: provider);
                                }
                                return _BusinessCard(
                                  business: provider.businesses[i],
                                  onDeleteSuccess: () =>
                                      provider.removeLocal(provider.businesses[i].id),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Business Card ─────────────────────────────────────────────────────────────

class _BusinessCard extends StatefulWidget {
  final BusinessModel business;
  final VoidCallback  onDeleteSuccess;
  const _BusinessCard({required this.business, required this.onDeleteSuccess});

  @override
  State<_BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<_BusinessCard> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppModalDialog(
        icon: Icons.delete_forever_rounded,
        iconColor: scheme.error,
        title: 'Delete draft?',
        subtitle: 'Permanent deletion of pending enrollment',
        maxWidth: 440,
        content: Text(
          'This will permanently delete "${widget.business.brandName}" and all its branch drafts. This cannot be undone.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await context.read<FirestoreService>().deleteDraftBusiness(widget.business.id);
      if (mounted) widget.onDeleteSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz    = widget.business;
    final scheme = Theme.of(context).colorScheme;
    final status = biz.subscriptionStatus;
    final isDue  = biz.isDueSoon(30);
    final displayStatus = (isDue && status == AppConstants.statusActive)
        ? 'due_soon'
        : status;
    final statusLabel = {
      'pending_payment': 'Awaiting Payment',
      'active':          'Active',
      'due_soon':        'Due soon',
      'grace_period':    'Grace period',
      'deleted':         'Deleted',
    }[displayStatus] ?? status;

    final renewalStr = biz.renewalDate != null
        ? DateFormat('d MMM yyyy').format(biz.renewalDate!)
        : (status == AppConstants.statusPendingPayment ? 'Pending payment' : '—');

    final isPending = status == AppConstants.statusPendingPayment;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/business/${biz.id}', extra: biz),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ────────────────────────────────────────────────
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  biz.brandName.isNotEmpty
                      ? biz.brandName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize:   17,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Info ──────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            biz.brandName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        // Status badge
                        AppBadge.subscription(displayStatus, customLabel: statusLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      biz.categoryType,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      'Renewal: $renewalStr',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              // ── Action buttons ────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit button — always visible
                  IconButton(
                    icon:           const Icon(Icons.edit_outlined, size: 20),
                    tooltip:        'Edit',
                    visualDensity:  VisualDensity.compact,
                    onPressed: () => context.push(
                      '/business/${biz.id}/edit',
                      extra: biz,
                    ),
                  ),

                  // Delete button — ONLY for pending_payment
                  if (isPending)
                    _deleting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size:  20,
                              color: scheme.error,
                            ),
                            tooltip:       'Delete draft',
                            visualDensity: VisualDensity.compact,
                            onPressed:     _confirmDelete,
                          ),
                ],
              ),

              IconButton(
                icon: Icon(Icons.arrow_forward_ios, size: 16, color: scheme.onSurfaceVariant),
                tooltip: 'View Details',
                visualDensity: VisualDensity.compact,
                onPressed: () => context.push('/business/${biz.id}', extra: biz),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Load More Button ──────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final MyBusinessesProvider provider;
  const _LoadMoreButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!provider.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Text(
            'All businesses loaded',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: provider.loadingMore
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(
                onPressed: () => provider.loadMore(),
                icon:  const Icon(Icons.expand_more),
                label: const Text('Load more'),
              ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final PaymentFilter filter;
  final String        dateLabel;
  final bool          isAllTime;
  final VoidCallback  onEnroll;

  const _EmptyState({
    required this.filter,
    required this.dateLabel,
    required this.isAllTime,
    required this.onEnroll,
  });

  @override
  Widget build(BuildContext context) {
    final title = switch (filter) {
      PaymentFilter.pending    => 'No businesses awaiting payment',
      PaymentFilter.successful => 'No active businesses found',
      PaymentFilter.all        => isAllTime ? 'No businesses enrolled yet' : 'No businesses enrolled for $dateLabel',
    };
    final subtitle = switch (filter) {
      PaymentFilter.pending    => 'Businesses awaiting initial subscription payment for $dateLabel will appear here.',
      PaymentFilter.successful => 'Businesses with active subscriptions for $dateLabel will appear here.',
      PaymentFilter.all        => isAllTime
          ? 'Tap the button below to enroll your first client business.'
          : 'No enrollments found for $dateLabel. Tap below to enroll or change the date filter.',
    };

    return AppEmptyState(
      icon: Icons.storefront_outlined,
      title: title,
      subtitle: subtitle,
      actionLabel: 'Enroll New Business',
      onAction: onEnroll,
    );
  }
}

// ── Error State ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Finalizing Banner ─────────────────────────────────────────────────────────
// Shown after Razorpay checkout SUCCESS while the webhook is in transit.
// Polls provider.refresh() every 3s until the item flips to active, then dismisses.

class _FinalizingBanner extends StatefulWidget {
  final VoidCallback onDismiss;
  const _FinalizingBanner({required this.onDismiss});

  @override
  State<_FinalizingBanner> createState() => _FinalizingBannerState();
}

class _FinalizingBannerState extends State<_FinalizingBanner> {
  Timer? _timer;
  int _polls = 0;
  static const _maxPolls = 10;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      _polls++;
      final provider  = context.read<MyBusinessesProvider>();
      final pendingId = provider.pendingActivationId;
      if (pendingId == null) { _timer?.cancel(); return; }

      await provider.refresh();
      if (!mounted) return;

      // Check if the business in the list is now active.
      final biz = provider.businesses.where((b) => b.id == pendingId).firstOrNull;
      if (biz != null && biz.subscriptionStatus == AppConstants.statusActive) {
        provider.clearPendingActivation();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ Payment confirmed — business is now active!'),
          backgroundColor: AppColors.activeFg,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
        _timer?.cancel();
        return;
      }

      // Give up after maxPolls — user can refresh manually.
      if (_polls >= _maxPolls) {
        _timer?.cancel();
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.pendingBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.pendingFg,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Finalizing payment — please wait a moment…',
              style: TextStyle(
                fontSize:   13,
                color:      AppColors.pendingFg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon:          Icon(Icons.close, size: 16, color: AppColors.pendingFg),
            tooltip:       'Dismiss',
            padding:       EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed:     widget.onDismiss,
          ),
        ],
      ),
    );
  }
}
