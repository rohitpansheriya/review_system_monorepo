// lib/widgets/app_badge.dart
//
// Reusable, modern SaaS status pill and badge component.
// Features:
//   - Consistent rounded pill shape with soft pastel background, crisp text, and delicate border.
//   - Optional status dot indicator or icon.
//   - Dedicated constructors for Subscription, Standee fulfillment, KYC, Inbound Leads,
//     Commission payouts, Business Codes, and Branch counters.

import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';

class AppBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final IconData? icon;
  final bool showDot;
  final Color? dotColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final TextStyle? customTextStyle;
  final VoidCallback? onTap;

  const AppBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.icon,
    this.showDot = false,
    this.dotColor,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
    this.borderRadius,
    this.customTextStyle,
    this.onTap,
  });

  // ── 1. Subscription Status Badge ─────────────────────────────────────────────
  factory AppBadge.subscription(
    String status, {
    Key? key,
    String? customLabel,
    bool showDot = true,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
  }) {
    final bg = AppTheme.statusColor(status);
    final fg = AppTheme.statusForeground(status);
    final label = customLabel ?? AppTheme.statusLabel(status);

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.25),
      showDot: showDot,
      dotColor: fg,
      fontSize: fontSize,
      padding: padding,
    );
  }

  // ── 2. Standee Fulfillment Status Badge ─────────────────────────────────────
  factory AppBadge.standee(
    String status, {
    Key? key,
    String? customLabel,
    bool showDot = true,
    IconData? icon,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
  }) {
    final safeStatus = AppConstants.standeeStatuses.contains(status)
        ? status
        : AppConstants.standeeOrdered;
    final bg = AppTheme.standeeStatusColor(safeStatus);
    final fg = AppTheme.standeeStatusForeground(safeStatus);
    final label = customLabel ?? (AppConstants.standeeStatusLabels[safeStatus] ?? safeStatus);

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.25),
      icon: icon,
      showDot: showDot && icon == null,
      dotColor: fg,
      fontSize: fontSize,
      padding: padding,
    );
  }

  // ── 3. KYC Verification Badge ───────────────────────────────────────────────
  factory AppBadge.kyc(
    String status, {
    Key? key,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
  }) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'verified':
        bg = AppColors.activeBg;
        fg = AppColors.activeFg;
        label = 'KYC Verified';
        icon = Icons.verified_user_rounded;
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'KYC Rejected';
        icon = Icons.gpp_bad_rounded;
        break;
      case 'pending':
      default:
        bg = AppColors.pendingBg;
        fg = AppColors.pendingFg;
        label = 'KYC Pending';
        icon = Icons.pending_actions_rounded;
        break;
    }

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.25),
      icon: icon,
      fontSize: fontSize,
      padding: padding,
    );
  }

  // ── 4. Inbound Lead Status Badge ────────────────────────────────────────────
  factory AppBadge.lead(
    String status, {
    Key? key,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
  }) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'lead':
        bg = const Color(0xFFFEE2E2); // red-100
        fg = const Color(0xFFDC2626); // red-600
        label = 'New Lead';
        break;
      case 'contacted':
        bg = AppColors.pendingBg;
        fg = AppColors.pendingFg;
        label = 'Contacted';
        break;
      case 'converted':
        bg = AppColors.activeBg;
        fg = AppColors.activeFg;
        label = 'Converted';
        break;
      case 'archived':
      default:
        bg = AppColors.deletedBg;
        fg = AppColors.deletedFg;
        label = 'Archived';
        break;
    }

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.25),
      showDot: true,
      dotColor: fg,
      fontSize: fontSize,
      padding: padding,
    );
  }

  // ── 5. Commission Status Badge ──────────────────────────────────────────────
  factory AppBadge.commission(
    String status, {
    Key? key,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
  }) {
    final isPaid = status.toLowerCase() == 'paid';
    final bg = isPaid ? AppColors.commPaidBg : AppColors.commPendingBg;
    final fg = isPaid ? AppColors.commPaidFg : AppColors.commPendingFg;
    final label = isPaid ? 'PAID' : 'PENDING';
    final icon = isPaid ? Icons.check_circle_rounded : Icons.schedule_rounded;

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.25),
      icon: icon,
      fontSize: fontSize,
      padding: padding,
    );
  }

  // ── 6. Business Code / Test Account Badge ────────────────────────────────────
  factory AppBadge.code(
    String code, {
    Key? key,
    bool isTest = false,
    String? prefix,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
  }) {
    final fg = isTest ? AppColors.warning : AppColors.primary;
    final bg = isTest ? AppColors.warning.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.09);
    final text = prefix != null ? '$prefix: $code' : code;

    return AppBadge(
      key: key,
      label: text,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      fontSize: fontSize,
      padding: padding,
      customTextStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: fg,
        letterSpacing: 0.3,
      ),
    );
  }

  // ── 7. Count / Counter Badge ────────────────────────────────────────────────
  factory AppBadge.count({
    Key? key,
    required String label,
    required Color color,
    Color? backgroundColor,
    IconData? icon,
    double fontSize = 11,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
  }) {
    final bg = backgroundColor ?? color.withValues(alpha: 0.12);

    return AppBadge(
      key: key,
      label: label,
      backgroundColor: bg,
      foregroundColor: color,
      borderColor: color.withValues(alpha: 0.25),
      icon: icon,
      fontSize: fontSize,
      padding: padding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(AppRadius.full);
    final textStyle = customTextStyle ??
        TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
          letterSpacing: 0.2,
        );

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: effectiveRadius,
        border: Border.all(
          color: borderColor ?? foregroundColor.withValues(alpha: 0.2),
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor ?? foregroundColor,
              ),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: foregroundColor),
            const SizedBox(width: 4.5),
          ],
          Flexible(
            child: Text(
              label,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: effectiveRadius,
        child: content,
      );
    }

    return content;
  }
}
