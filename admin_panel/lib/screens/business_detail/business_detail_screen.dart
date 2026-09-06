// lib/screens/business_detail/business_detail_screen.dart
//
// Detail view for a single enrolled business.
// Shows business-level info + all branches with star routing.
// Edit button (FAB) navigates to BusinessEditScreen.
//
// Changes in this file:
//   Change 1 — "Download printable QR" button per branch when
//               plain_qr_storage_path is set (only after activation).
//   Change 2 — Standee fulfillment status dropdown per branch (employee updates).
//   Change 3 — For pending_payment businesses: amber "Resend payment link" panel
//               with action button; displays/copies the returned short_url.
//
// Styling: all Colors.* replaced with AppTheme/AppColors semantic tokens.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/share_business_qr.dart';
import '../../widgets/app_animated_loader.dart';
import '../enroll/branch_form_widget.dart';

class BusinessDetailScreen extends StatefulWidget {
  final BusinessModel business;
  const BusinessDetailScreen({super.key, required this.business});

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  late BusinessModel _business;
  List<BranchModel> _branches = [];
  bool _loading = true;
  String? _error;

  String? _enrolledByName;

  @override
  void initState() {
    super.initState();
    _business = widget.business;
    _refreshBusiness();
  }

  Future<void> _refreshBusiness() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(_business.id)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _business = BusinessModel.fromDoc(doc);
        });
      }
      await _loadBranches();
      if (mounted) {
        try {
          final auth = context.read<AppAuthProvider>();
          if (auth.isAdmin) {
            context.read<AdminDashboardProvider>().loadAdminData();
          } else {
            context.read<MyBusinessesProvider>().refresh();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _loadBranches() async {
    try {
      final svc = context.read<FirestoreService>();
      final branches = await svc.getBranches(_business.id);
      final empName = await svc.getEmployeeName(_business.enrolledBy);
      if (mounted) {
        setState(() {
          _branches = branches;
          _enrolledByName = empName;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showAddBranchDialog(BuildContext context) {
    final draft = BranchDraft();
    bool showErrors = false;
    bool saving = false;
    String? saveError;
    final auth = context.read<AppAuthProvider>();
    final enrolledBy = auth.isAdmin ? 'admin' : (auth.uid ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Add New Branch to "${_business.brandName}"'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BranchFormWidget(
                    branchIndex: _branches.length,
                    draft: draft,
                    showBranchName: true,
                    showError: showErrors,
                    ownerPhone: _business.ownerPhone,
                    ownerName: _business.ownerName,
                    onChanged: () => setDlgState(() {}),
                  ),
                  if (saveError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        saveError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      showErrors = true;
                      if (draft.name.trim().isEmpty) {
                        setDlgState(() => saveError = 'Branch name is required.');
                        return;
                      }
                      if (draft.address.trim().isEmpty) {
                        setDlgState(() => saveError = 'Address is required.');
                        return;
                      }
                      if (draft.whatsappNumber.trim().isEmpty) {
                        setDlgState(() => saveError = 'WhatsApp number is required.');
                        return;
                      }
                      if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(draft.whatsappNumber.trim())) {
                        setDlgState(() => saveError = 'Please enter a valid 10-digit WhatsApp number.');
                        return;
                      }
                      if (draft.whatsappMonitoredBy.trim().isEmpty) {
                        setDlgState(() => saveError = '"Monitored by" is required.');
                        return;
                      }
                      if (!draft.starRoutingComplete) {
                        setDlgState(() => saveError = 'Please set routing for all 5 star ratings.');
                        return;
                      }

                      setDlgState(() {
                        saving = true;
                        saveError = null;
                      });

                      try {
                        final svc = context.read<FirestoreService>();
                        if (draft.placeId != null && draft.placeId!.isNotEmpty) {
                          final exists = await svc.placeIdExists(draft.placeId!);
                          if (exists) {
                            setDlgState(() {
                              saveError = 'Place ID "${draft.placeId}" is already registered.';
                              saving = false;
                            });
                            return;
                          }
                        }

                        final newBranchId = await svc.addBranchToBusiness(
                          _business.id,
                          draft,
                          enrolledBy: enrolledBy,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop();
                        }
                        if (mounted) {
                          _refreshBusiness();
                          // Redirect directly to the dedicated Branch Payment Screen!
                          // ignore: use_build_context_synchronously
                          context.push('/enroll/payment/${_business.id}/$newBranchId');
                        }
                      } catch (e) {
                        setDlgState(() {
                          saveError = 'Error: $e';
                          saving = false;
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_forward, size: 16),
              label: Text(saving ? 'Saving…' : 'Continue to Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteBusinessDialog(BuildContext context) async {
    final svc = context.read<FirestoreService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: errorColor, size: 28),
            const SizedBox(width: 10),
            const Text('Delete Business?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete "${_business.brandName}"?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will cascade and permanently remove:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text('• All ${_branches.length} branch location(s) and review configs', style: const TextStyle(fontSize: 12)),
            const Text('• All generated Standee & Plain QR codes from Cloud Storage', style: TextStyle(fontSize: 12)),
            const Text('• Scan history and analytics logs', style: TextStyle(fontSize: 12)),
            if ((_business.ownerEmail ?? '').isNotEmpty)
              Text('• Owner Auth user account (${_business.ownerEmail}) so the email can be reused', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: errorColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                '⚠️ This action cannot be undone.',
                style: TextStyle(color: errorColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Deleting business & associated assets...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );

      try {
        final bizId = _business.id;
        await svc.deleteBusinessAdmin(bizId);
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ "${_business.brandName}" and all related data deleted.'),
            backgroundColor: Colors.green,
          ),
        );
        final isAdmin = context.read<AppAuthProvider>().isAdmin;
        if (isAdmin) {
          try {
            final adminProvider = context.read<AdminDashboardProvider>();
            adminProvider.removeBusinessLocally(bizId);
            adminProvider.loadAdminData();
          } catch (_) {}
          if (!mounted) return;
          context.go('/admin?tab=directory');
        } else {
          try {
            context.read<MyBusinessesProvider>().refresh();
          } catch (_) {}
          if (!mounted) return;
          context.go('/businesses');
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to delete business: $e'),
              backgroundColor: errorColor,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz    = _business;
    final scheme = Theme.of(context).colorScheme;
    final status = biz.subscriptionStatus;
    final isDue  = biz.isDueSoon(30);
    final displayStatus = isDue && status == AppConstants.statusActive
        ? 'due_soon'
        : status;
    final renewalStr = biz.renewalDate != null
        ? DateFormat('d MMM yyyy').format(biz.renewalDate!)
        : '—';
    final isAdmin = context.watch<AppAuthProvider>().isAdmin;

    final activeBranches = _branches.where((b) => b.isActive).toList();
    final pendingBranches = _branches.where((b) => b.isPendingPayment).toList();
    final graceBranches = _branches.where((b) => b.subscriptionStatus == AppConstants.statusGracePeriod).toList();

    final activeBranchCount = activeBranches.length;
    final pendingBranchCount = pendingBranches.length;
    final graceBranchCount = graceBranches.length;
    final totalBranchCount = _branches.length;

    final isPendingPayment = status == AppConstants.statusPendingPayment || (totalBranchCount > 0 && activeBranchCount == 0);
    final isFullyActive = totalBranchCount > 0 && activeBranchCount == totalBranchCount;
    final isPartialPending = activeBranchCount > 0 && pendingBranchCount > 0;

    return Scaffold(
      appBar: AppBar(
        title:       Text(biz.brandName),
        centerTitle: false,
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(isAdmin ? '/admin' : '/businesses');
            }
          },
        ),
        actions: [
          IconButton(
            onPressed: _refreshBusiness,
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh data',
          ),
          if (isAdmin)
            TextButton.icon(
              onPressed: () => _showDeleteBusinessDialog(context),
              icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
              label: Text('Delete Business', style: TextStyle(color: scheme.error)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/business/${biz.id}/edit', extra: biz);
          _refreshBusiness();
        },
        icon:  const Icon(Icons.edit_outlined),
        label: const Text('Edit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg - 4),
        children: [
          // ── Top Status Banner ──────────────────────────────────────────
          if (isPendingPayment) ...[
            _PendingPaymentPanel(
              business: biz,
              pendingBranches: pendingBranches,
              branchCount: totalBranchCount,
              onActivated: _refreshBusiness,
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (isPartialPending) ...[
            _PartialPendingPaymentPanel(
              business: biz,
              pendingBranches: pendingBranches,
              totalBranchCount: totalBranchCount,
              onActivated: _refreshBusiness,
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (isFullyActive) ...[
            _FullyActiveBanner(
              business: biz,
              branchCount: totalBranchCount,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Business Summary Card ─────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius:          28,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        biz.brandName.isNotEmpty
                            ? biz.brandName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize:   22,
                          fontWeight: FontWeight.bold,
                          color:      scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            biz.brandName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (biz.businessCode != null || biz.isTestAccount)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: biz.isTestAccount ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(
                                      color: biz.isTestAccount ? AppColors.warning : AppColors.primary.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'ID: ${biz.displayCode}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: biz.isTestAccount ? AppColors.warning : AppColors.primary,
                                    ),
                                  ),
                                ),
                              _StatusBadge(status: displayStatus),
                              if (isFullyActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.activeBg,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, size: 13, color: AppColors.activeFg),
                                      const SizedBox(width: 4),
                                      Text(
                                        'All $totalBranchCount ${totalBranchCount == 1 ? "Location" : "Locations"} Active',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.activeFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isPartialPending) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.activeBg,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 13, color: AppColors.activeFg),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$activeBranchCount of $totalBranchCount Active',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.activeFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.pendingBg,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(color: AppColors.pendingFg.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.hourglass_empty, size: 13, color: AppColors.pendingFg),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$pendingBranchCount of $totalBranchCount Pending Payment (₹${pendingBranchCount * 1999})',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.pendingFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (graceBranchCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.graceBg,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(color: AppColors.graceFg.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.graceFg),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$graceBranchCount ${totalBranchCount > 1 ? "of $totalBranchCount branches" : "branch"} in Grace Period',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.graceFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.sm + 4),
                _InfoRow(
                  label: 'Category',
                  value: biz.categoryType.isEmpty ? '—' : biz.categoryType,
                ),
                _InfoRow(label: 'Owner email',  value: biz.ownerEmail ?? '—'),
                _InfoRow(label: 'Renewal date', value: renewalStr),
                _InfoRow(
                  label: 'Payment status',
                  value: isFullyActive
                      ? 'Paid in Full — ₹${(biz.amountPaid ?? 0) > 0 ? biz.amountPaid : totalBranchCount * 1999} (${biz.paymentMode.isNotEmpty ? biz.paymentMode.toUpperCase() : "PAID"})'
                      : (isPartialPending
                          ? '₹${(biz.amountPaid ?? 0) > 0 ? biz.amountPaid : activeBranchCount * 1999} Paid ($activeBranchCount active) • ₹${pendingBranchCount * 1999} Pending ($pendingBranchCount pending)'
                          : (isPendingPayment
                              ? 'Awaiting Setup Fee (₹${totalBranchCount > 0 ? totalBranchCount * 1999 : 1999})'
                              : '—')),
                ),
                _InfoRow(
                  label: 'Enrolled by',
                  value: _enrolledByName ?? (biz.enrolledBy == 'admin' ? 'Admin' : (biz.enrolledBy.isEmpty ? '—' : 'Loading…')),
                ),
                _InfoRow(label: 'Business ID',  value: biz.id, mono: true),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg - 4),

          // ── Branches Header with Add Branch Button ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Branches (${_branches.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showAddBranchDialog(context),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: const Text('Add Branch'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),

          if (_loading)
            const Center(
              child: AppAnimatedLoader.card(
                message: 'Loading branches…',
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Error loading branches: $_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_branches.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No branches found.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ..._branches.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _BranchCard(
                  branch:              b,
                  businessId:          biz.id,
                  ownerPhone:          biz.ownerPhone,
                  showStandeeControls: !isPendingPayment && b.isActive,
                  totalBranchCount:    _branches.length,
                  onBranchUpdated:     _refreshBusiness,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.xxl - 8),
        ],
      ),
    );
  }
}

// ── Top Status Banners ────────────────────────────────────────────────────────

class _FullyActiveBanner extends StatelessWidget {
  final BusinessModel business;
  final int branchCount;

  const _FullyActiveBanner({
    required this.business,
    required this.branchCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.activeBg,
        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
        border: Border.all(
          color: AppColors.activeFg.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.activeFg.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified, color: AppColors.activeFg, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Business ($branchCount ${branchCount == 1 ? "Location" : "Locations"})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.activeFg,
                    fontSize: 14,
                  ),
                ),
                Text(
                  branchCount == 1
                      ? 'The branch location is active with live review routing and verified credentials.'
                      : 'All $branchCount branch locations are active with live review routing and verified credentials.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.activeFg.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartialPendingPaymentPanel extends StatefulWidget {
  final BusinessModel business;
  final List<BranchModel> pendingBranches;
  final int totalBranchCount;
  final VoidCallback? onActivated;

  const _PartialPendingPaymentPanel({
    required this.business,
    required this.pendingBranches,
    required this.totalBranchCount,
    this.onActivated,
  });

  @override
  State<_PartialPendingPaymentPanel> createState() => _PartialPendingPaymentPanelState();
}

class _PartialPendingPaymentPanelState extends State<_PartialPendingPaymentPanel> {
  bool _cashActivating = false;
  bool _sending = false;
  String? _shortUrl;
  String? _error;

  int get pendingFee => widget.pendingBranches.length * 1999;

  Future<void> _adminCashActivateAllRemaining() async {
    setState(() {
      _cashActivating = true;
      _error = null;
    });
    try {
      final auth = context.read<AppAuthProvider>();
      if (!auth.isAdmin) {
        throw Exception('Only admins can activate businesses with cash.');
      }
      final svc = context.read<FirestoreService>();
      await svc.confirmCashAndActivate(
        businessId: widget.business.id,
        adminUid: auth.uid ?? 'admin',
      );
      if (mounted) {
        setState(() => _cashActivating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All ${widget.pendingBranches.length} remaining branches activated via cash!'),
            backgroundColor: AppColors.activeFg,
          ),
        );
        widget.onActivated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cashActivating = false;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending  = true;
      _error    = null;
      _shortUrl = null;
    });
    try {
      final svc    = context.read<FirestoreService>();
      final result = await svc.resendPaymentLink(widget.business.id);
      final url    = result['shortUrl'] as String?;
      if (mounted) {
        setState(() {
          _shortUrl = url;
          _sending  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _sending = false;
        });
      }
    }
  }

  void _copyLink() {
    if (_shortUrl == null) return;
    Clipboard.setData(ClipboardData(text: _shortUrl!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:  Text('Payment link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openLink() {
    if (_shortUrl == null) return;
    html.window.open(_shortUrl!, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final isAdmin = auth.isAdmin;
    final pendingCount = widget.pendingBranches.length;
    final activeCount = widget.totalBranchCount - pendingCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
        border: Border.all(
          color: AppColors.pendingFg.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.pendingFg, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Partial Payment Pending ($pendingCount of ${widget.totalBranchCount} Locations — ₹$pendingFee)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.pendingFg,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$activeCount of ${widget.totalBranchCount} branch locations are currently active. $pendingCount branch location(s) require setup fee payment (₹1,999 each) to activate review routing and QR code generation.',
            style: const TextStyle(fontSize: 13, color: AppColors.pendingFg),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (isAdmin)
                FilledButton.icon(
                  onPressed: (_sending || _cashActivating) ? null : _adminCashActivateAllRemaining,
                  icon: _cashActivating
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onTertiary,
                          ),
                        )
                      : const Icon(Icons.local_atm_outlined, size: 16),
                  label: Text(_cashActivating
                      ? 'Activating…'
                      : 'Cash: Activate $pendingCount Remaining Branch${pendingCount > 1 ? "es" : ""} (₹$pendingFee)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                  ),
                ),
              ElevatedButton.icon(
                onPressed: (_sending || _cashActivating) ? null : _resend,
                icon: _sending
                    ? SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 16),
                label: Text(_sending ? 'Sending…' : 'Resend Payment Link'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/enroll/payment/${widget.business.id}'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Payment Page'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Error: $_error',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          if (_shortUrl != null) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                border: Border.all(color: AppColors.pendingFg.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 14, color: AppColors.activeFg),
                      const SizedBox(width: 6),
                      Text(
                        'Payment link generated for remaining branches',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.activeFg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(
                    _shortUrl!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _copyLink,
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openLink,
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Change 3: Pending Payment Panel ──────────────────────────────────────────

class _PendingPaymentPanel extends StatefulWidget {
  final BusinessModel business;
  final List<BranchModel>? pendingBranches;
  final int branchCount;
  final VoidCallback? onActivated;
  const _PendingPaymentPanel({
    required this.business,
    this.pendingBranches,
    this.branchCount = 1,
    this.onActivated,
  });

  @override
  State<_PendingPaymentPanel> createState() => _PendingPaymentPanelState();
}

class _PendingPaymentPanelState extends State<_PendingPaymentPanel> {
  bool    _sending = false;
  bool    _cashActivating = false;
  String? _shortUrl;
  String? _error;

  int get effectiveBranchCount => (widget.pendingBranches != null && widget.pendingBranches!.isNotEmpty)
      ? widget.pendingBranches!.length
      : (widget.branchCount > 0 ? widget.branchCount : 1);

  int get totalFee => effectiveBranchCount * 1999;

  Future<void> _adminCashActivate() async {
    setState(() {
      _cashActivating = true;
      _error = null;
    });
    try {
      final auth = context.read<AppAuthProvider>();
      if (!auth.isAdmin) {
        throw Exception('Only admins can activate businesses with cash.');
      }
      final svc = context.read<FirestoreService>();
      await svc.confirmCashAndActivate(
        businessId: widget.business.id,
        adminUid: auth.uid ?? 'admin',
      );
      if (mounted) {
        setState(() => _cashActivating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${widget.business.brandName}" activated via cash payment!'),
            backgroundColor: AppColors.activeFg,
          ),
        );
        widget.onActivated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cashActivating = false;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending  = true;
      _error    = null;
      _shortUrl = null;
    });
    try {
      final svc    = context.read<FirestoreService>();
      final result = await svc.resendPaymentLink(widget.business.id);
      final url    = result['shortUrl'] as String?;
      if (mounted) {
        setState(() {
          _shortUrl = url;
          _sending  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _sending = false;
        });
      }
    }
  }

  void _copyLink() {
    if (_shortUrl == null) return;
    Clipboard.setData(ClipboardData(text: _shortUrl!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:  Text('Payment link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openLink() {
    if (_shortUrl == null) return;
    html.window.open(_shortUrl!, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AppAuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final isAdmin = auth.isAdmin;

    final bannerDesc = isAdmin
        ? (effectiveBranchCount > 1
            ? 'This business has $effectiveBranchCount enrolled locations awaiting total setup fee of ₹$totalFee (₹1,999 × $effectiveBranchCount). As an admin, you can activate all branches with cash or send an online payment link.'
            : 'This business is enrolled but the setup fee (₹1,999) has not yet been paid. As an admin, you can activate it directly with cash or send an online payment link.')
        : (effectiveBranchCount > 1
            ? 'This business has $effectiveBranchCount enrolled locations awaiting setup payment of ₹$totalFee. Use the button below to generate a fresh payment link.'
            : 'This business is enrolled but the owner has not yet paid the ₹1,999 setup fee. Use the button below to generate a fresh payment link.');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
        border:       Border.all(
          color: AppColors.pendingFg.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.payment_outlined, color: AppColors.pendingFg, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  effectiveBranchCount > 1
                      ? 'Awaiting Payment ($effectiveBranchCount Locations — ₹$totalFee)'
                      : 'Awaiting Payment (₹1,999)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:      AppColors.pendingFg,
                    fontSize:   15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            bannerDesc,
            style: TextStyle(fontSize: 13, color: AppColors.pendingFg),
          ),
          const SizedBox(height: AppSpacing.sm + 4),

          // Action buttons
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              // Admin-only Cash Activate
              if (isAdmin)
                FilledButton.icon(
                  onPressed: (_sending || _cashActivating) ? null : _adminCashActivate,
                  icon: _cashActivating
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onTertiary,
                          ),
                        )
                      : const Icon(Icons.local_atm_outlined, size: 16),
                  label: Text(_cashActivating
                      ? 'Activating…'
                      : (effectiveBranchCount > 1
                          ? 'Cash: Activate $effectiveBranchCount Branches (₹$totalFee)'
                          : 'Cash Payment — Activate Now (₹1,999)')),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                  ),
                ),

              // Online: Resend payment link
              ElevatedButton.icon(
                onPressed: (_sending || _cashActivating) ? null : _resend,
                icon: _sending
                    ? SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 16),
                label: Text(_sending ? 'Sending…' : 'Resend payment link'),
              ),

              // Open Payment Page
              OutlinedButton.icon(
                onPressed: () => context.push('/enroll/payment/${widget.business.id}'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Payment Page'),
              ),
            ],
          ),

          // Error
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Error: $_error',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],

          // Success: show link for WhatsApp / copy
          if (_shortUrl != null) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                border:       Border.all(color: AppColors.pendingFg.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.activeFg),
                      const SizedBox(width: 6),
                      Text(
                        'Payment link generated and emailed to owner',
                        style: TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                          color:      AppColors.activeFg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(
                    _shortUrl!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _copyLink,
                        icon:  const Icon(Icons.copy, size: 14),
                        label: const Text('Copy'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openLink,
                        icon:  const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Branch Card ───────────────────────────────────────────────────────────────

class _BranchCard extends StatefulWidget {
  final BranchModel branch;
  final String      businessId;
  final String?     ownerPhone;
  final bool        showStandeeControls;
  final int         totalBranchCount;
  final VoidCallback? onBranchUpdated;

  const _BranchCard({
    required this.branch,
    required this.businessId,
    this.ownerPhone,
    this.showStandeeControls = true,
    required this.totalBranchCount,
    this.onBranchUpdated,
  });

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  late String _standeeStatus;
  bool        _standeeUpdating = false;
  bool        _deleting = false;

  // QR download state (Change 1)
  bool    _qrLoading = false;
  String? _qrError;

  @override
  void initState() {
    super.initState();
    _standeeStatus = widget.branch.standeeStatus;
  }

  Future<void> _onStandeeChanged(String? newStatus) async {
    if (newStatus == null || newStatus == _standeeStatus) return;
    setState(() {
      _standeeStatus   = newStatus;
      _standeeUpdating = true;
    });
    try {
      await context.read<FirestoreService>().updateStandeeStatus(
            widget.businessId, widget.branch.id, newStatus);
    } catch (e) {
      if (mounted) {
        setState(() => _standeeStatus = widget.branch.standeeStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update standee status: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _standeeUpdating = false);
    }
  }

  Future<void> _downloadQr() async {
    final path = widget.branch.plainQrStoragePath;
    if (path == null) return;
    setState(() {
      _qrLoading = true;
      _qrError   = null;
    });
    try {
      final url = await context.read<FirestoreService>().getPlainQrDownloadUrl(path);
      if (mounted) {
        setState(() => _qrLoading = false);
        // ignore: avoid_web_libraries_in_flutter
        html.window.open(url, '_blank');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _qrError   = 'Download failed: $e';
          _qrLoading = false;
        });
      }
    }
  }

  Future<void> _showRevertBranchDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final svc = context.read<FirestoreService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revert Branch "${widget.branch.branchName}"?'),
        content: const Text(
          'This will revert this branch back to "Payment Pending". '
          'Any pending employee commission record for this branch will also be cancelled.\n\n'
          'Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Revert to Pending'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await svc.adminRevertBranchActivation(
          businessId: widget.businessId,
          branchId: widget.branch.id,
        );
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('✅ Branch "${widget.branch.branchName}" reverted to Payment Pending.'),
              backgroundColor: Colors.orange,
            ),
          );
          widget.onBranchUpdated?.call();
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to revert branch: $e'),
              backgroundColor: errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteBranchDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final svc = context.read<FirestoreService>();
    final branchName = widget.branch.branchName;

    // Safety guard: Cannot delete the only remaining branch
    if (widget.totalBranchCount <= 1) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('Cannot Delete Only Branch'),
            ],
          ),
          content: const Text(
            'This is the only branch for this business. Every business must have at least 1 branch.\n\n'
            'If you wish to remove this entire business, use the "Delete Business" option at the top of the page.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final isActiveOrGrace = widget.branch.isActive ||
        widget.branch.subscriptionStatus == AppConstants.statusGracePeriod;

    if (isActiveOrGrace) {
      // ── Step 1: Warning Confirmation for Active / Grace Period Branch ────
      final step1Confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: errorColor),
              const SizedBox(width: 8),
              Expanded(child: Text('Delete Active Branch "$branchName"?')),
            ],
          ),
          content: const Text(
            '⚠️ WARNING: This branch is currently ACTIVE (or in grace period).\n\n'
            'Deleting this branch will permanently:\n'
            '• Remove this location from the business\n'
            '• Invalidate and delete its QR code and review links\n'
            '• Permanently purge all customer scan logs and analytics for this branch\n\n'
            'Are you sure you want to proceed to the final confirmation?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              child: const Text('Proceed to Final Confirmation'),
            ),
          ],
        ),
      );

      if (step1Confirmed != true || !mounted) return;

      // ── Step 2: Final Critical Confirmation ─────────────────────────────
      final step2Confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.dangerous, color: errorColor),
              const SizedBox(width: 8),
              Expanded(child: Text('Final Confirmation: Delete "$branchName"?')),
            ],
          ),
          content: const Text(
            'This action is IRREVERSIBLE.\n\n'
            'All data, QR assets, and scan history for this location will be destroyed immediately.\n\n'
            'Click below to permanently delete this branch.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_forever, size: 16),
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              label: const Text('Permanently Delete Branch'),
            ),
          ],
        ),
      );

      if (step2Confirmed != true || !mounted) return;
    } else {
      // ── Single Confirmation for Pending Payment / Draft Branch ───────────
      final singleConfirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete Branch "$branchName"?'),
          content: const Text(
            'This branch is currently pending payment / first-time enrollment.\n\n'
            'Are you sure you want to remove this location from the business?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              child: const Text('Delete Branch'),
            ),
          ],
        ),
      );

      if (singleConfirmed != true || !mounted) return;
    }

    // ── Execute Deletion ───────────────────────────────────────────────────
    try {
      setState(() => _deleting = true);
      await svc.deleteBranchAdmin(widget.businessId, widget.branch.id);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ Branch "$branchName" deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onBranchUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to delete branch: $e'),
            backgroundColor: errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.branch;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch name header
          Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size:  18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  branch.branchName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (branch.isPendingPayment)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.pendingBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.pendingFg.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty, size: 12, color: AppColors.pendingFg),
                      SizedBox(width: 4),
                      Text(
                        'Payment Pending (₹1,999)',
                        style: TextStyle(
                          color: AppColors.pendingFg,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.activeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 12, color: AppColors.activeFg),
                      SizedBox(width: 4),
                      Text(
                        'Active',
                        style: TextStyle(
                          color: AppColors.activeFg,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (context.watch<AppAuthProvider>().isAdmin && branch.isActive) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _deleting ? null : () => _showRevertBranchDialog(context),
                  icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
                  tooltip: 'Revert branch activation to Payment Pending',
                ),
              ],
              if (context.watch<AppAuthProvider>().isAdmin) ...[
                const SizedBox(width: 4),
                if (_deleting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    onPressed: () => _showDeleteBranchDialog(context),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: 'Delete branch',
                  ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm + 4),

          // ── Branch Payment Panel (when pending payment) ───────────────
          if (branch.isPendingPayment)
            _BranchPaymentPanel(
              branch: branch,
              businessId: widget.businessId,
              onActivated: widget.onBranchUpdated ?? () {},
            ),

          _InfoRow(label: 'Address',  value: branch.address),
          _InfoRow(label: 'WhatsApp', value: branch.whatsappNumber),
          if (branch.whatsappMonitoredBy.isNotEmpty)
            _InfoRow(
              label: 'WA monitor',
              value: branch.whatsappMonitoredBy,
            ),
          if (branch.placeId != null && branch.placeId!.isNotEmpty)
            _InfoRow(label: 'Place ID',    value: branch.placeId!, mono: true),
          if (branch.googleReviewLink != null &&
              branch.googleReviewLink!.isNotEmpty)
            _InfoRow(label: 'Review link', value: branch.googleReviewLink!),
          _InfoRow(label: 'Branch ID', value: branch.id, mono: true),

          const SizedBox(height: AppSpacing.md),

          // ── Change 1: Plain printable QR download (active branches) ───
          _PlainQrRow(
            plainQrStoragePath: branch.plainQrStoragePath,
            qrLoading:          _qrLoading,
            qrError:            _qrError,
            onDownload:         _downloadQr,
          ),

          const SizedBox(height: AppSpacing.sm + 4),

          // ── Change 2: Standee fulfillment status ──────────────────────
          if (widget.showStandeeControls)
            _StandeeStatusRow(
              currentStatus: _standeeStatus,
              updating:      _standeeUpdating,
              updatedAt:     branch.standeeStatusUpdatedAt,
              onChanged:     _onStandeeChanged,
            ),

          if (widget.showStandeeControls)
            const SizedBox(height: AppSpacing.md),

          // Star routing
          Text(
            'Star Routing',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StarRoutingTable(config: branch.starRoutingConfig),

          // ── Share Review QR & Link ────────────────────────────────────
          ShareBusinessQr(
            branch: branch,
            ownerPhone: widget.ownerPhone,
          ),
        ],
      ),
    );
  }
}

// ── Branch Payment Panel ─────────────────────────────────────────────────────

class _BranchPaymentPanel extends StatefulWidget {
  final BranchModel branch;
  final String businessId;
  final VoidCallback onActivated;

  const _BranchPaymentPanel({
    required this.branch,
    required this.businessId,
    required this.onActivated,
  });

  @override
  State<_BranchPaymentPanel> createState() => _BranchPaymentPanelState();
}

class _BranchPaymentPanelState extends State<_BranchPaymentPanel> {
  bool _activatingCash = false;
  bool _sendingLink = false;
  bool _payingOnline = false;
  String? _shortUrl;
  String? _error;

  Future<void> _adminCashActivate() async {
    setState(() {
      _activatingCash = true;
      _error = null;
    });
    try {
      final svc = context.read<FirestoreService>();
      await svc.adminCashActivateBranch(
        businessId: widget.businessId,
        branchId: widget.branch.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Branch activated via cash payment! QR code generation initiated.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onActivated();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Cash activation failed: $e');
    } finally {
      if (mounted) setState(() => _activatingCash = false);
    }
  }

  Future<void> _resendPaymentLink() async {
    setState(() {
      _sendingLink = true;
      _error = null;
    });
    try {
      final svc = context.read<FirestoreService>();
      final res = await svc.resendBranchPaymentLink(
        businessId: widget.businessId,
        branchId: widget.branch.id,
      );
      final url = res['shortUrl'] as String?;
      if (mounted) {
        setState(() => _shortUrl = url);
        if (url != null) {
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Payment link created and copied to clipboard!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed generating link: $e');
    } finally {
      if (mounted) setState(() => _sendingLink = false);
    }
  }

  Future<void> _payOnlineRazorpay() async {
    setState(() {
      _payingOnline = true;
      _error = null;
    });

    if (!js.context.hasProperty('Razorpay')) {
      setState(() {
        _payingOnline = false;
        _error = 'Razorpay script not loaded.';
      });
      return;
    }

    try {
      final empId = context.read<AppAuthProvider>().uid ?? '';
      final handlerSuccess = js.allowInterop((dynamic response) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payment received! Branch activation in progress.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onActivated();
      });

      final handlerDismiss = js.allowInterop(() {
        if (!mounted) return;
        setState(() {
          _payingOnline = false;
          _error = 'Payment cancelled.';
        });
      });

      final options = js.JsObject.jsify({
        'key': AppConfig.razorpayKeyId,
        'amount': 199900,
        'currency': 'INR',
        'name': 'Appnexa Technologies',
        'description': 'Branch setup fee — ${widget.branch.branchName}',
        'notes': {
          'business_id': widget.businessId,
          'businessId': widget.businessId,
          'branch_id': widget.branch.id,
          'branchId': widget.branch.id,
          'type': 'branch_setup_fee',
          'enrolled_by': empId,
        },
        'handler': handlerSuccess,
        'modal': {'ondismiss': handlerDismiss},
        'theme': {'color': '#3B4DB8'},
      });

      final rzp = js.JsObject(js.context['Razorpay'] as js.JsFunction, [options]);
      rzp.callMethod('open');
    } catch (e) {
      if (mounted) {
        setState(() {
          _payingOnline = false;
          _error = 'Failed opening Razorpay: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppAuthProvider>().isAdmin;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.pendingFg.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.pendingFg, size: 18),
              const SizedBox(width: 8),
              Text(
                'Branch Payment Required (₹1,999 setup fee)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.pendingFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'This branch is inactive. Review page, QR codes, and acrylic standees will activate once payment of ₹1,999 is completed.',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
          if (_shortUrl != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Link: $_shortUrl',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isAdmin)
                FilledButton.icon(
                  onPressed: (_activatingCash || _payingOnline || _sendingLink)
                      ? null
                      : _adminCashActivate,
                  icon: _activatingCash
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Cash: Activate (₹1,999)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[700],
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: (_activatingCash || _payingOnline || _sendingLink)
                    ? null
                    : _payOnlineRazorpay,
                icon: _payingOnline
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.credit_card, size: 16),
                label: const Text('Pay Online (₹1,999)'),
              ),
              OutlinedButton.icon(
                onPressed: (_activatingCash || _payingOnline || _sendingLink)
                    ? null
                    : _resendPaymentLink,
                icon: _sendingLink
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 16),
                label: const Text('Send Payment Link'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/enroll/payment/${widget.businessId}/${widget.branch.id}'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Payment Page'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Change 1: Plain QR download row ──────────────────────────────────────────

class _PlainQrRow extends StatelessWidget {
  final String?      plainQrStoragePath;
  final bool         qrLoading;
  final String?      qrError;
  final VoidCallback onDownload;

  const _PlainQrRow({
    required this.plainQrStoragePath,
    required this.qrLoading,
    required this.qrError,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.qr_code_2_outlined, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Printable QR',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              if (qrError != null)
                Text(
                  qrError!,
                  style: TextStyle(color: scheme.error, fontSize: 11),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (plainQrStoragePath != null)
          ElevatedButton.icon(
            onPressed: qrLoading ? null : onDownload,
            icon: qrLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(qrLoading ? 'Loading…' : 'Download'),
            style: ElevatedButton.styleFrom(
              padding:   const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          )
        else
          Tooltip(
            message: 'QR will be ready after payment is confirmed',
            child: ElevatedButton.icon(
              onPressed: null,
              icon:  const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                padding:   const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Change 2: Standee status row ──────────────────────────────────────────────

class _StandeeStatusRow extends StatelessWidget {
  final String    currentStatus;
  final bool      updating;
  final DateTime? updatedAt;
  final void Function(String?) onChanged;

  const _StandeeStatusRow({
    required this.currentStatus,
    required this.updating,
    required this.updatedAt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme      = Theme.of(context).colorScheme;
    final safeStatus  = AppConstants.standeeStatuses.contains(currentStatus)
        ? currentStatus
        : AppConstants.standeeOrdered;
    final label       = AppConstants.standeeStatusLabels[safeStatus] ?? safeStatus;
    final statusColor = AppTheme.standeeStatusColor(safeStatus);
    final statusFg    = AppTheme.standeeStatusForeground(safeStatus);
    final updatedStr  = updatedAt != null
        ? DateFormat('d MMM yyyy').format(updatedAt!)
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              const Text('Acrylic Standee',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              // Current status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        statusColor,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border:       Border.all(
                    color: statusFg.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize:   10,
                    fontWeight: FontWeight.w600,
                    color:      statusFg,
                  ),
                ),
              ),
              if (updating)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            value:      safeStatus,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
              label: const Text('Update status'),
            ),
            items: AppConstants.standeeStatuses
                .map((s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(AppConstants.standeeStatusLabels[s] ?? s),
                    ))
                .toList(),
            onChanged: updating ? null : onChanged,
          ),
          if (updatedStr != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Last updated: $updatedStr',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Star Routing Table ────────────────────────────────────────────────────────

class _StarRoutingTable extends StatelessWidget {
  final Map<String, String> config;
  const _StarRoutingTable({required this.config});

  static const _labels = {
    'thankyou': 'Thank you only',
    'whatsapp': 'WhatsApp',
    'google':   'Google review',
  };

  static const _icons = {
    'thankyou': Icons.favorite_border,
    'whatsapp': Icons.chat_bubble_outline,
    'google':   Icons.star_outline,
  };

  // Semantic, purposeful routing colors — not random
  static const _colors = {
    'thankyou': AppColors.deletedFg,    // grey — neutral action
    'whatsapp': Color(0xFF25D366),      // WhatsApp brand green (unchanged)
    'google':   AppColors.star,         // star amber — brand token
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (i) {
        final star  = '${i + 1}';
        final route = config[star] ?? '—';
        final label = _labels[route] ?? route;
        final icon  = _icons[route]  ?? Icons.help_outline;
        final color = _colors[route] ?? Theme.of(context).colorScheme.onSurfaceVariant;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ...List.generate(
                i + 1,
                (_) => const Icon(Icons.star, size: 14, color: AppColors.star),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize:   13,
                  color:      color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color:        Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color:     AppColors.primary.withValues(alpha: 0.05),
              blurRadius: 12,
              offset:    const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   mono;
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(
                  fontSize:   12,
                  color:      Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize:   13,
                  fontFamily: mono ? 'monospace' : null,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final labels = {
      'pending_payment': 'Awaiting Payment',
      'active':          'Active',
      'due_soon':        'Renewal Due',
      'grace_period':    'Grace Period',
      'suspended':       'Suspended',
      'deleted':         'Deleted',
    };
    final label = labels[status] ?? status;
    final bg    = AppTheme.statusColor(status);
    final fg    = AppTheme.statusForeground(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border:       Border.all(color: fg.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   11,
          fontWeight: FontWeight.w700,
          color:      fg,
        ),
      ),
    );
  }
}
