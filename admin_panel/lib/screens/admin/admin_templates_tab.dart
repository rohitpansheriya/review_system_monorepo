// lib/screens/admin/admin_templates_tab.dart
//
// Category Template Library CRUD Tab for Platform Admin (Doc 04 / Doc 07).
// Allows full CRUD on phrase pools & versions (v1, v2, v3) without code deploys.
// Surface is English-only (translations stay dormant behind ENABLE_TRANSLATIONS flag).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminTemplatesTab extends StatefulWidget {
  const AdminTemplatesTab({super.key});

  @override
  State<AdminTemplatesTab> createState() => _AdminTemplatesTabState();
}

class _AdminTemplatesTabState extends State<AdminTemplatesTab> {
  String? _selectedTemplateId;

  void _showAddPhraseDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName,
    String poolVersion,
  ) {
    final phraseCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Phrase to $categoryName ($poolVersion)'),
        content: TextField(
          controller: phraseCtrl,
          decoration: const InputDecoration(
            labelText: 'New Phrase Variant',
            hintText: 'e.g. Friendly staff and fast service!',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (phraseCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              await provider.addPhraseVariant(
                templateId: templateId,
                categoryName: categoryName,
                poolVersion: poolVersion,
                language: 'en',
                phrase: phraseCtrl.text.trim(),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Phrase variant added successfully (takes effect immediately).')),
                );
              }
            },
            child: const Text('Add Variant'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final templates = provider.templates;

    if (templates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    _selectedTemplateId ??= templates.first['id'] as String?;

    final currentTemplate = templates.firstWhere(
      (t) => t['id'] == _selectedTemplateId,
      orElse: () => templates.first,
    );

    final categories = (currentTemplate['categories'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category Template Library (Doc 07 CRUD)',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage review phrase pools & pool versions (v1, v2, v3). Pure Firestore updates — zero code deployment needed.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Template Selector
          Row(
            children: [
              Text('Select Industry Template: ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: currentTemplate['id'] as String?,
                items: templates
                    .map((t) => DropdownMenuItem<String>(
                          value: t['id'] as String,
                          child: Text('${t['business_type']} (${t['id']})'),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTemplateId = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Categories & Phrase Pools
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final cat = categories[index] as Map<String, dynamic>;
              final catName = cat['name'] as String? ?? 'Category ${index + 1}';
              final versions = (cat['phrase_pool_versions'] as Map<String, dynamic>?) ?? {
                'v1': cat['phrase_pool'] as List? ?? [],
              };

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            catName,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Chip(
                            label: Text('${versions.length} Pool Version(s)'),
                            backgroundColor: colorScheme.primaryContainer,
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      for (final versionKey in versions.keys) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pool Version: $versionKey',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showAddPhraseDialog(
                                context,
                                provider,
                                currentTemplate['id'] as String,
                                catName,
                                versionKey,
                              ),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Phrase Variant'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildPhraseList(
                          context,
                          provider,
                          currentTemplate['id'] as String,
                          catName,
                          versionKey,
                          List<String>.from(versions[versionKey] ?? []),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseList(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName,
    String poolVersion,
    List<String> phrases,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (phrases.isEmpty) {
      return const Text('No phrase variants in this pool version.');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(phrases.length, (idx) {
        final phrase = phrases[idx];
        return Chip(
          label: Text('"$phrase"'),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () async {
            await provider.retirePhraseVariant(
              templateId: templateId,
              categoryName: categoryName,
              poolVersion: poolVersion,
              language: 'en',
              index: idx,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Phrase variant retired.')),
              );
            }
          },
          backgroundColor: colorScheme.surfaceContainerHigh,
        );
      }),
    );
  }
}
