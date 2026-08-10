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

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';

class BusinessDetailScreen extends StatefulWidget {
  final BusinessModel business;
  const BusinessDetailScreen({super.key, required this.business});

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  List<BranchModel> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final svc      = context.read<FirestoreService>();
      final branches = await svc.getBranches(widget.business.id);
      if (mounted) {
        setState(() {
          _branches = branches;
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

  @override
  Widget build(BuildContext context) {
    final biz    = widget.business;
    final status = biz.subscriptionStatus;
    final isDue  = biz.isDueSoon(30);
    final displayStatus = isDue && status == AppConstants.statusActive
        ? 'due_soon'
        : status;
    final renewalStr = biz.renewalDate != null
        ? DateFormat('d MMM yyyy').format(biz.renewalDate!)
        : '—';
    final isPendingPayment = status == AppConstants.statusPendingPayment;

    return Scaffold(
      appBar: AppBar(
        title: Text(biz.brandName),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/business/${biz.id}/edit', extra: biz),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Change 3: Pending payment banner ─────────────────────────
          if (isPendingPayment)
            _PendingPaymentPanel(business: biz),

          if (isPendingPayment) const SizedBox(height: 16),

          // ── Business Summary Card ─────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        biz.brandName.isNotEmpty
                            ? biz.brandName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
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
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Category',
                  value: biz.categoryType.isEmpty ? '—' : biz.categoryType,
                ),
                _InfoRow(label: 'Owner email',  value: biz.ownerEmail ?? '—'),
                _InfoRow(label: 'Renewal date', value: renewalStr),
                _InfoRow(label: 'Business ID',  value: biz.id, mono: true),
                if (biz.isReassigned)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _ReassignedBanner(),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Branches ─────────────────────────────────────────────────
          Text(
            'Branches (${_branches.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

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
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading branches: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else if (_branches.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No branches found.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._branches.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _BranchCard(
                  branch: b,
                  businessId: biz.id,
                  // Standee UI only makes sense for activated businesses.
                  showStandeeControls: !isPendingPayment,
                ),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Change 3: Pending Payment Panel ──────────────────────────────────────────

class _PendingPaymentPanel extends StatefulWidget {
  final BusinessModel business;
  const _PendingPaymentPanel({required this.business});

  @override
  State<_PendingPaymentPanel> createState() => _PendingPaymentPanelState();
}

class _PendingPaymentPanelState extends State<_PendingPaymentPanel> {
  bool   _sending = false;
  String? _shortUrl;
  String? _error;

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
        content: Text('Payment link copied to clipboard'),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.payment_outlined, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Awaiting Payment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This business is enrolled but the owner has not yet paid the '
            '₹1999 setup fee. Use the button below to generate a fresh '
            'payment link and email it to ${widget.business.ownerEmail ?? "the owner"}.',
            style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
          ),
          const SizedBox(height: 12),

          // Action button
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _sending ? null : _resend,
                icon: _sending
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 16),
                label: Text(_sending ? 'Sending…' : 'Resend payment link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // Error
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text('Error: $_error',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],

          // Success: show link for WhatsApp / copy
          if (_shortUrl != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment link generated and emailed to owner ✅',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700)),
                  const SizedBox(height: 8),
                  // Link display
                  SelectableText(
                    _shortUrl!,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _copyLink,
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openLink,
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8)),
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
  final bool        showStandeeControls;

  const _BranchCard({
    required this.branch,
    required this.businessId,
    this.showStandeeControls = true,
  });

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  // Current standee status (may be updated locally on dropdown change).
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
      _standeeStatus    = newStatus;
      _standeeUpdating  = true;
    });
    try {
      await context.read<FirestoreService>().updateStandeeStatus(
            widget.businessId, widget.branch.id, newStatus);
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() => _standeeStatus = widget.branch.standeeStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update standee status: $e'),
            backgroundColor: Colors.red.shade700,
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
        setState(() {
          _qrLoading = false;
        });
        // Open in new tab for download.
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
              const Icon(Icons.storefront_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch.branchName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          _InfoRow(label: 'Address',  value: branch.address),
          _InfoRow(label: 'WhatsApp', value: branch.whatsappNumber),
          // Change 5: show who monitors the WhatsApp channel
          if (branch.whatsappMonitoredBy.isNotEmpty)
            _InfoRow(
              label: 'WA monitor',
              value: branch.whatsappMonitoredBy,
            ),
          if (branch.placeId != null && branch.placeId!.isNotEmpty)
            _InfoRow(label: 'Place ID', value: branch.placeId!, mono: true),
          if (branch.googleReviewLink != null &&
              branch.googleReviewLink!.isNotEmpty)
            _InfoRow(label: 'Review link', value: branch.googleReviewLink!),
          _InfoRow(label: 'Branch ID', value: branch.id, mono: true),

          const SizedBox(height: 16),

          // ── Change 1: Plain printable QR download ─────────────────────
          _PlainQrRow(
            plainQrStoragePath: branch.plainQrStoragePath,
            qrLoading:          _qrLoading,
            qrError:            _qrError,
            onDownload:         _downloadQr,
          ),

          const SizedBox(height: 12),

          // ── Change 2: Standee fulfillment status ──────────────────────
          if (widget.showStandeeControls)
            _StandeeStatusRow(
              currentStatus: _standeeStatus,
              updating:      _standeeUpdating,
              updatedAt:     branch.standeeStatusUpdatedAt,
              onChanged:     _onStandeeChanged,
            ),

          if (widget.showStandeeControls) const SizedBox(height: 16),

          // Star routing
          Text(
            'Star Routing',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _StarRoutingTable(config: branch.starRoutingConfig),
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
    return Row(
      children: [
        Icon(Icons.qr_code_2_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Printable QR',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              if (qrError != null)
                Text(qrError!,
                    style: const TextStyle(color: Colors.red, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          )
        else
          Tooltip(
            message: 'QR will be ready after payment is confirmed',
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    final label = AppConstants.standeeStatusLabels[currentStatus]
        ?? currentStatus;
    final updatedStr = updatedAt != null
        ? DateFormat('d MMM yyyy').format(updatedAt!)
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 16),
              const SizedBox(width: 6),
              const Text('Acrylic Standee',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (updating)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: currentStatus,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6)),
              label: const Text('Status'),
            ),
            items: AppConstants.standeeStatuses
                .map((s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(
                          AppConstants.standeeStatusLabels[s] ?? s),
                    ))
                .toList(),
            onChanged: updating ? null : onChanged,
          ),
          if (updatedStr != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Last updated: $updatedStr',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          // Current status label below dropdown for quick glance
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Current: $label',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _standeeColor(currentStatus)),
            ),
          ),
        ],
      ),
    );
  }

  Color _standeeColor(String status) {
    switch (status) {
      case AppConstants.standeeNotOrdered: return Colors.grey;
      case AppConstants.standeePrinted:    return const Color(0xFF3B82F6); // blue
      case AppConstants.standeeShipped:    return const Color(0xFFF59E0B); // amber
      case AppConstants.standeeDelivered:  return const Color(0xFF22C55E); // green
      default:                             return Colors.grey;
    }
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

  static const _colors = {
    'thankyou': Color(0xFF6B7280),
    'whatsapp': Color(0xFF25D366),
    'google':   Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (i) {
        final star  = '${i + 1}';
        final route = config[star] ?? '—';
        final label = _labels[route] ?? route;
        final icon  = _icons[route]  ?? Icons.help_outline;
        final color = _colors[route] ?? Colors.grey;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ...List.generate(
                i + 1,
                (_) => const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
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
    final color = AppTheme.statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
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
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This business has been reassigned to admin management.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          ],
        ),
      );
}
