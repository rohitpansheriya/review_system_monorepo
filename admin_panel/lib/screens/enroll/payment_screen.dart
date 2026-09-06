// lib/screens/enroll/payment_screen.dart
//
// Post-enrollment payment page.
//
// Flow (NEW MODEL — GROUP C):
//   EnrollScreen submits draft → navigates here with the new businessId.
//
//   ADMIN path:
//     A. "Cash Payment — Activate Now" → admin cash-activates directly.
//        Business flips to active, QR generation triggered, commission recorded.
//     B. "Online Payment (Razorpay)" → same as employee Razorpay flow.
//     C. "Owner will pay online later" → defer.
//
//   EMPLOYEE path:
//     A. "Online Payment (Razorpay)" → Razorpay checkout (dart:html JS interop).
//        On SUCCESS: webhook activates, navigate home.
//     B. "Owner will pay online later" → defer.
//     *** NO CASH OPTION FOR EMPLOYEES ***
//
// IMPORTANT: This screen NEVER writes subscription_status directly.
// Activation paths: admin cash activate (via service) OR Razorpay webhook.

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';

class PaymentScreen extends StatefulWidget {
  final String businessId;
  final String? branchId;

  const PaymentScreen({
    super.key,
    required this.businessId,
    this.branchId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

/// Returns the role-aware home route: admin → /admin, employee → /businesses.
String _homeRoute(BuildContext context) {
  final isAdmin = context.read<AppAuthProvider>().isAdmin;
  return isAdmin ? '/admin' : '/businesses';
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = true;
  String _brandName = '';
  String _ownerName  = '';
  String _ownerPhone = '';
  String _branchName = '';
  String _branchAddress = '';
  int _branchCount = 1;
  bool   _paying = false;
  bool   _cashActivating = false;
  bool   _sharingWhatsApp = false;
  bool   _copyingLink = false;
  bool   _deferring = false;
  String? _shortUrl;
  String? _payError;

  bool get _isProcessing => _paying || _cashActivating || _sharingWhatsApp || _copyingLink || _deferring;

  bool get isBranchPayment => widget.branchId != null && widget.branchId!.isNotEmpty;
  int get setupFeeRupees => isBranchPayment ? 1999 : (_branchCount * 1999);
  int get setupFeePaise => setupFeeRupees * 100;
  int get renewalFeeRupees => isBranchPayment ? 999 : (_branchCount * 999);

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final bizDoc = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .get();

      if (!mounted) return;
      final bizData = bizDoc.data();
      _brandName = bizData?['brand_name'] as String? ?? '—';
      _ownerName = bizData?['owner_name'] as String? ?? '—';
      _ownerPhone = bizData?['owner_phone'] as String? ?? '';

      if (isBranchPayment) {
        _branchCount = 1;
        final branchDoc = await FirebaseFirestore.instance
            .collection(AppConstants.colBusinesses)
            .doc(widget.businessId)
            .collection(AppConstants.colBranches)
            .doc(widget.branchId!)
            .get();
        if (mounted && branchDoc.exists) {
          final bData = branchDoc.data();
          _branchName = bData?['branch_name'] as String? ?? 'Branch';
          _branchAddress = bData?['address'] as String? ?? '';
        }
      } else {
        final branchesSnap = await FirebaseFirestore.instance
            .collection(AppConstants.colBusinesses)
            .doc(widget.businessId)
            .collection(AppConstants.colBranches)
            .get();
        if (mounted && branchesSnap.docs.isNotEmpty) {
          final pendingBranches = branchesSnap.docs.where((d) {
            final s = d.data()['subscription_status'] as String?;
            return s == AppConstants.statusPendingPayment || s == null;
          }).toList();
          _branchCount = pendingBranches.isNotEmpty ? pendingBranches.length : branchesSnap.docs.length;
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Razorpay checkout (Dart → JS interop) ───────────────────────────────────
  Future<void> _launchRazorpay() async {
    if (_isProcessing) return;
    setState(() { _paying = true; _payError = null; });

    if (!js.context.hasProperty('Razorpay')) {
      setState(() {
        _paying   = false;
        _payError = 'Razorpay script not loaded. Add checkout.js to web/index.html.';
      });
      return;
    }

    try {
      final empId = context.read<AppAuthProvider>().uid ?? '';
      final bizId = widget.businessId;

      final handlerSuccess = js.allowInterop((dynamic response) {
        if (!mounted) return;
        final biz = context.read<MyBusinessesProvider>();
        biz.setPendingActivation(bizId);
        biz.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payment received! Activation in progress.'),
            backgroundColor: Colors.green,
          ),
        );
        if (isBranchPayment) {
          context.go('/business/$bizId');
        } else {
          context.go(_homeRoute(context));
        }
      });

      final handlerDismiss = js.allowInterop(() {
        if (!mounted) return;
        setState(() {
          _paying   = false;
          _payError = 'Payment cancelled. You can retry or defer for now.';
        });
      });

      final notesMap = <String, dynamic>{
        'business_id': bizId,
        'businessId': bizId,
        'enrolled_by': empId,
        'branch_count': _branchCount,
      };

      if (isBranchPayment) {
        notesMap['branch_id'] = widget.branchId!;
        notesMap['branchId'] = widget.branchId!;
        notesMap['type'] = 'branch_setup_fee';
      }

      final options = js.JsObject.jsify({
        'key':         AppConfig.razorpayKeyId,
        'amount':      setupFeePaise,
        'currency':    'INR',
        'name':        'Appnexa Technologies',
        'description': isBranchPayment
            ? 'Branch setup fee — $_branchName ($_brandName)'
            : (_branchCount > 1
                ? 'Setup fee ($_branchCount branches) — $_brandName'
                : 'Business setup fee — $_brandName'),
        'notes': notesMap,
        'handler': handlerSuccess,
        'modal':   {'ondismiss': handlerDismiss},
        'prefill': {'name': _ownerName},
        'theme':   {'color': '#3B4DB8'},
      });

      final rzp = js.JsObject(js.context['Razorpay'] as js.JsFunction, [options]);
      rzp.callMethod('open');
    } catch (e) {
      if (mounted) {
        setState(() {
          _paying   = false;
          _payError = 'Failed to open payment: $e';
        });
      }
    }
  }

  // ── Admin Cash Activate (Admin only) ───────────────────────────────────────
  Future<void> _adminCashActivate() async {
    if (_isProcessing) return;
    setState(() { _cashActivating = true; _payError = null; });

    final auth = context.read<AppAuthProvider>();
    if (!auth.isAdmin) {
      setState(() {
        _cashActivating = false;
        _payError = 'Permission denied: Only admins can activate with cash.';
      });
      return;
    }

    try {
      final adminUid = auth.uid ?? '';
      final svc = context.read<FirestoreService>();

      if (isBranchPayment) {
        await svc.adminCashActivateBranch(
          businessId: widget.businessId,
          branchId: widget.branchId!,
        );
      } else {
        await svc.adminCashActivate(
          businessId: widget.businessId,
          adminUid: adminUid,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBranchPayment
              ? '✅ Branch "$_branchName" activated via cash payment! QR generation triggered.'
              : '✅ Business "$_brandName" activated via cash payment! QR generation triggered.'),
          backgroundColor: Colors.green,
        ),
      );

      if (isBranchPayment) {
        context.go('/business/${widget.businessId}');
      } else {
        context.go('/admin');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cashActivating = false;
          _payError = 'Cash activation failed: $e';
        });
      }
    }
  }

  // ── Instant WhatsApp Share of Payment Link ──────────────────────────────
  Future<void> _sendWhatsAppPaymentLink() async {
    if (_isProcessing) return;
    setState(() {
      _sharingWhatsApp = true;
      _payError = null;
    });

    try {
      String? url = _shortUrl;
      if (url == null) {
        final svc = context.read<FirestoreService>();
        final Map<String, dynamic> res;
        if (isBranchPayment) {
          res = await svc.resendBranchPaymentLink(
            businessId: widget.businessId,
            branchId: widget.branchId!,
          );
        } else {
          res = await svc.resendPaymentLink(widget.businessId);
        }
        url = res['shortUrl'] as String?;
        if (mounted && url != null) {
          setState(() => _shortUrl = url);
        }
      }

      if (url != null) {
        await Clipboard.setData(ClipboardData(text: url));
        final ownerGreeting = _ownerName.isNotEmpty && _ownerName != '—' ? _ownerName : 'there';
        final targetBiz = _brandName.isNotEmpty && _brandName != '—' ? _brandName : 'your business';
        final msg = 'Hello $ownerGreeting, here is the secure link to activate your AppNexa Smart Standee for $targetBiz: $url';
        
        // Clean phone number for wa.me URL
        String cleanPhone = _ownerPhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanPhone.startsWith('0')) cleanPhone = cleanPhone.substring(1);
        if (cleanPhone.length == 10) cleanPhone = '91$cleanPhone';

        final waUrl = cleanPhone.isNotEmpty
            ? 'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}'
            : 'https://wa.me/?text=${Uri.encodeComponent(msg)}';

        html.window.open(waUrl, '_blank');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Opening WhatsApp with pre-formatted payment message!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _payError = 'Failed to generate link: $e');
    } finally {
      if (mounted) setState(() => _sharingWhatsApp = false);
    }
  }

  // ── Generate / Share Payment Link ──────────────────────────────────────────
  Future<void> _sharePaymentLink() async {
    if (_isProcessing) return;
    setState(() {
      _copyingLink = true;
      _payError = null;
    });

    try {
      final svc = context.read<FirestoreService>();
      final Map<String, dynamic> res;

      if (isBranchPayment) {
        res = await svc.resendBranchPaymentLink(
          businessId: widget.businessId,
          branchId: widget.branchId!,
        );
      } else {
        res = await svc.resendPaymentLink(widget.businessId);
      }

      final url = res['shortUrl'] as String?;
      if (mounted) {
        setState(() => _shortUrl = url);
        if (url != null) {
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Payment link copied to clipboard!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _payError = 'Failed to generate link: $e');
    } finally {
      if (mounted) setState(() => _copyingLink = false);
    }
  }

  // ── Defer (Owner will pay online later) ──────────────────────────────────────
  Future<void> _defer() async {
    if (_isProcessing) return;
    setState(() {
      _deferring = true;
      _payError = null;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final svc = context.read<FirestoreService>();
      if (isBranchPayment) {
        await svc.resendBranchPaymentLink(
          businessId: widget.businessId,
          branchId: widget.branchId!,
        );
      } else {
        await svc.resendPaymentLink(widget.businessId);
      }
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('✉️ Payment link email sent to the owner!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Non-blocking fallback
    } finally {
      if (mounted) {
        setState(() => _deferring = false);
      }
    }

    if (mounted) {
      if (isBranchPayment) {
        context.go('/business/${widget.businessId}');
      } else {
        context.go(_homeRoute(context));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;
    final isAdmin = context.read<AppAuthProvider>().isAdmin;

    final headerTitle = isBranchPayment
        ? 'Payment for Branch: $_branchName'
        : (_branchCount > 1
            ? 'Payment for $_brandName ($_branchCount Locations)'
            : 'Payment for $_brandName');

    final headerSubtitle = isBranchPayment
        ? 'Branch enrolled under $_brandName.\nCollect setup fee now or let the owner pay online later.'
        : (_branchCount > 1
            ? '$_branchCount locations enrolled under $_brandName.\nCollect total setup fee (₹1,999 × $_branchCount) now or let the owner pay online later.'
            : 'Business enrolled successfully as a draft.\nCollect setup fee now or let the owner pay online later.');

    final planSummaryTitle = isBranchPayment
        ? 'Branch Plan Summary'
        : (_branchCount > 1 ? 'Plan Summary ($_branchCount Locations)' : 'Plan Summary');

    final setupBadgeText = isBranchPayment
        ? 'Due now'
        : (_branchCount > 1 ? 'Due now (₹1,999 × $_branchCount)' : 'Due now');

    final renewalBadgeText = isBranchPayment
        ? 'Next year'
        : (_branchCount > 1 ? 'From Year 2 (₹999 × $_branchCount)' : 'Next year');

    return Scaffold(
      appBar: AppBar(
        title: Text(isBranchPayment ? 'Collect Branch Payment' : 'Collect Payment'),
        leading: BackButton(
          onPressed: _isProcessing
              ? null
              : () => isBranchPayment
                  ? context.go('/business/${widget.businessId}')
                  : context.go(_homeRoute(context)),
        ),
        bottom: _isProcessing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(minHeight: 4),
              )
            : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // ── Header ────────────────────────────────────────────────
                    Icon(Icons.receipt_long_outlined,
                        size: 48, color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      headerTitle,
                      style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (isBranchPayment && _branchAddress.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _branchAddress,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      headerSubtitle,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // ── Plan summary card ─────────────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(planSummaryTitle,
                                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            _PlanRow(
                              label: 'Setup fee (one-time)',
                              value: '₹$setupFeeRupees',
                              badge: setupBadgeText,
                              badgeColor: AppTheme.statusColor('pending_payment'),
                              badgeFgColor: AppTheme.statusForeground('pending_payment'),
                            ),
                            const Divider(height: 24),
                            _PlanRow(
                              label: 'Annual renewal (from Year 2)',
                              value: '₹$renewalFeeRupees / year',
                              badge: renewalBadgeText,
                              badgeColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                              badgeFgColor: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'The renewal starts from the 2nd year (₹999/year per location). '
                                      'Razorpay will auto-collect it — no manual follow-up needed.',
                                      style: tt.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Error state ───────────────────────────────────────────
                    if (_payError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_payError!,
                                  style: tt.bodySmall?.copyWith(
                                      color: cs.onErrorContainer)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_shortUrl != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: SelectableText(
                          'Payment Link: $_shortUrl',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Admin-only: Cash Activate button ──────────────────────
                    if (isAdmin) ...[
                      FilledButton.icon(
                        onPressed: _isProcessing ? null : _adminCashActivate,
                        icon: _cashActivating
                            ? SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onTertiary))
                            : const Icon(Icons.local_atm_outlined),
                        label: Text(
                            _cashActivating
                                ? 'Activating…'
                                : (isBranchPayment
                                    ? 'Cash Payment — Activate Branch (₹1,999)'
                                    : (_branchCount > 1
                                        ? 'Cash Payment — Activate $_branchCount Branches (₹$setupFeeRupees)'
                                        : 'Cash Payment — Activate Business (₹1,999)'))),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiary,
                          foregroundColor: cs.onTertiary,
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── WhatsApp Share Payment Link CTA ──────────────────────────────
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _sendWhatsAppPaymentLink,
                      icon: _sharingWhatsApp
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.chat_bubble_outline, size: 20),
                      label: Text(
                        _sharingWhatsApp ? 'Opening WhatsApp…' : 'Send Payment Link on WhatsApp',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Primary CTA: Online payment ───────────────────────────
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _launchRazorpay,
                      icon: _paying
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary))
                          : const Icon(Icons.payments_outlined),
                      label: Text(
                          _paying ? 'Opening checkout…' : 'Pay Online via Razorpay (₹$setupFeeRupees)'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Copy Payment Link CTA ─────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _sharePaymentLink,
                      icon: _copyingLink
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.copy_outlined, size: 18),
                      label: Text(
                        _copyingLink ? 'Generating link…' : 'Copy Payment Link to Clipboard',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Defer CTA ───────────────────────────────────────────
                    TextButton.icon(
                      onPressed: _isProcessing ? null : _defer,
                      icon: _deferring
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.schedule_outlined),
                      label: Text(
                        _deferring ? 'Saving & sending link…' : 'Owner will pay online later (Defer)',
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Defer explanation ─────────────────────────────────────
                    Text(
                      'If deferred, this location appears with an "Awaiting payment" badge. '
                      'Use the payment link or pay online action whenever the owner is ready.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PlanRow extends StatelessWidget {
  final String label;
  final String value;
  final String badge;
  final Color  badgeColor;
  final Color  badgeFgColor;

  const _PlanRow({
    required this.label,
    required this.value,
    required this.badge,
    required this.badgeColor,
    required this.badgeFgColor,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.bodyMedium),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge,
                    style: tt.labelSmall?.copyWith(color: badgeFgColor,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Text(value,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
