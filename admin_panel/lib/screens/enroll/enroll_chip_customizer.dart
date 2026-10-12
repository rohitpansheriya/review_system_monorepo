// lib/screens/enroll/enroll_chip_customizer.dart
//
// Interactive chip customizer widget used directly within EnrollScreen.
// Allows admin/employee to customize hero products/services and their positive tags,
// standout highlights, and experience chips right during business enrollment.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/step_category_presets.dart';
import '../../core/string_utils.dart';
import '../../core/theme.dart';
import '../../providers/enroll_provider.dart';

class EnrollChipCustomizer extends StatefulWidget {
  const EnrollChipCustomizer({super.key});

  @override
  State<EnrollChipCustomizer> createState() => _EnrollChipCustomizerState();
}

class _EnrollChipCustomizerState extends State<EnrollChipCustomizer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _addCtrl = TextEditingController();
  final FocusNode _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addCtrl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _handleAddChip(EnrollProvider enroll) {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    final currentStep = _tabController.index + 1;
    enroll.addChip(currentStep, text);
    _addCtrl.clear();
    _addFocus.requestFocus();

    if (currentStep == 1 && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ Added offering. Tap the chip or tag badge to preview/edit its suggested tags.'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openTagsEditor(BuildContext context, EnrollProvider enroll, String serviceLabel) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ServiceTagsEditorModal(
        serviceLabel: serviceLabel,
        initialTags: enroll.getTagsForService(serviceLabel),
        onSaved: (newTags) {
          enroll.updateTagsForService(serviceLabel, newTags);
        },
        onResetToSuggestions: () {
          enroll.resetTagsForService(serviceLabel);
        },
      ),
    );
  }

  void _openRenameChipDialog(BuildContext context, EnrollProvider enroll, int step, String oldChip) {
    final ctrl = TextEditingController(text: oldChip);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Chip Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Chip Label',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            _saveRenamedChip(ctx, enroll, step, oldChip, ctrl.text.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _saveRenamedChip(ctx, enroll, step, oldChip, ctrl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveRenamedChip(BuildContext ctx, EnrollProvider enroll, int step, String oldChip, String newText) {
    if (newText.isEmpty || newText == oldChip) {
      Navigator.pop(ctx);
      return;
    }
    final formatted = step == 4
        ? newText
        : StringUtils.formatChipText(newText, step: step, archetype: enroll.archetype);
    
    if (step == 1) {
      final tags = enroll.getTagsForService(oldChip);
      enroll.removeChip(1, oldChip);
      enroll.addChip(1, formatted);
      enroll.updateTagsForService(formatted, tags);
    } else {
      enroll.removeChip(step, oldChip);
      enroll.addChip(step, formatted);
    }
    Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollProvider>();
    final scheme = Theme.of(context).colorScheme;

    final currentStep = _tabController.index + 1;
    final currentList = currentStep == 1
        ? enroll.step1Chips
        : (currentStep == 2
            ? enroll.step2Chips
            : (currentStep == 3 ? enroll.step3Chips : enroll.negativeFeedbackChips));

    final stepHints = [
      'e.g., 🍕 Wood-fired Pizza, ☕ Cold Brew, 💆 Balayage Hair Spa',
      'e.g., 🧀 Rich Cheese Pull, ⚡ Fast Turnaround, 😋 Authentic Taste',
      'e.g., ✨ Cozy Vibe, 😊 Attentive Staff, 🧼 Hygienic Seating',
      'e.g., ⏳ Long wait time, 👥 Staff behavior, 💰 Pricing surprise',
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: enroll.isChipsCustomized
              ? AppColors.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: enroll.isChipsCustomized ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Review Offerings & Chips',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (enroll.isChipsCustomized) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Customized',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Customize offerings & their positive tags, plus 1-tap review chips & private feedback tags.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enroll.isChipsCustomized)
                  TextButton.icon(
                    onPressed: () => enroll.resetChipsToPreset(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Tab Navigation Bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: [
              Tab(text: '1. Offerings & Tags (${enroll.step1Chips.length})'),
              Tab(text: '2. Highlights (${enroll.step2Chips.length})'),
              Tab(text: '3. Experience (${enroll.step3Chips.length})'),
              Tab(text: '⚠️ Private Feedback (${enroll.negativeFeedbackChips.length})'),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Offerings Helper Tip
                if (currentStep == 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tap any offering chip below to preview or customize its 5–8 positive experience tags.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Quick Add Input Box
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addCtrl,
                        focusNode: _addFocus,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: stepHints[_tabController.index],
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          prefixIcon: const Icon(Icons.add, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) => _handleAddChip(enroll),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => _handleAddChip(enroll),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.md),

                // Chip Cloud Area
                if (currentList.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Center(
                      child: Text(
                        'No chips added for this step. Type above and click Add.',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentList.map((chipText) {
                      if (currentStep == 1) {
                        final tagCount = enroll.getTagsForService(chipText).length;
                        return InkWell(
                          onTap: () => _openTagsEditor(context, enroll, chipText),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  chipText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sell_outlined, size: 11, color: AppColors.primary),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$tagCount tags',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => _openRenameChipDialog(context, enroll, 1, chipText),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                InkWell(
                                  onTap: () => enroll.removeChip(1, chipText),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.close,
                                      size: 15,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Chip(
                        label: Text(
                          chipText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => enroll.removeChip(currentStep, chipText),
                        backgroundColor: scheme.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Tags Preview & Editor Modal Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceTagsEditorModal extends StatefulWidget {
  final String serviceLabel;
  final List<String> initialTags;
  final ValueChanged<List<String>> onSaved;
  final VoidCallback onResetToSuggestions;

  const _ServiceTagsEditorModal({
    required this.serviceLabel,
    required this.initialTags,
    required this.onSaved,
    required this.onResetToSuggestions,
  });

  @override
  State<_ServiceTagsEditorModal> createState() => _ServiceTagsEditorModalState();
}

class _ServiceTagsEditorModalState extends State<_ServiceTagsEditorModal> {
  late List<String> _tags;
  final TextEditingController _tagInputCtrl = TextEditingController();
  final FocusNode _tagFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _tagInputCtrl.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  void _handleAddTag() {
    final text = _tagInputCtrl.text.trim();
    if (text.isEmpty) return;
    final formatted = StringUtils.formatChipText(text, step: 2);
    if (formatted.isNotEmpty && !_tags.contains(formatted)) {
      setState(() {
        _tags.add(formatted);
      });
      _tagInputCtrl.clear();
      _tagFocusNode.requestFocus();
    }
  }

  void _handleReset() {
    widget.onResetToSuggestions();
    final suggested = StepCategoryPresets.suggestTagsForService(widget.serviceLabel);
    setState(() {
      _tags = List<String>.from(suggested);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sell_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customize Positive Experience Tags',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.serviceLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              'When customers select "${widget.serviceLabel}" on the review page, these positive tags will appear for quick 1-tap review creation.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),

            const SizedBox(height: 16),

            // Tag Add Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputCtrl,
                    focusNode: _tagFocusNode,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add positive tag (e.g. 🧀 Rich Flavors, ⚡ Fast Service)...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _handleAddTag(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _handleAddTag,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Tag'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tags Container
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Tags (${_tags.length}):',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _handleReset,
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('Smart Suggestions', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: _tags.isEmpty
                    ? Center(
                        child: Text(
                          'No tags yet. Click "Smart Suggestions" or add custom tags above.',
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tags.map((t) {
                            return Chip(
                              label: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                              deleteIcon: const Icon(Icons.close, size: 15),
                              onDeleted: () {
                                setState(() {
                                  _tags.remove(t);
                                });
                              },
                              backgroundColor: scheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Save Tags'),
                  onPressed: () {
                    widget.onSaved(_tags);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
