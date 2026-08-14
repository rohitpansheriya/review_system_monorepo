// lib/screens/owner/owner_categories_tab.dart
//
// Category Management Tab for Business Owner.
// Displays assigned category template and permits toggling active categories.
//
// SUBSCRIPTION GATING:
// If subscription_status is grace_period or deleted, this screen renders in
// READ-ONLY mode with a "renew to edit" banner.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/owner_dashboard_provider.dart';

class OwnerCategoriesTab extends StatelessWidget {
  const OwnerCategoriesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final biz = provider.business;
    final template = provider.assignedTemplate;

    if (biz == null || template == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final categories = (template['categories'] as List?) ?? [];
    final activeMap = biz.activeCategories;
    final isReadOnly = provider.isGracePeriod || provider.isDeleted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Read-only Grace Period Banner ──────────────────────────────
          if (isReadOnly)
            Card(
              color: colorScheme.errorContainer,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.error),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock, color: colorScheme.onErrorContainer, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Category editing is READ-ONLY during Grace Period. Renew your subscription to modify active categories.',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Text(
            'Category Management',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toggle customer review categories active for ${biz.brandName}. (Phrase pools are managed by platform admins).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── 2. Assigned Template Info Card ────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: _buildTemplateCard(context, template),
          ),

          const SizedBox(height: 24),

          // ── 3. Category Toggle List ────────────────────────────────────────
          Text(
            'Active Review Categories',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final cat = categories[index] as Map<String, dynamic>;
              final catName = cat['name'] as String? ?? 'Category ${index + 1}';
              final phrases = (cat['phrase_pool'] as List?) ?? [];
              final isActive = activeMap[catName] ?? true;

              return Card(
                elevation: 0,
                color: isActive
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isActive
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: SwitchListTile(
                  title: Text(
                    catName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  subtitle: Text(
                    '${phrases.length} phrase variants in pool',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isActive,
                  onChanged: isReadOnly
                      ? null // Disabled in grace period / read-only
                      : (val) async {
                          try {
                            await provider.toggleCategory(catName, val);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Updated category "$catName" -> ${val ? "Active" : "Disabled"}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (err) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${err.toString()}'),
                                  backgroundColor: colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, Map<String, dynamic> template) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bizType = template['business_type'] ?? 'Standard';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.category_outlined, color: colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned Template: $bizType',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Template ID: ${template['id'] ?? 'ice_cream_v1'} • Admin maintained',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
