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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/business_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';

class MyBusinessesScreen extends StatefulWidget {
  const MyBusinessesScreen({super.key});

  @override
  State<MyBusinessesScreen> createState() => _MyBusinessesScreenState();
}

class _MyBusinessesScreenState extends State<MyBusinessesScreen> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AppAuthProvider>().uid;
      if (uid != null) {
        context.read<MyBusinessesProvider>().loadFirst(uid);
      }
    });
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
    final employee = auth.employee;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Enrolled Businesses'),
        actions: [
          if (employee != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(
                avatar: const Icon(Icons.person_outline, size: 16),
                label: Text(employee.name),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Commission tracker',
            onPressed: () => context.go('/commission'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AppAuthProvider>().signOut(),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/enroll'),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Enroll New'),
      ),

      body: Column(
        children: [
          // ── Summary bar ─────────────────────────────────────────────────
          if (employee != null)
            Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Total enrolled',
                    value: '${employee.totalEnrollments}',
                  ),
                  const SizedBox(width: 16),
                  _StatChip(
                    label: 'This month',
                    value: '${employee.thisMonthEnrollments}',
                  ),
                ],
              ),
            ),

          // ── Filter bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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

          // ── Date window indicator ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Since ${DateFormat('d MMM yyyy').format(provider.since)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: provider.loading ? null : () => provider.loadOlderWindow(),
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('Load older', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Pending activation banner ─────────────────────────────────
          if (provider.pendingActivationId != null)
            _FinalizingBanner(
              onDismiss: () => provider.clearPendingActivation(),
            ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? _ErrorState(
                        message: provider.error!,
                        onRetry: () {
                          final uid = context.read<AppAuthProvider>().uid;
                          if (uid != null) provider.loadFirst(uid);
                        },
                      )
                    : provider.businesses.isEmpty
                        ? _EmptyState(
                            filter: provider.filter,
                            onEnroll: () => context.go('/enroll'),
                          )
                        : RefreshIndicator(
                            onRefresh: () => provider.refresh(),
                            child: ListView.separated(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount: provider.businesses.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text(
          'This will permanently delete "${widget.business.brandName}" '
          'and all its branches. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz    = widget.business;
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
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  biz.brandName.isNotEmpty
                      ? biz.brandName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        // Status badge
                        _StatusBadge(status: displayStatus, label: statusLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(biz.categoryType,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text('Renewal: $renewalStr',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    if (biz.isReassigned)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Text(
                            'Reassigned to admin',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                          ),
                        ),
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
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
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
                              size: 20,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            tooltip: 'Delete draft',
                            visualDensity: VisualDensity.compact,
                            onPressed: _confirmDelete,
                          ),
                ],
              ),

              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
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
    if (!provider.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'All businesses loaded',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: provider.loadingMore
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(
                onPressed: () => provider.loadMore(),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more'),
              ),
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final String label;
  const _StatusBadge({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
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
    final message = switch (filter) {
      PaymentFilter.pending    => 'No businesses awaiting payment.',
      PaymentFilter.successful => 'No businesses with successful payment.',
      PaymentFilter.all        => 'No businesses enrolled yet.',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined,
              size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(fontSize: 16, color: Colors.grey)),
          if (filter == PaymentFilter.all) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onEnroll,
              icon: const Icon(Icons.add),
              label: const Text('Enroll first business'),
            ),
          ],
        ],
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
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
  final String label, value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ],
      );
}

// ── Finalizing Banner ─────────────────────────────────────────────────────────
// Shown after Razorpay checkout SUCCESS while the webhook is in transit.
// Polls provider.refresh() every 3s until the item in the list flips to active
// (via the webhook), then the banner is automatically dismissed.

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
      final provider = context.read<MyBusinessesProvider>();
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
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
        _timer?.cancel();
        return;
      }

      // Give up after maxPolls (webhook may be delayed — user can refresh manually)
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
      color: const Color(0xFFFEF3C7), // amber-100
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Finalizing payment — please wait a moment…',
              style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF92400E),
                  fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: widget.onDismiss,
          ),
        ],
      ),
    );
  }
}

