// lib/screens/enroll/payment_screen.dart
//
// Post-enrollment payment page.
//
// Flow:
//   EnrollScreen submits draft → navigates here with the new businessId.
//   Employee chooses one of two actions:
//
//   A. "Collect payment now" → Razorpay checkout (dart:html JS interop).
//      • On SUCCESS: navigate to /businesses, set pendingActivationId in provider,
//        start polling the business doc until subscription_status == "active".
//        The status flip comes ONLY from the webhook (Cloud Function), NEVER
//        written client-side here.
//      • On FAIL/CANCEL: stay on this page; show retry snackbar.
//
//   B. "Owner will pay later" → navigate to /businesses.
//      Business stays pending_payment, visible in the list with its badge.
//      The resend-payment-link action on the home screen handles follow-up.
//
// IMPORTANT: This screen NEVER writes subscription_status. The webhook is the
// only activation path (doc 05 — payment webhook flow).

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/my_businesses_provider.dart';

/// Razorpay checkout key — placeholder. Replace with real key before production.
const String _rzpKeyId = 'rzp_test_PLACEHOLDER';

/// Setup fee in paise (1 INR = 100 paise).
const int _setupFeePaise = 199900; // ₹1999

class PaymentScreen extends StatefulWidget {
  final String businessId;
  const PaymentScreen({super.key, required this.businessId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loadingBusiness = true;
  String _brandName = '';
  String _ownerName  = '';
  bool   _paying     = false;
  String? _payError;

  @override
  void initState() {
    super.initState();
    _loadBusiness();
  }

  Future<void> _loadBusiness() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .get();
      if (!mounted) return;
      final d = doc.data();
      setState(() {
        _brandName       = d?['brand_name'] as String? ?? '—';
        _ownerName       = d?['owner_name']  as String? ?? '—';
        _loadingBusiness = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBusiness = false);
    }
  }

  // ── Razorpay checkout (Dart → JS interop) ───────────────────────────────────
  //
  // The Razorpay checkout script must be loaded in web/index.html:
  //   <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
  //
  // On success the JS callback navigates home and starts webhook polling.
  // On dismiss/failure it stays on this page so the employee can retry or defer.

  Future<void> _launchRazorpay() async {
    setState(() { _paying = true; _payError = null; });

    // Guard: verify Razorpay is available in the global JS scope.
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

      // Dart callbacks registered with the JS options map.
      // These run synchronously on the JS main thread via dart:js allowInterop.
      final handlerSuccess = js.allowInterop((dynamic response) {
        if (!mounted) return;
        // SUCCESS: navigate home + start webhook polling.
        // Do NOT set subscription_status here — webhook-only activation path.
        final biz = context.read<MyBusinessesProvider>();
        biz.setPendingActivation(bizId);
        biz.refresh();
        context.go('/businesses');
      });

      final handlerDismiss = js.allowInterop(() {
        if (!mounted) return;
        setState(() {
          _paying   = false;
          _payError = 'Payment cancelled. You can retry or defer for now.';
        });
      });

      // Build the options JsObject that Razorpay expects.
      final options = js.JsObject.jsify({
        'key':         _rzpKeyId,
        'amount':      _setupFeePaise,
        'currency':    'INR',
        'name':        'Review System',
        'description': 'Business setup fee — $_brandName',
        'notes': {
          'business_id': bizId,
          'enrolled_by': empId,
        },
        'handler': handlerSuccess,
        'modal':   {'ondismiss': handlerDismiss},
        'prefill': {'name': _ownerName},
        'theme':   {'color': '#3B4DB8'},
      });

      // Invoke: const rzp = new Razorpay(options); rzp.open();
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

  // ── Defer ────────────────────────────────────────────────────────────────────
  void _defer() {
    // Business stays pending_payment — employee handles follow-up via the
    // resend-payment-link action on the home screen.
    context.go('/businesses');
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect Payment'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _loadingBusiness
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // ── Header ────────────────────────────────────────────────
                    Icon(Icons.receipt_long_outlined,
                        size: 48, color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Payment for $_brandName',
                      style: tt.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Business enrolled successfully as a draft.\nCollect the setup fee now or let the owner pay later.',
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
                            Text('Plan Summary', style: tt.titleMedium),
                            const SizedBox(height: 16),
                            _PlanRow(
                              label: 'Setup fee (one-time)',
                              value: '₹1,999',
                              badge: 'Due now',
                              badgeColor: AppTheme.statusColor('pending_payment'),
                              badgeFgColor: AppTheme.statusForeground('pending_payment'),
                            ),
                            const Divider(height: 24),
                            _PlanRow(
                              label: 'Annual renewal (from Year 2)',
                              value: '₹999 / year',
                              badge: 'Next year',
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
                                      'The ₹999/year renewal starts from the 2nd year. '
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

                    // ── Primary CTA: Collect payment ─────────────────────────
                    ElevatedButton.icon(
                      onPressed: _paying ? null : _launchRazorpay,
                      icon: _paying
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary))
                          : const Icon(Icons.payments_outlined),
                      label: Text(
                          _paying ? 'Opening checkout…' : 'Collect payment now  ₹1,999'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Secondary CTA: Defer ──────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _paying ? null : _defer,
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('Owner will pay later'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Defer explanation ─────────────────────────────────────
                    Text(
                      'If deferred, the business appears in your list with an '
                      '"Awaiting payment" badge. Use the "Resend payment link" '
                      'action to send a payment link to the owner later.',
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
