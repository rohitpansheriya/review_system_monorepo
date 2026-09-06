// lib/screens/owner/owner_renewal_tab.dart
//
// Renewal & Payment Tab for Business Owner.
// Displays individual branch renewal data, branch payment links,
// and a combined option to renew all branches at once.
//
// RENEWAL PATH: Status flips and renewal_date extends ONLY via the
// payment webhook in razorpay.ts — NO SECOND ACTIVATION PATH.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/constants.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../providers/owner_dashboard_provider.dart';
import '../../services/firestore_service.dart';

class OwnerRenewalTab extends StatefulWidget {
  const OwnerRenewalTab({super.key});

  @override
  State<OwnerRenewalTab> createState() => _OwnerRenewalTabState();
}

class _OwnerRenewalTabState extends State<OwnerRenewalTab> {
  bool _paying = false;
  String? _payingTarget; // 'all' or branchId
  String? _payError;

  // Track loading state for generating payment links
  String? _generatingLinkId; // 'all' or branchId
  final Map<String, String> _generatedLinks = {}; // key: 'all' | branchId -> shortUrl

  static const int _renewalFeePerBranchPaise = 99900; // ₹999 in paise

  /// Launches Razorpay modal for either all branches combined or a single branch.
  Future<void> _launchRazorpayRenewal({
    required BusinessModel biz,
    BranchModel? branch,
    required List<BranchModel> allBranches,
  }) async {
    final targetId = branch?.id ?? 'all';
    if (_paying) return;

    setState(() {
      _paying = true;
      _payingTarget = targetId;
      _payError = null;
    });

    final keyId = AppConfig.razorpayKeyId;
    if (keyId.isEmpty) {
      setState(() {
        _paying = false;
        _payingTarget = null;
        _payError = 'Razorpay Key ID is not configured. Please contact support.';
      });
      return;
    }

    if (!js.context.hasProperty('Razorpay')) {
      setState(() {
        _paying = false;
        _payingTarget = null;
        _payError = 'Razorpay checkout script not loaded in web scope.';
      });
      return;
    }

    try {
      final isSingle = branch != null;
      final branchCount = isSingle ? 1 : (allBranches.isNotEmpty ? allBranches.length : 1);
      final totalPaise = isSingle ? _renewalFeePerBranchPaise : branchCount * _renewalFeePerBranchPaise;
      final desc = isSingle
          ? 'Annual Subscription Renewal — ${branch.branchName}'
          : 'Annual Subscription Renewal for $branchCount locations — ${biz.brandName}';

      final handlerSuccess = js.allowInterop((dynamic response) {
        if (!mounted) return;
        setState(() {
          _paying = false;
          _payingTarget = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Payment received! Renewal processing via secure webhook. Dashboard will update shortly.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );
      });

      final handlerDismiss = js.allowInterop(() {
        if (!mounted) return;
        setState(() {
          _paying = false;
          _payingTarget = null;
          _payError = 'Renewal payment cancelled.';
        });
      });

      final notesMap = <String, dynamic>{
        'business_id': biz.id,
        'businessId': biz.id,
        'type': 'annual_renewal',
      };
      if (isSingle) {
        notesMap['branch_id'] = branch.id;
        notesMap['branchId'] = branch.id;
      } else {
        notesMap['branch_count'] = branchCount.toString();
      }

      final options = js.JsObject.jsify({
        'key': keyId,
        'amount': totalPaise,
        'currency': 'INR',
        'name': 'Appnexa Technologies',
        'description': desc,
        'notes': notesMap,
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
          _payingTarget = null;
          _payError = 'Payment initialization failed: ${e.toString()}';
        });
      }
    }
  }

  /// Generates or fetches a shareable payment link for combined or branch-specific renewal.
  Future<void> _generateAndCopyPaymentLink({
    required BuildContext context,
    required String businessId,
    BranchModel? branch,
  }) async {
    final targetKey = branch?.id ?? 'all';
    setState(() {
      _generatingLinkId = targetKey;
      _payError = null;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final totalBranchCount = context.read<OwnerDashboardProvider>().branches.length;

    try {
      final svc = context.read<FirestoreService>();
      final result = await svc.generateRenewalPaymentLink(
        businessId: businessId,
        branchId: branch?.id,
      );

      final shortUrl = (result['shortUrl'] ?? result['short_url'] ?? '') as String;
      if (shortUrl.isEmpty) {
        throw Exception('Failed to generate payment link.');
      }

      if (mounted) {
        setState(() {
          _generatedLinks[targetKey] = shortUrl;
          _generatingLinkId = null;
        });

        await Clipboard.setData(ClipboardData(text: shortUrl));

        if (mounted) {
          _showPaymentLinkDialog(
            context: context,
            title: branch != null
                ? 'Renewal Link — ${branch.branchName}'
                : 'Combined Renewal Link (All Branches)',
            url: shortUrl,
            amountRupees: (result['amountRupees'] ?? (branch != null ? 999 : 999 * totalBranchCount)) as num,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generatingLinkId = null;
          _payError = 'Link generation error: ${e.toString()}';
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('⚠️ Could not generate payment link: $e'),
            backgroundColor: errorColor,
          ),
        );
      }
    }
  }

  void _showPaymentLinkDialog({
    required BuildContext context,
    required String title,
    required String url,
    required num amountRupees,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.link_rounded, color: Color(0xFF3B4DB8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount: ₹$amountRupees (Annual Renewal)',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      url,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF3B4DB8)),
                    tooltip: 'Copy Link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Link copied to clipboard!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '✅ Link copied to clipboard! You can also share directly on WhatsApp or open in browser.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366), size: 18),
            label: const Text('Share on WhatsApp', style: TextStyle(color: Color(0xFF25D366))),
            onPressed: () {
              final text = Uri.encodeComponent(
                'Here is your annual subscription renewal link for Appnexa ($title): $url',
              );
              html.window.open('https://wa.me/?text=$text', '_blank');
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B4DB8),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final biz = provider.business;
    final branches = provider.branches;

    if (biz == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final branchCount = branches.isNotEmpty ? branches.length : 1;
    final totalRenewalPaise = branchCount * _renewalFeePerBranchPaise;
    final totalRenewalRupees = totalRenewalPaise / 100;

    final dateFormat = DateFormat('dd MMM yyyy');
    final bizRenewalStr = biz.renewalDate != null
        ? dateFormat.format(biz.renewalDate!)
        : 'Not set';

    final isMultiBranch = branches.length > 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Subscription & Renewal',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your annual subscriptions (₹999/year per branch) and payment links.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // Suspended Banner
              if (provider.isSuspended)
                Card(
                  color: const Color(0xFFFEF2F2),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.qr_code_2_rounded, color: Color(0xFFDC2626), size: 24),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '⚠️ Subscription Suspended — QR Standees Inactive',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Customer review redirection on your QR standees is paused. Renew your subscription below to instantly reactivate all standees.',
                          style: TextStyle(color: Color(0xFFB91C1C), fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),

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
                                Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '⚠️ Subscription In Grace Period',
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
                              'Subscription expired ($daysLeft days remaining in grace period). Renew below to ensure uninterrupted service.',
                              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              if (_payError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _payError!,
                          style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // ════════════════════════════════════════════════════════════════
              // COMBINED / ALL BRANCHES RENEWAL CARD
              // ════════════════════════════════════════════════════════════════
              _buildCombinedRenewalCard(
                context: context,
                biz: biz,
                branches: branches,
                totalRupees: totalRenewalRupees,
                renewalStr: bizRenewalStr,
                isMultiBranch: isMultiBranch,
              ),

              const SizedBox(height: 32),

              // ════════════════════════════════════════════════════════════════
              // INDIVIDUAL BRANCHES SECTION
              // ════════════════════════════════════════════════════════════════
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Individual Branch Renewals',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'View renewal dates and generate separate payment links for each location.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${branches.length} ${branches.length == 1 ? "Branch" : "Branches"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (branches.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No individual branches found for this account.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                ...branches.map((branch) => _buildIndividualBranchCard(
                      context: context,
                      biz: biz,
                      branch: branch,
                      allBranches: branches,
                      dateFormat: dateFormat,
                    )),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Payments are secured by Razorpay.\nRenewal extends subscription by 1 full year from current expiry.',
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

  /// Builds the Combined Renewal Card for all branches at once.
  Widget _buildCombinedRenewalCard({
    required BuildContext context,
    required BusinessModel biz,
    required List<BranchModel> branches,
    required num totalRupees,
    required String renewalStr,
    required bool isMultiBranch,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPayingAll = _paying && _payingTarget == 'all';
    final isGeneratingAll = _generatingLinkId == 'all';
    final count = branches.isNotEmpty ? branches.length : 1;

    final existingCombinedLink = _generatedLinks['all'] ?? biz.lastRenewalLinkUrl;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.35),
              colorScheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMultiBranch ? Icons.account_tree_rounded : Icons.storefront_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMultiBranch ? 'Combined Multi-Branch Renewal' : 'Annual Subscription Renewal',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isMultiBranch
                              ? 'Renew all $count branches in a single combined payment'
                              : 'Standard single-location annual plan',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _buildStatusBadge(context, biz.subscriptionStatus),
              ],
            ),
            const Divider(height: 32),

            // Summary grid
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _buildSummaryTile(
                  context,
                  label: 'Total Branches',
                  value: '$count ${count == 1 ? "Location" : "Locations"}',
                  icon: Icons.location_on_outlined,
                ),
                _buildSummaryTile(
                  context,
                  label: 'Combined Annual Fee',
                  value: '₹$totalRupees / year',
                  subtitle: isMultiBranch ? '$count × ₹999/yr' : '₹999/yr',
                  icon: Icons.payments_outlined,
                  isHighlight: true,
                ),
                _buildSummaryTile(
                  context,
                  label: 'Next Renewal Date',
                  value: renewalStr,
                  icon: Icons.calendar_today_outlined,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _paying
                          ? null
                          : () => _launchRazorpayRenewal(
                                biz: biz,
                                allBranches: branches,
                              ),
                      icon: isPayingAll
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.bolt_rounded, size: 20),
                      label: Text(
                        isPayingAll
                            ? 'Opening Checkout...'
                            : (isMultiBranch
                                ? 'Pay ₹$totalRupees to Renew All ($count Branches)'
                                : 'Pay ₹$totalRupees to Renew Subscription'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: isGeneratingAll
                          ? null
                          : () => _generateAndCopyPaymentLink(
                                context: context,
                                businessId: biz.id,
                              ),
                      icon: isGeneratingAll
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_rounded, size: 20),
                      label: Text(
                        isGeneratingAll ? 'Generating...' : 'Payment Link',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (existingCombinedLink != null && existingCombinedLink.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: Color(0xFF3B4DB8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last Combined Link: $existingCombinedLink',
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: existingCombinedLink));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Combined renewal link copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds a single branch renewal card.
  Widget _buildIndividualBranchCard({
    required BuildContext context,
    required BusinessModel biz,
    required BranchModel branch,
    required List<BranchModel> allBranches,
    required DateFormat dateFormat,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPayingThis = _paying && _payingTarget == branch.id;
    final isGeneratingThis = _generatingLinkId == branch.id;

    final branchRenewal = branch.renewalDate ?? biz.renewalDate;
    final branchRenewalStr = branchRenewal != null ? dateFormat.format(branchRenewal) : 'Not set';
    final branchGrace = branch.gracePeriodEnds ?? biz.gracePeriodEnds;
    final branchGraceStr = branchGrace != null ? dateFormat.format(branchGrace) : null;

    final existingLink = _generatedLinks[branch.id] ?? branch.lastRenewalLinkUrl;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branch.branchName.isNotEmpty ? branch.branchName : 'Branch Location',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (branch.address.isNotEmpty)
                        Text(
                          branch.address,
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                _buildStatusBadge(context, branch.subscriptionStatus),
              ],
            ),
            const Divider(height: 24),

            // Branch Details Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Renewal Date', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(branchRenewalStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                if (branchGraceStr != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Grace Period Ends', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(branchGraceStr, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDC2626), fontSize: 13)),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Annual Fee', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text('₹999 / year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534))),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Branch Actions Row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _paying
                        ? null
                        : () => _launchRazorpayRenewal(
                              biz: biz,
                              branch: branch,
                              allBranches: allBranches,
                            ),
                    icon: isPayingThis
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.payment, size: 16),
                    label: Text(
                      isPayingThis ? 'Processing...' : 'Pay ₹999 for this Branch',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: isGeneratingThis
                      ? null
                      : () => _generateAndCopyPaymentLink(
                            context: context,
                            businessId: biz.id,
                            branch: branch,
                          ),
                  icon: isGeneratingThis
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link, size: 16),
                  label: Text(
                    isGeneratingThis ? 'Generating...' : 'Payment Link',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),

            if (existingLink != null && existingLink.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        existingLink,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF475569)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14),
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: existingLink));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('✅ Copied link for ${branch.branchName}!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(
    BuildContext context, {
    required String label,
    required String value,
    String? subtitle,
    required IconData icon,
    bool isHighlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: isHighlight ? colorScheme.primary : colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isHighlight ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($subtitle)',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AppConstants.statusActive:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        label = 'Active';
        break;
      case AppConstants.statusGracePeriod:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Grace Period';
        break;
      case AppConstants.statusSuspended:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'Suspended';
        break;
      case AppConstants.statusPendingPayment:
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFF854D0E);
        label = 'Pending Payment';
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
