// lib/screens/admin/admin_templates_tab.dart
//
// Category Template Library Tab for Platform Admin (Doc 04 / Doc 07).
// Lazy loads category phrase pools on demand when a category is expanded/clicked.
// Hides v2/v3 pool versions behind AppConstants.enableMultiplePoolVersions (defaults to v1).
// Pure Firestore updates — zero code deployment needed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminTemplatesTab extends StatefulWidget {
  const AdminTemplatesTab({super.key});

  @override
  State<AdminTemplatesTab> createState() => _AdminTemplatesTabState();
}

class _AdminTemplatesTabState extends State<AdminTemplatesTab> {
  String? _selectedTemplateId;

  void _showCreateTemplateDialog(
    BuildContext context,
    AdminDashboardProvider provider,
  ) {
    final idCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final catCtrl = TextEditingController();
    final phraseCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Category Template'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Template ID',
                    hintText: 'e.g. bakery_v1 or fitness_v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Business Type Label',
                    hintText: 'e.g. Bakery / Confectionery',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(
                    labelText: 'First Category Name',
                    hintText: 'e.g. Taste & Freshness',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phraseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Initial Review Phrase Variant',
                    hintText: 'e.g. Freshly baked goods and amazing cakes!',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (idCtrl.text.trim().isEmpty ||
                  typeCtrl.text.trim().isEmpty ||
                  catCtrl.text.trim().isEmpty ||
                  phraseCtrl.text.trim().isEmpty) {
                return;
              }

              Navigator.of(ctx).pop();
              await provider.createCategoryTemplate(
                templateId: idCtrl.text.trim(),
                businessType: typeCtrl.text.trim(),
                categoryName: catCtrl.text.trim(),
                initialPhrase: phraseCtrl.text.trim(),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category template created successfully!')),
                );
              }
            },
            child: const Text('Create Template'),
          ),
        ],
      ),
    );
  }

  void _showAddPhraseDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName, {
    String poolVersion = AppConstants.defaultPoolVersion,
  }) {
    final phraseCtrl = TextEditingController();
    final title = AppConstants.enableMultiplePoolVersions
        ? 'Add Phrase to $categoryName ($poolVersion)'
        : 'Add Phrase to $categoryName';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
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

    // Get list of category names (lazy loaded header)
    final categoryNames = (currentTemplate['category_names'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        (currentTemplate['categories'] as List?)
            ?.map((c) => (c is Map) ? (c['name'] as String? ?? '') : '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];

    final templateId = currentTemplate['id'] as String;

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
                    'Manage review phrase pools. Pure Firestore updates — zero code deployment needed.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Template Selector & Create Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Select Industry Template: ',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
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
              ElevatedButton.icon(
                onPressed: () => _showCreateTemplateDialog(context, provider),
                icon: const Icon(Icons.add),
                label: const Text('Create New Template'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Categories & Lazy-Loaded Phrase Pools
          if (categoryNames.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'No categories defined for this template yet.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categoryNames.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final catName = categoryNames[index];
                return _buildCategoryExpansionCard(
                  context,
                  provider,
                  templateId,
                  catName,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryExpansionCard(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String catName,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final version = AppConstants.defaultPoolVersion;
    final isPhrasesLoading = provider.isCategoryPhrasesLoading(templateId, catName, version: version);
    final phrases = provider.getCachedCategoryPhrases(templateId, catName, version: version);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (expanded) {
            if (expanded && phrases == null && !isPhrasesLoading) {
              provider.fetchCategoryPhrases(
                templateId: templateId,
                categoryName: catName,
                version: version,
              );
            }
          },
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(Icons.category_outlined, color: colorScheme.primary, size: 20),
          ),
          title: Text(
            catName,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            phrases != null
                ? '${phrases.length} phrase variant(s)'
                : 'Click to load & edit phrase pool',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppConstants.enableMultiplePoolVersions
                            ? 'Pool Version: $version'
                            : 'Review Phrase Pool',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showAddPhraseDialog(
                          context,
                          provider,
                          templateId,
                          catName,
                          poolVersion: version,
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Phrase Variant'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isPhrasesLoading)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (phrases == null || phrases.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No phrase variants in this pool yet. Click "Add Phrase Variant" to add one.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    )
                  else
                    _buildPhraseChips(
                      context,
                      provider,
                      templateId,
                      catName,
                      version,
                      phrases,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhraseChips(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName,
    String poolVersion,
    List<String> phrases,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

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
