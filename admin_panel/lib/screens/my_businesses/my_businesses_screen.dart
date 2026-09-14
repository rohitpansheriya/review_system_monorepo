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
        title: const Text('My Enrolled Businesses'),
        actions: [
          if (employee != null && MediaQuery.of(context).size.width > 480)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(
                avatar: Icon(Icons.person_outline,
                    size: 16, color: scheme.onPrimary),
                label: Text(employee.name,
                    style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
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

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/enroll'),
        icon:  const Icon(Icons.add_business_outlined),
        label: const Text('Enroll New'),
      ),

      body: Column(
        children: [
          // ── Summary bar with Live Commission Earnings Meter ──────────────
          if (employee != null)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.primaryContainer.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topLeft,
                  end:   Alignment.bottomRight,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 600 ? 20 : 12,
                vertical: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatChip(
                          icon:  Icons.business_outlined,
                          label: 'Total enrolled',
                          value: '${employee.totalEnrollments}',
                        ),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.25),
                      ),
                      Expanded(
                        child: _StatChip(
                          icon:  Icons.calendar_month_outlined,
                          label: 'This month',
                          value: '${employee.thisMonthEnrollments}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Gamified Live Commission Meter Card ───────────────────
                  InkWell(
                    onTap: () => context.go('/commission'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.monetization_on_rounded, color: Color(0xFFD97706), size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
                                      children: [
                                        TextSpan(
                                          text: '₹${NumberFormat('#,##0').format(thisMonthEarned.toInt())} ',
                                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF059669), fontSize: 16),
                                        ),
                                        TextSpan(
                                          text: 'in $currentMonthName',
                                          style: TextStyle(fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  remainingToGoal > 0 ? '₹${NumberFormat('#,##0').format(remainingToGoal)} to next' : '🎯 Target Smashed!',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: meterProgress,
                              minHeight: 7,
                              backgroundColor: scheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                meterProgress >= 1.0 ? const Color(0xFF10B981) : scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${(meterProgress * 100).toInt()}% of ₹${NumberFormat('#,##0').format(targetGoal.toInt())} ($milestoneTier)',
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('View Payouts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                                  Icon(Icons.chevron_right, size: 14, color: scheme.primary),
                                ],
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

          // ── Filter bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<PaymentFilter>(
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
            ),
          ),

          // ── Date window indicator ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Since ${DateFormat('d MMM yyyy').format(provider.since)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: provider.loading ? null : () => provider.loadOlderWindow(),
                  icon:  const Icon(Icons.history, size: 14),
                  label: const Text('Load older', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding:        const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity:  VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: scheme.outlineVariant),

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
                            filter:   provider.filter,
                            onEnroll: () => context.go('/enroll'),
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
  final VoidCallback  onEnroll;
  const _EmptyState({required this.filter, required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    final title = switch (filter) {
      PaymentFilter.pending    => 'No businesses awaiting payment',
      PaymentFilter.successful => 'No active businesses found',
      PaymentFilter.all        => 'No businesses enrolled yet',
    };
    final subtitle = switch (filter) {
      PaymentFilter.pending    => 'Businesses awaiting initial subscription payment will appear here.',
      PaymentFilter.successful => 'Businesses with active subscriptions will appear here.',
      PaymentFilter.all        => 'Tap the button below to enroll your first client business.',
    };

    return AppEmptyState(
      icon: Icons.storefront_outlined,
      title: title,
      subtitle: subtitle,
      actionLabel: filter == PaymentFilter.all ? 'Enroll First Business' : null,
      onAction: filter == PaymentFilter.all ? onEnroll : null,
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

// ── Stat Chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w700,
                color:      scheme.onPrimaryContainer,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color:    scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ],
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
