// lib/widgets/app_fulfillment_stepper.dart
//
// Modern, responsive visual milestone stepper for Standee fulfillment tracking.
// Steps: Ordered ➔ Printed ➔ Shipped ➔ Delivered.
// Supports interactive step updates, completed tick states, and compact responsive layouts.

import 'package:flutter/material.dart';
import '../core/constants.dart';

class AppFulfillmentStepper extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String>? onStepSelected;
  final bool isInteractive;
  final bool compact;

  const AppFulfillmentStepper({
    super.key,
    required this.currentStatus,
    this.onStepSelected,
    this.isInteractive = false,
    this.compact = false,
  });

  static const List<({String key, String label, IconData icon, Color activeColor})> _steps = [
    (
      key: AppConstants.standeeOrdered,
      label: 'Ordered',
      icon: Icons.shopping_bag_outlined,
      activeColor: Color(0xFFF59E0B), // Amber
    ),
    (
      key: AppConstants.standeePrinted,
      label: 'Printed',
      icon: Icons.print_outlined,
      activeColor: Color(0xFF2563EB), // Blue
    ),
    (
      key: AppConstants.standeeShipped,
      label: 'Shipped',
      icon: Icons.local_shipping_outlined,
      activeColor: Color(0xFF7C3AED), // Purple
    ),
    (
      key: AppConstants.standeeDelivered,
      label: 'Delivered',
      icon: Icons.verified_rounded,
      activeColor: Color(0xFF10B981), // Emerald
    ),
  ];

  int _statusToIndex(String status) {
    final idx = _steps.indexWhere((s) => s.key == status);
    return idx != -1 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentIdx = _statusToIndex(currentStatus);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_steps.length * 2 - 1, (index) {
            // Even indices are Step Nodes, Odd indices are Connecting Lines
            if (index.isOdd) {
              final stepBeforeIdx = index ~/ 2;
              final isPassed = stepBeforeIdx < currentIdx;

              return Expanded(
                child: Container(
                  height: 3,
                  margin: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
                  decoration: BoxDecoration(
                    color: isPassed
                        ? const Color(0xFF10B981) // Completed green connection
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }

            final stepIdx = index ~/ 2;
            final step = _steps[stepIdx];
            final isCompleted = stepIdx < currentIdx;
            final isCurrent = stepIdx == currentIdx;

            // Determine node visuals
            Color nodeBg;
            Color nodeBorder;
            Color iconColor;
            Widget iconChild;

            if (isCompleted) {
              nodeBg = const Color(0xFF10B981);
              nodeBorder = const Color(0xFF10B981);
              iconColor = Colors.white;
              iconChild = Icon(Icons.check_rounded, size: compact ? 14 : 16, color: iconColor);
            } else if (isCurrent) {
              nodeBg = step.activeColor.withValues(alpha: 0.12);
              nodeBorder = step.activeColor;
              iconColor = step.activeColor;
              iconChild = Icon(step.icon, size: compact ? 14 : 16, color: iconColor);
            } else {
              nodeBg = colorScheme.surfaceContainerLowest;
              nodeBorder = colorScheme.outlineVariant;
              iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
              iconChild = Icon(step.icon, size: compact ? 14 : 16, color: iconColor);
            }

            final nodeWidget = InkWell(
              onTap: (isInteractive && onStepSelected != null)
                  ? () => onStepSelected!(step.key)
                  : null,
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 28 : 34,
                      height: compact ? 28 : 34,
                      decoration: BoxDecoration(
                        color: nodeBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: nodeBorder,
                          width: isCurrent ? 2.0 : 1.2,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: step.activeColor.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(child: iconChild),
                    ),
                    if (!isNarrow || isCurrent) ...[
                      const SizedBox(height: 5),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          fontWeight: isCurrent ? FontWeight.w700 : (isCompleted ? FontWeight.w600 : FontWeight.w500),
                          color: isCurrent
                              ? step.activeColor
                              : (isCompleted
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            );

            return nodeWidget;
          }),
        );
      },
    );
  }
}
