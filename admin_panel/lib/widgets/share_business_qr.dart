// lib/widgets/share_business_qr.dart
//
// Shared "Share review QR & link" widget used on BOTH the admin and employee
// business detail screens. Shows only for ACTIVATED businesses (status == active).
//
// Features:
//   1. Send review link via WhatsApp (owner number + WA manager number)
//   2. Download plain functional QR PNG
//   3. Copy review link to clipboard
//
// Domain: appnexa.co.in (hardcoded per product requirement)

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/branch_model.dart';
import '../core/standee_generator.dart';

/// Hardcoded review domain per product requirement.
const String _kReviewDomain = 'appnexa.co.in';

/// Shared widget for sharing the review QR code and link with the business owner.
///
/// This widget is reused in both admin and employee panels.
/// It only displays for activated businesses (branches with QR generated).
class ShareBusinessQr extends StatefulWidget {
  final BranchModel branch;
  final String? ownerPhone;
  final String? businessName;
  final String? logoUrl;

  const ShareBusinessQr({
    super.key,
    required this.branch,
    this.ownerPhone,
    this.businessName,
    this.logoUrl,
  });

  @override
  State<ShareBusinessQr> createState() => _ShareBusinessQrState();
}

class _ShareBusinessQrState extends State<ShareBusinessQr> {
  bool _qrDownloading = false;
  String? _qrError;
  bool _linkCopied = false;

  /// The review URL: dynamic in emulator/localhost, or https://appnexa.co.in/r/{businessId}/{branchId}
  String get _reviewUrl {
    try {
      final host = html.window.location.host;
      if (host.contains('localhost') || host.contains('127.0.0.1')) {
        final origin = html.window.location.origin;
        return '$origin/r/${widget.branch.businessId}/${widget.branch.id}';
      }
    } catch (_) {}
    return 'https://$_kReviewDomain/r/${widget.branch.businessId}/${widget.branch.id}';
  }

  /// Formats a phone number for wa.me: strips '+', ensures starts with '91'.
  String _waNumber(String phone) {
    var num = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (num.startsWith('0')) num = num.substring(1);
    if (!num.startsWith('91') && num.length == 10) num = '91$num';
    return num;
  }

  /// Opens wa.me with a pre-filled message containing the review link.
  void _sendWhatsApp(String phoneNumber) {
    final waNum = _waNumber(phoneNumber);
    final message = Uri.encodeComponent(
      'Here is your AppNexa review QR link:\n$_reviewUrl\n\n'
      'Share this link with your customers to collect Google reviews!',
    );
    final url = 'https://wa.me/$waNum?text=$message';
    html.window.open(url, '_blank');
  }

  /// Downloads the 4×6 print-ready standee PNG matching appnexa.co.in acrylic design.
  Future<void> _downloadStandee() async {
    setState(() {
      _qrDownloading = true;
      _qrError = null;
    });
    try {
      await StandeeGenerator.downloadStandeePng(
        businessName: widget.businessName ?? 'Business',
        branchName: widget.branch.branchName,
        reviewUrl: _reviewUrl,
        logoUrl: widget.logoUrl,
      );
      if (mounted) {
        setState(() => _qrDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('4×6 Standee downloaded successfully!'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _qrError = 'Download failed: $e';
          _qrDownloading = false;
        });
      }
    }
  }

  /// Downloads plain QR code PNG.
  void _downloadPlainQr() {
    StandeeGenerator.downloadPlainQrPng(
      businessName: widget.businessName ?? 'Business',
      branchName: widget.branch.branchName,
      reviewUrl: _reviewUrl,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Plain QR code downloaded!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Copies the review URL to clipboard.
  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _reviewUrl));
    if (mounted) {
      setState(() => _linkCopied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review link copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _linkCopied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.branch;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Only show for activated branches (QR generated)
    final isActivated = branch.qrCodeId != null || branch.plainQrStoragePath != null;
    if (!isActivated) return const SizedBox.shrink();

    final ownerPhone = widget.ownerPhone;
    final managerPhone = branch.whatsappMonitoredBy;
    final branchWhatsapp = branch.whatsappNumber;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.share_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Share Review QR & Link',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Review URL display
          SelectableText(
            _reviewUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons — wrapped for mobile
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 1. Copy Link
              _ActionChip(
                icon: _linkCopied ? Icons.check : Icons.copy_outlined,
                label: _linkCopied ? 'Copied!' : 'Copy Link',
                onTap: _copyLink,
                scheme: scheme,
              ),

              // 2. Download 4×6 Standee
              if (branch.qrCodeId != null || branch.plainQrStoragePath != null || branch.isActive) ...[
                _ActionChip(
                  icon: Icons.photo_size_select_actual_outlined,
                  label: _qrDownloading ? 'Generating…' : 'Download 4×6 Standee',
                  onTap: _qrDownloading ? null : _downloadStandee,
                  scheme: scheme,
                ),
                _ActionChip(
                  icon: Icons.qr_code_2_outlined,
                  label: 'Plain QR',
                  onTap: _downloadPlainQr,
                  scheme: scheme,
                ),
              ],

              // 3. WhatsApp — Owner phone
              if (ownerPhone != null && ownerPhone.isNotEmpty)
                _ActionChip(
                  icon: Icons.chat_outlined,
                  label: 'WA Owner',
                  onTap: () => _sendWhatsApp(ownerPhone),
                  scheme: scheme,
                  isWhatsApp: true,
                ),

              // 4. WhatsApp — Branch WA number
              if (branchWhatsapp.isNotEmpty && branchWhatsapp != ownerPhone)
                _ActionChip(
                  icon: Icons.chat_outlined,
                  label: 'WA Branch',
                  onTap: () => _sendWhatsApp(branchWhatsapp),
                  scheme: scheme,
                  isWhatsApp: true,
                ),

              // 5. WhatsApp — Manager number (if different)
              if (managerPhone.isNotEmpty &&
                  managerPhone != ownerPhone &&
                  managerPhone != branchWhatsapp)
                _ActionChip(
                  icon: Icons.chat_outlined,
                  label: 'WA Manager',
                  onTap: () => _sendWhatsApp(managerPhone),
                  scheme: scheme,
                  isWhatsApp: true,
                ),
            ],
          ),

          // Error display
          if (_qrError != null) ...[
            const SizedBox(height: 8),
            Text(
              _qrError!,
              style: TextStyle(color: scheme.error, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small styled action chip for the share panel.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ColorScheme scheme;
  final bool isWhatsApp;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.scheme,
    this.isWhatsApp = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isWhatsApp
        ? const Color(0xFF25D366).withValues(alpha: 0.15)
        : scheme.surfaceContainerHighest;
    final fgColor = isWhatsApp
        ? const Color(0xFF25D366)
        : scheme.primary;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
