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
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/share_business_qr.dart';
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
    _loadBranches();
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
        _loadBranches();
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
                          _loadBranches();
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

  Future<void> _showRevertBusinessDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final svc = context.read<FirestoreService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert Business Activation?'),
        content: const Text(
          'This will revert this business and ALL its branches back to "Payment Pending". '
          'Any pending employee commission records for this business will also be cancelled.\n\n'
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
        await svc.adminRevertBusinessActivation(businessId: _business.id);
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('✅ Business activation reverted to Payment Pending.'),
              backgroundColor: Colors.orange,
            ),
          );
          _refreshBusiness();
          _loadBranches();
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to revert business: $e'),
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
    final isPendingPayment = status == AppConstants.statusPendingPayment;
    final isAdmin = context.watch<AppAuthProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title:       Text(biz.brandName),
        centerTitle: false,
        actions: [
          if (isAdmin && !isPendingPayment)
            TextButton.icon(
              onPressed: () => _showRevertBusinessDialog(context),
              icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
              label: const Text('Revert Activation', style: TextStyle(color: Colors.orange)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/business/${biz.id}/edit', extra: biz),
        icon:  const Icon(Icons.edit_outlined),
        label: const Text('Edit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg - 4),
        children: [
          // ── Change 3: Pending payment banner ─────────────────────────
          if (isPendingPayment)
            _PendingPaymentPanel(
              business: biz,
              branchCount: _branches.length,
              onActivated: _refreshBusiness,
            ),

          if (isPendingPayment) const SizedBox(height: AppSpacing.md),

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
                          _StatusBadge(status: displayStatus),
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
                  label: 'Enrolled by',
                  value: _enrolledByName ?? (biz.enrolledBy == 'admin' ? 'Admin' : (biz.enrolledBy.isEmpty ? '—' : 'Loading…')),
                ),
                _InfoRow(label: 'Business ID',  value: biz.id, mono: true),
                if (biz.isReassigned)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: _ReassignedBanner(),
                  ),
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
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
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
                  onBranchUpdated:     _loadBranches,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.xxl - 8),
        ],
      ),
    );
  }
}

// ── Change 3: Pending Payment Panel ──────────────────────────────────────────

class _PendingPaymentPanel extends StatefulWidget {
  final BusinessModel business;
  final int branchCount;
  final VoidCallback? onActivated;
  const _PendingPaymentPanel({
    required this.business,
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

  int get totalFee => (widget.branchCount > 0 ? widget.branchCount : 1) * 1999;

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
      await svc.adminCashActivate(
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
        ? (widget.branchCount > 1
            ? 'This business has ${widget.branchCount} enrolled locations awaiting total setup fee of ₹$totalFee (₹1,999 × ${widget.branchCount}). As an admin, you can activate all branches with cash or send an online payment link.'
            : 'This business is enrolled but the setup fee (₹1,999) has not yet been paid. As an admin, you can activate it directly with cash or send an online payment link.')
        : (widget.branchCount > 1
            ? 'This business has ${widget.branchCount} enrolled locations awaiting setup payment of ₹$totalFee. Use the button below to generate a fresh payment link.'
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
                  widget.branchCount > 1
                      ? 'Awaiting Payment (${widget.branchCount} Locations — ₹$totalFee)'
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
                      : (widget.branchCount > 1
                          ? 'Cash: Activate ${widget.branchCount} Branches (₹$totalFee)'
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
  final VoidCallback? onBranchUpdated;

  const _BranchCard({
    required this.branch,
    required this.businessId,
    this.ownerPhone,
    this.showStandeeControls = true,
    this.onBranchUpdated,
  });

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  late String _standeeStatus;
  bool        _standeeUpdating = false;

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
                  onPressed: () => _showRevertBranchDialog(context),
                  icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
                  tooltip: 'Revert branch activation to Payment Pending',
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
        'key': 'rzp_test_PLACEHOLDER',
        'amount': 199900,
        'currency': 'INR',
        'name': 'Review System',
        'description': 'Branch setup fee — ${widget.branch.branchName}',
        'notes': {
          'business_id': widget.businessId,
          'branch_id': widget.branch.id,
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
    final scheme     = Theme.of(context).colorScheme;
    final label      = AppConstants.standeeStatusLabels[currentStatus] ?? currentStatus;
    final statusColor = AppTheme.standeeStatusColor(currentStatus);
    final statusFg    = AppTheme.standeeStatusForeground(currentStatus);
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
            value:      currentStatus,
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

class _ReassignedBanner extends StatelessWidget {
  const _ReassignedBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:        AppColors.dueSoonBg,
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          border:       Border.all(
            color: AppColors.dueSoonFg.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.dueSoonFg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This business has been reassigned to admin management.',
                style: TextStyle(fontSize: 12, color: AppColors.dueSoonFg),
              ),
            ),
          ],
        ),
      );
}
