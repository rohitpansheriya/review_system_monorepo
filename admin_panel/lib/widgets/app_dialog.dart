// lib/widgets/app_dialog.dart
//
// Modern reusable dialog container with header badge, rounded shape, and polished actions.

import 'package:flutter/material.dart';

class AppModalDialog extends StatelessWidget {
  final IconData? icon;
  final IconData? headerIcon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;

  const AppModalDialog({
    super.key,
    this.icon,
    this.headerIcon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.content,
    this.actions,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = iconColor ?? colorScheme.primary;
    final displayIcon = icon ?? headerIcon;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1.2),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row with Icon Badge
            Row(
              children: [
                if (displayIcon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(displayIcon, size: 20, color: primaryColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 15 : 17,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Content
            Flexible(
              child: SingleChildScrollView(
                child: content,
              ),
            ),

            // Actions
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

