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
import 'package:cloud_functions/cloud_functions.dart';
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
import '../../models/employee_profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/places_service.dart';
import '../../widgets/app_animated_loader.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_brand_title.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_fulfillment_stepper.dart';
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
        builder: (ctx, setDlgState) => AppModalDialog(
          icon: Icons.add_business_rounded,
          iconColor: AppColors.primary,
          title: 'Add New Branch',
          subtitle: 'Configure location, review routing, and details for "${_business.brandName}".',
          maxWidth: 580,
          content: Column(
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
          actions: [
            OutlinedButton(
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

  Future<void> _showChangeEnrollerDialog() async {
    final svc = context.read<FirestoreService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    List<EmployeeProfileModel> employees = [];
    try {
      employees = await svc.getEmployeesList();
    } catch (_) {}

    if (!mounted) return;

    String selectedEmployeeUid = _business.enrolledBy.isEmpty ? 'admin' : _business.enrolledBy;
    String reason = '';

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dCtx, setDialogState) {
            final isCurrent = selectedEmployeeUid == (_business.enrolledBy.isEmpty ? 'admin' : _business.enrolledBy);

            return AppModalDialog(
              icon: Icons.swap_horiz_rounded,
              iconColor: AppColors.primary,
              title: 'Change Enrolled Employee',
              subtitle: 'Reassign which employee is credited for enrolling "${_business.brandName}".',
              maxWidth: 520,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 20, color: Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Currently Enrolled By', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                _enrolledByName ?? (_business.enrolledBy == 'admin' ? 'Admin' : _business.enrolledBy),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedEmployeeUid,
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 8,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    decoration: const InputDecoration(
                      labelText: 'Select New Enrolled Employee *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'admin',
                        child: Text('Admin (Direct Enrollment / No Commission)'),
                      ),
                      ...employees
                          .where((emp) => !emp.isAdmin)
                          .map((emp) => DropdownMenuItem(
                            value: emp.uid,
                            child: Text(
                              '${emp.name} (${emp.email})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedEmployeeUid = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Reason for Reassignment (Optional)',
                      hintText: 'e.g. Territory reallocation or correction',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (val) => reason = val.trim(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Impact of change:\n'
                            '• Moves business to selected employee’s panel.\n'
                            '• Removes it from previous employee’s view.\n'
                            '• Transferred pending commissions & enrollment counters.',
                            style: TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isCurrent
                      ? null
                      : () {
                          Navigator.of(ctx).pop(true);
                        },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirm Reassignment'),
                ),
              ],
            );
          },
        );
      },
    );

    if (success == true && mounted) {
      try {
        setState(() => _loading = true);
        await svc.reassignBusinessEnroller(
          businessId: _business.id,
          newEmployeeId: selectedEmployeeUid,
          reason: reason.isNotEmpty ? reason : 'Admin reassignment',
        );

        final newName = await svc.getEmployeeName(selectedEmployeeUid);

        if (mounted) {
          setState(() {
            _business = _business.copyWith(
              enrolledBy: selectedEmployeeUid,
              currentlyManagedBy: selectedEmployeeUid,
            );
            _enrolledByName = newName;
            _loading = false;
          });

          try {
            final adminProvider = context.read<AdminDashboardProvider>();
            await adminProvider.fetchAllBusinesses();
            await adminProvider.fetchEmployees();
          } catch (_) {}

          if (!mounted) return;

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Enrolled employee changed to "$newName" successfully.'),
              backgroundColor: AppColors.activeFg,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to reassign enrolled employee: $e'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteBusinessDialog() async {
    final svc = context.read<FirestoreService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppModalDialog(
        icon: Icons.delete_forever_rounded,
        iconColor: errorColor,
        title: 'Delete Business?',
        subtitle: 'Cascade deletion of brand and branches',
        maxWidth: 480,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete "${_business.brandName}"?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will cascade and permanently remove:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text('• All ${_branches.length} branch location(s) and review configs', style: const TextStyle(fontSize: 12)),
            const Text('• All generated Standee & Plain QR codes from Cloud Storage', style: TextStyle(fontSize: 12)),
            const Text('• Scan history and analytics logs', style: TextStyle(fontSize: 12)),
            if ((_business.ownerEmail ?? '').isNotEmpty)
              Text('• Owner Auth user account (${_business.ownerEmail}) so the email can be reused', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
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
          OutlinedButton(
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

  void _showConvertToLiveDialog(
    BuildContext context,
    BusinessModel biz, {
    required bool isCurrentlyActive,
    required int activeBranchCount,
  }) {
    String selectedMode = 'cash'; // default
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
                          final provider = context.read<AdminDashboardProvider>();
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
                            await _refreshBusiness();
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
    final totalActiveBranchAmount = _branches.isNotEmpty
        ? activeBranches.fold<double>(
            0.0,
            (acc, b) => acc + (b.amountPaid ?? b.setupFeePaid ?? 1999.0),
          )
        : (activeBranchCount > 0 ? activeBranchCount * 1999.0 : (biz.amountPaid ?? 1999.0));

    return Scaffold(
      appBar: AppBar(
        title:       AppBrandTitle(subtitle: biz.brandName),
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
          if (isAdmin && biz.isTestAccount)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ElevatedButton.icon(
                onPressed: () => _showConvertToLiveDialog(
                  context,
                  biz,
                  isCurrentlyActive: isFullyActive || isPartialPending,
                  activeBranchCount: activeBranchCount,
                ),
                icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                label: const Text('Convert to Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _refreshBusiness,
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh data',
          ),
          if (isAdmin)
            TextButton.icon(
              onPressed: _showDeleteBusinessDialog,
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
          // ── Top Test Business Banner ───────────────────────────────────
          if (biz.isTestAccount) ...[
            _TestBusinessBanner(
              business: biz,
              isAdmin: isAdmin,
              isCurrentlyActive: isFullyActive || isPartialPending,
              activeBranchCount: activeBranchCount,
              onConvertTap: () => _showConvertToLiveDialog(
                context,
                biz,
                isCurrentlyActive: isFullyActive || isPartialPending,
                activeBranchCount: activeBranchCount,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

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
                                AppBadge.code(
                                  biz.displayCode,
                                  isTest: biz.isTestAccount,
                                  prefix: 'ID',
                                  fontSize: 12,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                ),
                              AppBadge.subscription(displayStatus),
                              if (isFullyActive)
                                AppBadge.count(
                                  label: 'All $totalBranchCount ${totalBranchCount == 1 ? "Location" : "Locations"} Active',
                                  color: AppColors.activeFg,
                                  backgroundColor: AppColors.activeBg,
                                  icon: Icons.check_circle,
                                ),
                              if (isPartialPending) ...[
                                AppBadge.count(
                                  label: '$activeBranchCount of $totalBranchCount Active',
                                  color: AppColors.activeFg,
                                  backgroundColor: AppColors.activeBg,
                                  icon: Icons.check_circle_outline,
                                ),
                                AppBadge.count(
                                  label: '$pendingBranchCount of $totalBranchCount Pending Payment (₹${pendingBranchCount * 1999})',
                                  color: AppColors.pendingFg,
                                  backgroundColor: AppColors.pendingBg,
                                  icon: Icons.hourglass_empty,
                                ),
                              ],
                              if (graceBranchCount > 0)
                                AppBadge.count(
                                  label: '$graceBranchCount ${totalBranchCount > 1 ? "of $totalBranchCount branches" : "branch"} in Grace Period',
                                  color: AppColors.graceFg,
                                  backgroundColor: AppColors.graceBg,
                                  icon: Icons.warning_amber_rounded,
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
                _InfoRow(
                  label: 'Owner email',
                  value: biz.ownerEmail ?? '—',
                  trailing: (biz.ownerEmail != null && biz.ownerEmail!.isNotEmpty)
                      ? Tooltip(
                          message: 'Send branded password reset email to owner',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Send Password Reset Email?'),
                                  content: Text(
                                    'This will send a branded AppNexa password reset email to:\n${biz.ownerEmail}',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Send Email'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && context.mounted) {
                                try {
                                  final fn = FirebaseFunctions.instanceFor(region: 'asia-south1')
                                      .httpsCallable('sendCustomPasswordResetEmail');
                                  await fn.call({'email': biz.ownerEmail!.trim()});
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Password reset email sent to ${biz.ownerEmail}'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to send email: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_reset, size: 16, color: Colors.blueAccent),
                                  SizedBox(width: 4),
                                  Text(
                                    'Reset Link',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                _InfoRow(label: 'Renewal date', value: renewalStr),
                _InfoRow(
                  label: 'Payment status',
                  value: isFullyActive
                      ? 'Paid in Full — ₹${totalActiveBranchAmount.toInt()} (${biz.paymentMode.isNotEmpty ? biz.paymentMode.toUpperCase() : "PAID"})'
                      : (isPartialPending
                          ? '₹${totalActiveBranchAmount.toInt()} Paid ($activeBranchCount active) • ₹${pendingBranchCount * 1999} Pending ($pendingBranchCount pending)'
                          : (isPendingPayment
                              ? 'Awaiting Setup Fee (₹${totalBranchCount > 0 ? totalBranchCount * 1999 : 1999})'
                              : '—')),
                ),
                _InfoRow(
                  label: 'Enrolled by',
                  value: _enrolledByName ?? (biz.enrolledBy == 'admin' ? 'Admin' : (biz.enrolledBy.isEmpty ? '—' : 'Loading…')),
                  trailing: isAdmin
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: InkWell(
                            onTap: _showChangeEnrollerDialog,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : null,
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

class _TestBusinessBanner extends StatelessWidget {
  final BusinessModel business;
  final bool isAdmin;
  final bool isCurrentlyActive;
  final int activeBranchCount;
  final VoidCallback? onConvertTap;

  const _TestBusinessBanner({
    required this.business,
    required this.isAdmin,
    required this.isCurrentlyActive,
    required this.activeBranchCount,
    this.onConvertTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
        border: Border.all(
          color: const Color(0xFFF59E0B),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.science_rounded, color: Color(0xFFB45309), size: 22),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Test Business Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'TEST MODE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'This business operates in test mode. It is excluded from platform revenue & active business counters. All printed QR codes and standees are permanent and will keep working upon conversion.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onConvertTap,
              icon: const Icon(Icons.rocket_launch_rounded, size: 16),
              label: const Text('Convert to Live'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                elevation: 1,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
  bool        _syncingRating = false;

  // QR download state (Change 1)
  bool    _qrLoading = false;
  String? _qrError;

  @override
  void initState() {
    super.initState();
    _standeeStatus = widget.branch.standeeStatus;
  }

  Future<void> _syncGoogleRating() async {
    if ((widget.branch.placeId ?? '').isEmpty) return;
    setState(() => _syncingRating = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final res = await context.read<PlacesService>().syncBranchGoogleRating(
        widget.branch.id,
        businessId: widget.branch.businessId,
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '✅ Google Rating Synced: ${res['rating'] ?? '—'} ★ (${res['userRatingCount'] ?? '0'} reviews)',
            ),
            backgroundColor: AppColors.activeFg,
          ),
        );
        widget.onBranchUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to sync Google rating: $e'),
            backgroundColor: errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingRating = false);
    }
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
    final path = widget.branch.qrCodeId ?? widget.branch.plainQrStoragePath;
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

  Future<void> _showDeleteBranchDialog() async {
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
                    onPressed: _showDeleteBranchDialog,
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

          // ── Branch Payment Panel (shown only for multi-branch businesses when pending) ───
          if (branch.isPendingPayment && widget.totalBranchCount > 1)
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
          if (branch.placeId != null && branch.placeId!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Rating',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              branch.currentRating != null
                                  ? '${branch.currentRating!.toStringAsFixed(1)} ★ (${branch.currentReviewCount ?? 0} reviews)'
                                  : (branch.initialRating != null
                                      ? '${branch.initialRating!.toStringAsFixed(1)} ★ (${branch.initialReviewCount ?? 0} reviews)'
                                      : 'Not synced yet'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (branch.initialRating != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Baseline: ${branch.initialRating!.toStringAsFixed(1)} ★',
                                  style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _syncingRating ? null : _syncGoogleRating,
                    icon: _syncingRating
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 14),
                    label: Text(
                      _syncingRating ? 'Syncing…' : 'Sync Rating',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(60, 30),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _InfoRow(label: 'Branch ID', value: branch.id, mono: true),

          const SizedBox(height: AppSpacing.md),

          // ── QR download (active branches) ───
          _PlainQrRow(
            plainQrStoragePath: branch.qrCodeId ?? branch.plainQrStoragePath,
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
        'amount': 1999 * 100, // ₹1,999 in paise
        'currency': 'INR',
        'name': 'AppNexa Technologies',
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
              const Text('Acrylic Standee Pipeline',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              // Current status chip
              AppBadge.standee(
                safeStatus,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          const SizedBox(height: 10),

          // Visual 4-Step Stepper
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: AppFulfillmentStepper(
              currentStatus: safeStatus,
              isInteractive: !updating,
              onStepSelected: updating ? null : onChanged,
              compact: true,
            ),
          ),
          const SizedBox(height: 10),

          DropdownButtonFormField<String>(
            value:         safeStatus,
            isExpanded:    true,
            dropdownColor: Colors.white,
            borderRadius:  BorderRadius.circular(14),
            elevation:     8,
            icon:          const Icon(Icons.keyboard_arrow_down_rounded),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
              label: const Text('Change Standee Status'),
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
  final Widget? trailing;
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.trailing,
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
            if (trailing != null) trailing!,
          ],
        ),
      );
}
