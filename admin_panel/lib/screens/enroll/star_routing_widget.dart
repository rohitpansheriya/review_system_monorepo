// lib/screens/enroll/star_routing_widget.dart
// Renders 5 rows (one per star) with a required dropdown each.
// Operates on a BranchDraft directly — no longer reads from EnrollProvider —
// so it can be used independently inside BranchFormWidget for any branch.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';

class StarRoutingWidget extends StatelessWidget {
  final BranchDraft draft;
  /// Called when any star routing value changes.
  final VoidCallback onChanged;
  /// true when submit was attempted and some stars are still unset.
  final bool showError;

  const StarRoutingWidget({
    super.key,
    required this.draft,
    required this.onChanged,
    this.showError = false,
  });

  static const _options = [
    (value: AppConstants.routingThankyou, label: 'Thank-you only',   icon: Icons.favorite_border),
    (value: AppConstants.routingWhatsapp, label: 'WhatsApp message', icon: Icons.chat_bubble_outline),
    (value: AppConstants.routingGoogle,   label: 'Google review',    icon: Icons.star_border_outlined),
  ];

  static const _starLabels = ['★', '★★', '★★★', '★★★★', '★★★★★'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Star routing (required)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ask the business owner what action to take for each rating.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),

        ...List.generate(5, (i) {
          final star     = '${i + 1}';
          final current  = draft.starRouting[star];
          final hasError = showError && (current == null || current.isEmpty);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                  SizedBox(
                  width: 60,
                  child: Text(
                    _starLabels[i],
                    style: TextStyle(
                      fontSize: 16,
                      color: hasError ? scheme.error : AppColors.star,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: current,
                    hint: const Text('Select action'),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                      errorText: hasError ? 'Required' : null,
                    ),
                    items: _options
                        .map((opt) => DropdownMenuItem(
                              value: opt.value,
                              child: Row(
                                children: [
                                  Icon(opt.icon, size: 16,
                                      color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text(opt.label),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        draft.setStarRoute(star, v);
                        onChanged();
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        }),

        if (showError && !draft.starRoutingComplete)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Please set routing for all 5 stars.',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
