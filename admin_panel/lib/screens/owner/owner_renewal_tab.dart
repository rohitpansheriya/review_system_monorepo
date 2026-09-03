// lib/screens/owner/owner_renewal_tab.dart
//
// Renewal & Payment Tab for Business Owner.
// Displays renewal_date, subscription_status, grace_period_ends.
// Integrates Razorpay checkout for ₹999 annual renewal.
//
// RENEWAL PATH: Status flips and renewal_date extends ONLY via the
// existing payment webhook in razorpay.ts — NO SECOND ACTIVATION PATH.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/constants.dart';
import '../../providers/owner_dashboard_provider.dart';

class OwnerRenewalTab extends StatefulWidget {
  const OwnerRenewalTab({super.key});

  @override
  State<OwnerRenewalTab> createState() => _OwnerRenewalTabState();
}

class _OwnerRenewalTabState extends State<OwnerRenewalTab> {
  bool _paying = false;
  String? _payError;

  static const int _renewalFeePaise = 99900; // ₹999 in paise

  Future<void> _launchRazorpayRenewal(String businessId, String brandName) async {
    if (_paying) return;
    setState(() {
      _paying = true;
      _payError = null;
    });

    final keyId = AppConfig.razorpayKeyId;
    if (keyId.isEmpty) {
      setState(() {
        _paying = false;
        _payError = 'Razorpay Key ID is not configured. Please contact support.';
      });
      return;
    }

    if (!js.context.hasProperty('Razorpay')) {
      setState(() {
        _paying = false;
        _payError = 'Razorpay checkout script not loaded in web scope.';
      });
      return;
    }

    try {
      final handlerSuccess = js.allowInterop((dynamic response) {
        if (!mounted) return;
        setState(() => _paying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Payment received! Renewal processing via secure webhook. Dashboard will update shortly.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      });

      final handlerDismiss = js.allowInterop(() {
        if (!mounted) return;
        setState(() {
          _paying = false;
          _payError = 'Renewal payment cancelled.';
        });
      });

      final options = js.JsObject.jsify({
        'key': keyId,
        'amount': _renewalFeePaise,
        'currency': 'INR',
        'name': 'Appnexa Technologies',
        'description': 'Annual Subscription Renewal — $brandName',
        'notes': {
          'business_id': businessId,
          'businessId': businessId,
          'type': 'annual_renewal',
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
          _paying = false;
          _payError = 'Payment initialization failed: ${e.toString()}';
        });
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
      return const Center(child: CircularProgressIndicator());
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final renewalStr = biz.renewalDate != null
        ? dateFormat.format(biz.renewalDate!)
        : 'Not set';
    final graceStr = biz.gracePeriodEnds != null
        ? dateFormat.format(biz.gracePeriodEnds!)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subscription & Renewal',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your annual plan (₹999/year) and payment status.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Grace Period Banner
              if (provider.isGracePeriod)
                Builder(
                  builder: (context) {
                    final graceEnds = biz.gracePeriodEnds;
                    final daysLeft = graceEnds != null ? graceEnds.difference(DateTime.now()).inDays : 0;
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.qr_code_2_rounded,
                                    color: Color(0xFFDC2626), size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '⚠️ Subscription Expired — QR Standees Inactive',
                                    style: TextStyle(
                                      color: Color(0xFF991B1B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Customer review collection on your physical QR standees is currently unavailable ($daysLeft days remaining before permanent account & data deletion). Pay ₹999 below to instantly reactivate your standees and resume review collection.',
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // Status & Dates Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subscription Status',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _buildStatusBadge(context, biz.subscriptionStatus),
                        ],
                      ),
                      const Divider(height: 32),
                      _buildDateRow(context, 'Renewal Date', renewalStr, Icons.calendar_month),
                      if (graceStr != null) ...[
                        const SizedBox(height: 12),
                        _buildDateRow(context, 'Grace Period Ends', graceStr, Icons.alarm,
                            isWarning: true),
                      ],
                      const SizedBox(height: 12),
                      _buildDateRow(context, 'Annual Renewal Fee', '₹999 / year', Icons.payments),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (_payError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _payError!,
                    style: TextStyle(color: colorScheme.error, fontSize: 13),
                  ),
                ),

              // Checkout Action Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _paying
                      ? null
                      : () => _launchRazorpayRenewal(biz.id, biz.brandName),
                  icon: _paying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment),
                  label: Text(
                    _paying ? 'Opening Checkout...' : 'Pay ₹999 to Renew Subscription',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Payments are secured by Razorpay.\nRenewal extends your subscription by 1 full year from expiry.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AppConstants.statusActive:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        label = 'Active';
        break;
      case AppConstants.statusGracePeriod:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = 'Grace Period';
        break;
      case AppConstants.statusDeleted:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Deleted / Lapsed';
        break;
      default:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildDateRow(
      BuildContext context, String label, String value, IconData icon,
      {bool isWarning = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: isWarning ? scheme.error : scheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isWarning ? scheme.error : scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
