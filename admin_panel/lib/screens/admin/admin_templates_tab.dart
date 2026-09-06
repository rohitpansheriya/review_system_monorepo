// lib/screens/admin/admin_templates_tab.dart
//
// Category Template Library Tab for Platform Admin (Doc 04 / Doc 07).
// Lazy loads category phrase pools on demand when a category is expanded/clicked.
// Hides v2/v3 pool versions behind AppConstants.enableMultiplePoolVersions (defaults to v1).
// Pure Firestore updates — zero code deployment needed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/string_utils.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminTemplatesTab extends StatefulWidget {
  const AdminTemplatesTab({super.key});

  @override
  State<AdminTemplatesTab> createState() => _AdminTemplatesTabState();
}

class _AdminTemplatesTabState extends State<AdminTemplatesTab> {
  String? _selectedTemplateId;

  // ── Create New Template Dialog (With Bulk Phrases) ─────────────────────────
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final detectedPhrases = StringUtils.parseBulkPhrases(phraseCtrl.text);
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            title: const Text('Create New Category Template'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: idCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Template ID *',
                        hintText: 'e.g. bakery_v1 or fitness_v1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Business Type Label *',
                        hintText: 'e.g. Bakery / Confectionery',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: catCtrl,
                      decoration: const InputDecoration(
                        labelText: 'First Category Name *',
                        hintText: 'e.g. Taste & Quality',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Review Phrases (Paste all at once):',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (detectedPhrases.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '✨ ${detectedPhrases.length} phrases detected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phraseCtrl,
                      minLines: 4,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        hintText: 'Paste phrases here (one per line, numbered list, or separated by semicolons)\n\ne.g.\n1. Freshly baked cakes!\n2. Great taste and hygiene\n3. Value for money',
                        helperText: 'System automatically cleans numbering, bullets, and separates each phrase.',
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    if (detectedPhrases.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: detectedPhrases.map((p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final phrases = StringUtils.parseBulkPhrases(phraseCtrl.text);
                  if (idCtrl.text.trim().isEmpty ||
                      typeCtrl.text.trim().isEmpty ||
                      catCtrl.text.trim().isEmpty ||
                      phrases.isEmpty) {
                    return;
                  }

                  Navigator.of(ctx).pop();
                  await provider.createCategoryTemplate(
                    templateId: idCtrl.text.trim(),
                    businessType: typeCtrl.text.trim(),
                    categoryName: catCtrl.text.trim(),
                    phrases: phrases,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Category template created with ${phrases.length} phrases!')),
                    );
                  }
                },
                child: Text(detectedPhrases.length > 1
                    ? 'Create Template (${detectedPhrases.length} Phrases)'
                    : 'Create Template'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Add New Category Dialog (With Bulk Phrases) ────────────────────────────
  void _showAddCategoryDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
  ) {
    final catCtrl = TextEditingController();
    final phraseCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final detectedPhrases = StringUtils.parseBulkPhrases(phraseCtrl.text);
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            title: const Text('Add New Category & Phrases'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: catCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Category Name *',
                        hintText: 'e.g. Cleanliness & Ambience, Staff & Service',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Review Phrases (Paste all at once):',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (detectedPhrases.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '✨ ${detectedPhrases.length} phrases detected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phraseCtrl,
                      minLines: 4,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        hintText: 'Paste multiple phrases here (one per line, numbered list, or separated by semicolons)\n\ne.g.\n- Very clean and sanitized place\n- Pleasant atmosphere with soothing music\n- Cozy seating arrangement',
                        helperText: 'System automatically cleans numbering, bullets, and separates each phrase.',
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    if (detectedPhrases.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: detectedPhrases.map((p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final phrases = StringUtils.parseBulkPhrases(phraseCtrl.text);
                  if (catCtrl.text.trim().isEmpty || phrases.isEmpty) return;

                  Navigator.of(ctx).pop();
                  await provider.addCategory(
                    templateId: templateId,
                    categoryName: catCtrl.text.trim(),
                    phrases: phrases,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Category "${catCtrl.text.trim()}" added with ${phrases.length} phrase(s)!')),
                    );
                  }
                },
                child: Text(detectedPhrases.length > 1
                    ? 'Add Category (${detectedPhrases.length} Phrases)'
                    : 'Add Category'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Bulk Add Phrases Dialog (Paste All at Once) ────────────────────────────
  void _showAddPhraseDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName, {
    String poolVersion = AppConstants.defaultPoolVersion,
  }) {
    final phraseCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final detectedPhrases = StringUtils.parseBulkPhrases(phraseCtrl.text);
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return AlertDialog(
            title: Text('Paste Phrases to "$categoryName"'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Review Phrases:',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (detectedPhrases.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '✨ ${detectedPhrases.length} phrases detected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phraseCtrl,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Paste all phrases at once (one per line, numbered list, or separated by semicolons)\n\ne.g.\n1. Friendly staff and fast service!\n2. Extremely polite and helpful team\n3. Quick turnaround and great support',
                        helperText: 'System automatically parses and divides each phrase in real time.',
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    if (detectedPhrases.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Preview of Divided Phrases:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: detectedPhrases.map((p) => Chip(
                          label: Text('"$p"', style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.playlist_add_check, size: 18),
                onPressed: detectedPhrases.isEmpty
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        await provider.addPhrasesBulk(
                          templateId: templateId,
                          categoryName: categoryName,
                          poolVersion: poolVersion,
                          language: 'en',
                          phrases: detectedPhrases,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added ${detectedPhrases.length} phrase(s) to $categoryName!')),
                          );
                        }
                      },
                label: Text(detectedPhrases.length > 1
                    ? 'Add ${detectedPhrases.length} Phrases'
                    : 'Add Phrase'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Delete Category Confirmation Dialog ────────────────────────────────────
  void _showDeleteCategoryDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String templateId,
    String categoryName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$categoryName"?'),
        content: Text('Are you sure you want to remove the category "$categoryName" and all its phrase variants from this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.deleteCategory(
                templateId: templateId,
                categoryName: categoryName,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Category "$categoryName" removed.')),
                );
              }
            },
            child: const Text('Delete Category'),
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

    final editorSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category Template Library',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage review phrase pools and categories for each industry.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Template Selector & Action Buttons
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Industry Template: ',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
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
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _showAddCategoryDialog(context, provider, templateId),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add Category & Phrases'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showCreateTemplateDialog(context, provider),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create New Template'),
                ),
              ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No categories defined for this template yet.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showAddCategoryDialog(context, provider, templateId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Category'),
                    ),
                  ],
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
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: editorSection,
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
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: colorScheme.error.withValues(alpha: 0.8),
            tooltip: 'Delete Category',
            onPressed: () => _showDeleteCategoryDialog(context, provider, templateId, catName),
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
                      FilledButton.icon(
                        onPressed: () => _showAddPhraseDialog(
                          context,
                          provider,
                          templateId,
                          catName,
                          poolVersion: version,
                        ),
                        icon: const Icon(Icons.content_paste_go_rounded, size: 16),
                        label: const Text('Paste & Add Phrases'),
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
