// lib/screens/business_detail/business_phrases_editor_dialog.dart
//
// Review Phrases & 3-Step Guided Chips Editor for Business Management.
// Allows Platform Admin to customize 3-Step Guided Review Chips (Items, Highlights, Experience)
// from 50 Pre-Made Industry Dictionaries with live interactive smartphone simulator preview,
// bulk tools, and backward compatibility with classic phrase pools.

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/step_category_presets.dart';
import '../../core/string_utils.dart';
import '../../core/theme.dart';
import '../../models/business_model.dart';

class BusinessPhrasesEditorDialog extends StatefulWidget {
  final BusinessModel business;
  final VoidCallback? onSaved;

  const BusinessPhrasesEditorDialog({
    super.key,
    required this.business,
    this.onSaved,
  });

  static Future<bool?> show(BuildContext context, BusinessModel business) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BusinessPhrasesEditorDialog(business: business),
    );
  }

  @override
  State<BusinessPhrasesEditorDialog> createState() =>
      _BusinessPhrasesEditorDialogState();
}

enum _EditorMode { stepChips, legacyPhrases }

class _CategoryDraft {
  String name;
  List<String> phrasePool;
  Map<String, List<String>> translations;

  _CategoryDraft({
    required this.name,
    required List<String> phrasePool,
    Map<String, List<String>>? translations,
  })  : phrasePool = List<String>.from(phrasePool),
        translations = translations ?? {'hi': [], 'gu': []};

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'phrase_pool': phrasePool,
      'translations': translations,
    };
  }

  factory _CategoryDraft.fromMap(Map<String, dynamic> map) {
    final rawPool = map['phrase_pool'];
    final pool = <String>[];
    if (rawPool is List) {
      for (final p in rawPool) {
        if (p != null && p.toString().trim().isNotEmpty) {
          pool.add(p.toString().trim());
        }
      }
    }
    final rawTrans = map['translations'];
    final transMap = <String, List<String>>{'hi': [], 'gu': []};
    if (rawTrans is Map) {
      rawTrans.forEach((k, v) {
        if (v is List) {
          transMap[k.toString()] = v.map((e) => e.toString().trim()).toList();
        }
      });
    }

    return _CategoryDraft(
      name: map['name']?.toString() ?? 'Category',
      phrasePool: pool,
      translations: transMap,
    );
  }
}

class _BusinessPhrasesEditorDialogState
    extends State<BusinessPhrasesEditorDialog> with SingleTickerProviderStateMixin {
  _EditorMode _mode = _EditorMode.stepChips;
  late TabController _stepTabController;

  // ── 3-Step Chips State ─────────────────────────────────────────────────────
  final List<String> _step1Chips = [];
  final List<String> _step2Chips = [];
  final List<String> _step3Chips = [];
  final List<String> _negativeChips = [];
  final Map<String, List<String>> _serviceTags = {};
  String _selectedArchetype = 'food_dining';

  // Single chip input controllers for steps
  final TextEditingController _newStep1Ctrl = TextEditingController();
  final TextEditingController _newStep2Ctrl = TextEditingController();
  final TextEditingController _newStep3Ctrl = TextEditingController();
  final TextEditingController _newNegativeCtrl = TextEditingController();

  // ── Legacy Phrases State ───────────────────────────────────────────────────
  final List<_CategoryDraft> _categories = [];
  int _selectedCategoryIndex = 0;
  final TextEditingController _phraseSearchCtrl = TextEditingController();
  final TextEditingController _newPhraseCtrl = TextEditingController();

  // ── Live Simulator Preview State ───────────────────────────────────────────
  bool _showPreview = true;
  final Set<String> _simSelectedStep1 = {};
  final Set<String> _simSelectedStep2 = {};
  final Set<String> _simSelectedStep3 = {};
  String _simGeneratedReview = '';
  int _simSelectedStars = 5;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stepTabController = TabController(length: 4, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _stepTabController.dispose();
    _newStep1Ctrl.dispose();
    _newStep2Ctrl.dispose();
    _newStep3Ctrl.dispose();
    _newNegativeCtrl.dispose();
    _phraseSearchCtrl.dispose();
    _newPhraseCtrl.dispose();
    super.dispose();
  }

  void _initializeData() {
    // 1. Initialize 3-Step Chips & Negative Feedback Tags
    final detected = StepCategoryPresets.detectBestPreset(
      widget.business.categoryType,
      widget.business.defaultCategoryTemplateId,
    );

    if (widget.business.stepCategories != null && widget.business.hasStepCategories) {
      final s = widget.business.stepCategories!;
      _step1Chips.addAll(s['step1'] ?? []);
      _step2Chips.addAll(s['step2'] ?? []);
      _step3Chips.addAll(s['step3'] ?? []);
      _selectedArchetype = widget.business.archetype ?? detected.archetype;
      _mode = _EditorMode.stepChips;
    } else {
      _step1Chips.addAll(detected.step1);
      _step2Chips.addAll(detected.step2);
      _step3Chips.addAll(detected.step3);
      _selectedArchetype = detected.archetype;
      _mode = _EditorMode.stepChips;
    }

    // Populate service tags from existing services or detected preset
    if (widget.business.services != null && widget.business.services!.isNotEmpty) {
      for (final s in widget.business.services!) {
        final label = s['label']?.toString();
        final tags = s['tags'];
        if (label != null && tags is List) {
          _serviceTags[label] = tags.map((e) => e.toString()).toList();
        }
      }
    }
    for (final s in _step1Chips) {
      if (!_serviceTags.containsKey(s) || _serviceTags[s]!.isEmpty) {
        _serviceTags[s] = List<String>.from(
          detected.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: detected),
        );
      }
    }

    if (widget.business.negativeFeedbackChips != null && widget.business.negativeFeedbackChips!.isNotEmpty) {
      _negativeChips.addAll(widget.business.negativeFeedbackChips!);
    } else {
      _negativeChips.addAll(detected.negativeChips);
    }

    // 2. Initialize Legacy Categories
    if (widget.business.customCategories.isNotEmpty) {
      for (final catMap in widget.business.customCategories) {
        _categories.add(_CategoryDraft.fromMap(catMap));
      }
    } else {
      _categories.add(_CategoryDraft(
        name: 'General',
        phrasePool: [
          'Very pleasant and professional experience!',
          'Outstanding customer service and courteous staff.',
          'Super quick and hassle-free service.',
          'Extremely polite and helpful team members.',
          'Clean, organized, and very welcoming environment.',
          'Highly recommend to friends and family!',
        ],
      ));
    }

    _regenerateSimulatorReview();
  }

  int get _totalStepChipsCount =>
      _step1Chips.length + _step2Chips.length + _step3Chips.length;

  int get _totalLegacyPhrasesCount =>
      _categories.fold<int>(0, (tot, c) => tot + c.phrasePool.length);

  // ── Simulator Review Combinator Engine ─────────────────────────────────────
  void _regenerateSimulatorReview() {
    final s1List = _simSelectedStep1.map(StringUtils.stripLeadingEmoji).where((s) => s.isNotEmpty).toList();
    final s2List = _simSelectedStep2.map(StringUtils.stripLeadingEmoji).where((s) => s.isNotEmpty).toList();
    final s3List = _simSelectedStep3.map(StringUtils.stripLeadingEmoji).where((s) => s.isNotEmpty).toList();

    final s1 = s1List.isNotEmpty ? s1List.join(' & ') : null;
    final s2 = s2List.isNotEmpty ? s2List.join(' & ') : null;
    final s3 = s3List.isNotEmpty ? s3List.join(' & ') : null;

    final rand = math.Random();

    if (_selectedArchetype == 'beauty_wellness') {
      if (s1 != null && s2 != null && s3 != null) {
        final options = [
          'Got a $s1 done here today and the $s2 was exceptional! Really appreciated the $s3. Will definitely visit again!',
          'Booked a session for $s1 — $s2 exceeded my expectations. Very clean setup with $s3! 10/10!',
          'Had my $s1 styled here and the $s2 was top quality. Welcoming team and $s3. Highly recommended!',
        ];
        _simGeneratedReview = options[rand.nextInt(options.length)];
      } else if (s1 != null && s2 != null) {
        _simGeneratedReview = 'Got a $s1 done today and the $s2 was flawless! Really happy with the results.';
      } else if (s1 != null && s3 != null) {
        _simGeneratedReview = 'Had a relaxing session for $s1. The staff provided $s3. Will definitely be returning!';
      } else if (s2 != null && s3 != null) {
        _simGeneratedReview = 'Loved the $s2 and the wonderful $s3. Truly relaxing and refreshing! 10/10!';
      } else if (s1 != null) {
        _simGeneratedReview = 'Got a $s1 done here and had a great experience from start to finish. Highly recommended!';
      } else if (s2 != null) {
        _simGeneratedReview = 'The $s2 and overall precision were remarkable today. Great service!';
      } else if (s3 != null) {
        _simGeneratedReview = 'Super hospitable team with $s3. A very comfortable and pleasant visit!';
      } else {
        final r1 = _step1Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step1Chips.first) : 'Haircut';
        final r2 = _step2Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step2Chips.first) : 'Styling';
        final r3 = _step3Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step3Chips.first) : 'Service';
        _simGeneratedReview = 'Got a $r1 done here today and the $r2 was exceptional! Really appreciated the $r3. 10/10!';
      }
    } else if (_selectedArchetype == 'healthcare_clinic') {
      if (s1 != null && s2 != null && s3 != null) {
        final options = [
          'Visited the clinic for $s1 and was very impressed by the $s2. The doctor and $s3 made me feel completely comfortable.',
          'Consulted for $s1 — the $s2 gave immense relief. Highly professional environment and $s3! 10/10!',
          'Underwent $s1 with complete ease thanks to the $s2. Appreciated the clear guidance and $s3. Highly recommended!',
        ];
        _simGeneratedReview = options[rand.nextInt(options.length)];
      } else if (s1 != null && s2 != null) {
        _simGeneratedReview = 'Visited for $s1 and the $s2 was carried out with utmost care. Very reassuring!';
      } else if (s1 != null && s3 != null) {
        _simGeneratedReview = 'Smooth appointment for $s1. Really appreciated the $s3 throughout the visit.';
      } else if (s2 != null && s3 != null) {
        _simGeneratedReview = 'Very reassuring visit with $s2 and supportive $s3. 10/10 care!';
      } else if (s1 != null) {
        _simGeneratedReview = 'Visited for $s1 and received thorough, professional care. Highly recommended!';
      } else {
        final r1 = _step1Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step1Chips.first) : 'Treatment';
        final r2 = _step2Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step2Chips.first) : 'Diagnosis';
        final r3 = _step3Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step3Chips.first) : 'Care';
        _simGeneratedReview = 'Visited the clinic for $r1 and was very impressed by the $r2. The doctor and $r3 made me feel completely comfortable.';
      }
    } else if (_selectedArchetype == 'auto_services') {
      if (s1 != null && s2 != null && s3 != null) {
        final options = [
          'Brought my vehicle in for $s1 — the $s2 gave it a true showroom finish! Very professional work and $s3.',
          'Got my car\'s $s1 done here today and the $s2 was top tier. Quick turnaround with $s3! 10/10!',
          'Had an excellent experience with their $s1. Superb $s2 along with $s3. Highly recommended!',
        ];
        _simGeneratedReview = options[rand.nextInt(options.length)];
      } else if (s1 != null && s2 != null) {
        _simGeneratedReview = 'Brought my car in for $s1 and the $s2 exceeded my expectations. Flawless work!';
      } else if (s1 != null && s3 != null) {
        _simGeneratedReview = 'Got the $s1 done today with prompt handling and $s3. Highly recommended garage!';
      } else {
        final r1 = _step1Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step1Chips.first) : 'Service';
        final r2 = _step2Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step2Chips.first) : 'Finish';
        final r3 = _step3Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step3Chips.first) : 'Staff';
        _simGeneratedReview = 'Brought my vehicle in for $r1 — the $r2 gave it a true showroom finish! Very professional work and $r3.';
      }
    } else if (_selectedArchetype == 'retail_shopping') {
      if (s1 != null && s2 != null && s3 != null) {
        final options = [
          'Purchased a $s1 from here and the $s2 is unmatched! Great collection and $s3. 10/10!',
          'Bought the $s1 today — really loved the $s2. Smooth shopping experience with $s3!',
          'Wonderful range of products including their $s1. The $s2 was impressive, backed by $s3. Highly recommended!',
        ];
        _simGeneratedReview = options[rand.nextInt(options.length)];
      } else if (s1 != null && s2 != null) {
        _simGeneratedReview = 'Purchased a $s1 today and the $s2 is genuinely top-notch. Great store!';
      } else {
        final r1 = _step1Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step1Chips.first) : 'Collection';
        final r2 = _step2Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step2Chips.first) : 'Quality';
        final r3 = _step3Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step3Chips.first) : 'Hospitality';
        _simGeneratedReview = 'Purchased a $r1 from here and the $r2 is unmatched! Great collection and $r3. 10/10!';
      }
    } else {
      // Food & Dining default
      if (s1 != null && s2 != null && s3 != null) {
        final options = [
          'Tried their $s1 today and what really stood out was the $s2! $s3 made the experience even better. 10/10!',
          'Ordered the $s1 with friends — $s2 was exceptional. Paired with $s3, will definitely visit again!',
          'The $s1 here is freshly made and absolutely delicious, especially loved the $s2. Great hospitality with $s3!',
          'Had a wonderful time enjoying their $s1. You can really notice the $s2! Plus, the $s3 was on point. Highly recommended!',
        ];
        _simGeneratedReview = options[rand.nextInt(options.length)];
      } else if (s1 != null && s2 != null) {
        _simGeneratedReview = 'Tried their $s1 today and the $s2 was absolutely top-notch! Highly recommended.';
      } else if (s1 != null && s3 != null) {
        _simGeneratedReview = 'Had an amazing time trying their $s1. Super fast service and $s3! 10/10 recommendation.';
      } else if (s2 != null && s3 != null) {
        _simGeneratedReview = 'Wonderful food with $s2! Really enjoyed the visit thanks to the $s3. 5/5 stars!';
      } else if (s1 != null) {
        _simGeneratedReview = 'Tried their $s1 today and it was freshly prepared and delicious. Great spot to visit!';
      } else if (s2 != null) {
        _simGeneratedReview = 'The quality and $s2 were exceptional today! Absolutely loved the experience.';
      } else if (s3 != null) {
        _simGeneratedReview = 'Wonderful visit! Really appreciated the $s3 throughout our time here. Highly recommended!';
      } else {
        final r1 = _step1Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step1Chips.first) : 'Food';
        final r2 = _step2Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step2Chips.first) : 'Taste';
        final r3 = _step3Chips.isNotEmpty ? StringUtils.stripLeadingEmoji(_step3Chips.first) : 'Service';
        _simGeneratedReview = 'Tried their $r1 today and what really stood out was the $r2! $r3 made the experience even better. 10/10!';
      }
    }
  }

  // ── 1-Click Clone from 50 Industry Templates Dialog ────────────────────────
  void _showClonePresetDialog() {
    String selectedPresetId = 'food_pizzeria';
    String filterText = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final filteredPresets = StepCategoryPresets.all.where((p) {
            if (filterText.isEmpty) return true;
            return p.name.toLowerCase().contains(filterText.toLowerCase()) ||
                p.sector.toLowerCase().contains(filterText.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Clone from 50 Pre-Made Industry Templates'),
              ],
            ),
            content: SizedBox(
              width: 540,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select any of the 50 tailor-made industry dictionaries to instantly populate Step 1, Step 2, and Step 3 chips.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search templates (e.g. Pizza, Salon, Dentist, Detailing, Jewelry)...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setDlgState(() => filterText = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        itemCount: filteredPresets.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final preset = filteredPresets[i];
                          final isSel = preset.id == selectedPresetId;
                          return ListTile(
                            dense: true,
                            selected: isSel,
                            selectedTileColor: const Color(0xFFEFF6FF),
                            title: Text(
                              preset.name,
                              style: TextStyle(
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${preset.sector} • ${preset.step1.length + preset.step2.length + preset.step3.length} chips',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: isSel
                                ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () {
                              setDlgState(() => selectedPresetId = preset.id);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cloning will replace the current draft chips with the chosen template.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Clone Template'),
                onPressed: () {
                  final preset = StepCategoryPresets.findById(selectedPresetId) ??
                      StepCategoryPresets.all.first;

                  setState(() {
                    _step1Chips.clear();
                    _step2Chips.clear();
                    _step3Chips.clear();
                    _negativeChips.clear();
                    _serviceTags.clear();

                    _step1Chips.addAll(preset.step1);
                    _step2Chips.addAll(preset.step2);
                    _step3Chips.addAll(preset.step3);
                    _negativeChips.addAll(preset.negativeChips);
                    _selectedArchetype = preset.archetype;

                    for (final s in preset.step1) {
                      _serviceTags[s] = List<String>.from(
                        preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset),
                      );
                    }

                    _simSelectedStep1.clear();
                    _simSelectedStep2.clear();
                    _simSelectedStep3.clear();
                    _regenerateSimulatorReview();
                  });

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Cloned "${preset.name}" ($_totalStepChipsCount chips loaded).'),
                      backgroundColor: AppColors.activeFg,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Bulk Add Chips Dialog ──────────────────────────────────────────────────
  void _showBulkAddChipsDialog(int stepIndex) {
    final textCtrl = TextEditingController();
    final stepName = stepIndex == 0
        ? 'Step 1 (Items / Services)'
        : (stepIndex == 1 ? 'Step 2 (What Stood Out)' : 'Step 3 (Experience)');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.playlist_add_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Bulk Add to $stepName'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste a list of chips (one per line or comma-separated). Numbering and bullets will be cleaned automatically.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'e.g.\n1. 🍕 Pizza\n2. 🍔 Burger\n3. 🍝 Pasta\n4. ☕ Coffee',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final raw = textCtrl.text.trim();
              if (raw.isNotEmpty) {
                final cleaned = StringUtils.parseBulkPhrases(raw);
                if (cleaned.isNotEmpty) {
                  final formatted = cleaned
                      .map((c) => StringUtils.formatChipText(c, step: stepIndex + 1, archetype: _selectedArchetype))
                      .where((c) => c.isNotEmpty)
                      .toList();
                  setState(() {
                    final targetList = stepIndex == 0
                        ? _step1Chips
                        : (stepIndex == 1 ? _step2Chips : _step3Chips);
                    final preset = StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId);
                    for (final f in formatted) {
                      final cleanNew = StringUtils.stripLeadingEmoji(f).toLowerCase();
                      if (!targetList.any((item) => StringUtils.stripLeadingEmoji(item).toLowerCase() == cleanNew)) {
                        targetList.add(f);
                        if (stepIndex == 0) {
                          _serviceTags[f] = StepCategoryPresets.suggestTagsForService(f, currentPreset: preset);
                        }
                      }
                    }
                    _regenerateSimulatorReview();
                  });
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add Cleaned Chips'),
          ),
        ],
      ),
    );
  }

  // ── Save to Firestore ──────────────────────────────────────────────────────
  Future<void> _saveChanges() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.business.id);

      if (_mode == _EditorMode.stepChips) {
        final s1 = _step1Chips.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final s2 = _step2Chips.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final s3 = _step3Chips.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final stepMap = {
          'step1': s1,
          'step2': s2,
          'step3': s3,
        };

        final preset = StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId);
        final servicesList = s1.map((s) {
          final tags = _serviceTags[s] ?? preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset);
          return {
            'id': s.replaceAll(RegExp(r'^[^\w\s]+|\s+'), ' ').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
            'label': s,
            'tags': List<String>.from(tags),
          };
        }).toList();

        await docRef.set({
          'step_categories': stepMap,
          'services': servicesList,
          'negative_feedback_chips': _negativeChips.map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          'archetype': _selectedArchetype,
          'has_custom_phrases': true,
          'phrases_customized_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final legacyData = _categories.map((c) => c.toMap()).toList();
        await docRef.set({
          'custom_categories': legacyData,
          'has_custom_phrases': true,
          'phrases_customized_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        widget.onSaved?.call();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mode == _EditorMode.stepChips
                  ? '✅ Saved $_totalStepChipsCount 3-step chips & ${_negativeChips.length} private feedback tags successfully!'
                  : '✅ Saved ${_categories.length} categories ($_totalLegacyPhrasesCount phrases) successfully!',
            ),
            backgroundColor: AppColors.activeFg,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1200,
        height: 780,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildDialogHeader(),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  // Main Editor Area
                  Expanded(
                    flex: 6,
                    child: _mode == _EditorMode.stepChips
                        ? _build3StepChipsEditor()
                        : _buildLegacyPhrasePoolEditor(),
                  ),
                  if (_showPreview) ...[
                    const VerticalDivider(width: 1),
                    // Live Smartphone Simulator Preview
                    Expanded(
                      flex: 4,
                      child: _buildSmartphonePreviewPanel(),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Icon(Icons.rate_review_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Review Phrases & 3-Step Guided Chips Manager',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.business.displayCode,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.business.brandName,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Mode Toggle
          SegmentedButton<_EditorMode>(
            segments: const [
              ButtonSegment(
                value: _EditorMode.stepChips,
                label: Text('⚡ 3-Step Chips (Modern)'),
                icon: Icon(Icons.touch_app_rounded, size: 16),
              ),
              ButtonSegment(
                value: _EditorMode.legacyPhrases,
                label: Text('📂 Phrase Pools (Classic)'),
                icon: Icon(Icons.folder_outlined, size: 16),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (val) {
              setState(() => _mode = val.first);
            },
          ),
          const SizedBox(width: 12),
          // 1-Click Clone Button
          FilledButton.tonalIcon(
            onPressed: _showClonePresetDialog,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Clone 50 Templates'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _showPreview ? 'Hide Phone Simulator' : 'Show Phone Simulator',
            icon: Icon(
              _showPreview ? Icons.smartphone_rounded : Icons.smartphone_outlined,
              color: _showPreview ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () {
              setState(() => _showPreview = !_showPreview);
            },
          ),
        ],
      ),
    );
  }

  // ── 3-Step Guided Chips Editor View ────────────────────────────────────────
  Widget _build3StepChipsEditor() {
    return Column(
      children: [
        // Step Tabs
        Container(
          color: const Color(0xFFF1F5F9),
          child: TabBar(
            controller: _stepTabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: [
              Tab(text: '1. Offerings (${_step1Chips.length})'),
              Tab(text: '2. Highlights (${_step2Chips.length})'),
              Tab(text: '3. Experience (${_step3Chips.length})'),
              Tab(text: '⚠️ Private Feedback (${_negativeChips.length})'),
            ],
          ),
        ),
        // Archetype Picker Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              const Text('Industry Grammar Archetype: ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedArchetype,
                isDense: true,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'food_dining', child: Text('🍕 Food & Dining')),
                  DropdownMenuItem(value: 'beauty_wellness', child: Text('💇 Beauty & Wellness')),
                  DropdownMenuItem(value: 'healthcare_clinic', child: Text('🩺 Healthcare & Clinics')),
                  DropdownMenuItem(value: 'auto_services', child: Text('🚗 Auto & Detailing')),
                  DropdownMenuItem(value: 'retail_shopping', child: Text('🛍️ Retail & Shopping')),
                  DropdownMenuItem(value: 'it_services', child: Text('💻 IT & Tech Services')),
                  DropdownMenuItem(value: 'universal_general', child: Text('🌐 Universal & Professional')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedArchetype = val;
                      _regenerateSimulatorReview();
                    });
                  }
                },
              ),
              const Spacer(),
              Text(
                'Total: $_totalStepChipsCount interactive chips',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _stepTabController,
            children: [
              _buildStepChipsTab(0, _step1Chips, _newStep1Ctrl, 'e.g. 🍕 Wood-fired Pizza, ☕ Iced Latte, 🍔 Cheeseburger'),
              _buildStepChipsTab(1, _step2Chips, _newStep2Ctrl, 'e.g. 😋 Delicious Taste, 🔥 Fresh Ingredients, 🧀 Rich Cheese'),
              _buildStepChipsTab(2, _step3Chips, _newStep3Ctrl, 'e.g. ⚡ Fast Service, 😊 Friendly Staff, 🧼 Clean Ambience'),
              _buildStepChipsTab(3, _negativeChips, _newNegativeCtrl, 'e.g. ⏳ Long wait time, 👥 Staff behavior, 💰 Pricing surprise'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepChipsTab(
    int stepIdx,
    List<String> chips,
    TextEditingController newCtrl,
    String placeholder,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Offerings helper tip
          if (stepIdx == 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap any offering chip below to preview and customize its 5–8 positive experience tags.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // Add Chip Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: newCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: placeholder,
                    isDense: true,
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (val) {
                    final text = val.trim();
                    if (text.isNotEmpty) {
                      final formatted = StringUtils.formatChipText(
                        text,
                        step: stepIdx + 1,
                        archetype: _selectedArchetype,
                      );
                      if (formatted.isNotEmpty) {
                        setState(() {
                          final cleanNew = StringUtils.stripLeadingEmoji(formatted).toLowerCase();
                          final exists = chips.any(
                            (item) => StringUtils.stripLeadingEmoji(item).toLowerCase() == cleanNew,
                          );
                          if (!exists) {
                            chips.add(formatted);
                            if (stepIdx == 0) {
                              final preset = StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId);
                              _serviceTags[formatted] = StepCategoryPresets.suggestTagsForService(formatted, currentPreset: preset);
                            }
                          }
                          newCtrl.clear();
                          _regenerateSimulatorReview();
                        });
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Chip'),
                onPressed: () {
                  final text = newCtrl.text.trim();
                  if (text.isNotEmpty) {
                    final formatted = StringUtils.formatChipText(
                      text,
                      step: stepIdx + 1,
                      archetype: _selectedArchetype,
                    );
                    if (formatted.isNotEmpty) {
                      setState(() {
                        final cleanNew = StringUtils.stripLeadingEmoji(formatted).toLowerCase();
                        final exists = chips.any(
                          (item) => StringUtils.stripLeadingEmoji(item).toLowerCase() == cleanNew,
                        );
                        if (!exists) {
                          chips.add(formatted);
                          if (stepIdx == 0) {
                            final preset = StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId);
                            _serviceTags[formatted] = StepCategoryPresets.suggestTagsForService(formatted, currentPreset: preset);
                          }
                        }
                        newCtrl.clear();
                        _regenerateSimulatorReview();
                      });
                    }
                  }
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.playlist_add_rounded, size: 16),
                label: const Text('Bulk Paste'),
                onPressed: () => _showBulkAddChipsDialog(stepIdx),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Chip List
          Expanded(
            child: chips.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_outlined, size: 40, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        const Text('No chips added yet for this step.', style: TextStyle(color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _showClonePresetDialog,
                          child: const Text('Clone from 50 Presets'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips.map((chipText) {
                        if (stepIdx == 0) {
                          final tags = _serviceTags[chipText] ??
                              StepCategoryPresets.suggestTagsForService(
                                chipText,
                                currentPreset: StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId),
                              );
                          return InkWell(
                            onTap: () => _showServiceTagsModal(chipText),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    chipText,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.sell_outlined, size: 11, color: AppColors.primary),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${tags.length} tags',
                                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => _openRenameChipDialog(stepIdx, chipText),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(Icons.edit_outlined, size: 14, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        chips.remove(chipText);
                                        _serviceTags.remove(chipText);
                                        _simSelectedStep1.remove(chipText);
                                        _regenerateSimulatorReview();
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(Icons.close, size: 15, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Chip(
                          label: Text(chipText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          backgroundColor: const Color(0xFFF1F5F9),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              chips.remove(chipText);
                              _simSelectedStep1.remove(chipText);
                              _simSelectedStep2.remove(chipText);
                              _simSelectedStep3.remove(chipText);
                              _regenerateSimulatorReview();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showServiceTagsModal(String serviceLabel) {
    final currentTags = List<String>.from(
      _serviceTags[serviceLabel] ??
          StepCategoryPresets.suggestTagsForService(
            serviceLabel,
            currentPreset: StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId),
          ),
    );

    showDialog(
      context: context,
      builder: (ctx) => _PhrasesServiceTagsModal(
        serviceLabel: serviceLabel,
        initialTags: currentTags,
        categoryType: widget.business.categoryType,
        templateId: widget.business.defaultCategoryTemplateId,
        onSaved: (newTags) {
          setState(() {
            _serviceTags[serviceLabel] = List<String>.from(newTags);
          });
        },
      ),
    );
  }

  void _openRenameChipDialog(int stepIdx, String oldChip) {
    final ctrl = TextEditingController(text: oldChip);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Chip Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Chip Label', border: OutlineInputBorder()),
          onSubmitted: (_) {
            _saveRenamedChip(ctx, stepIdx, oldChip, ctrl.text.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => _saveRenamedChip(ctx, stepIdx, oldChip, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveRenamedChip(BuildContext ctx, int stepIdx, String oldChip, String newText) {
    if (newText.isEmpty || newText == oldChip) {
      Navigator.pop(ctx);
      return;
    }
    final formatted = StringUtils.formatChipText(newText, step: stepIdx + 1, archetype: _selectedArchetype);
    setState(() {
      if (stepIdx == 0) {
        final tags = List<String>.from(_serviceTags[oldChip] ?? []);
        _step1Chips.remove(oldChip);
        _serviceTags.remove(oldChip);
        _step1Chips.add(formatted);
        _serviceTags[formatted] = tags.isNotEmpty
            ? tags
            : StepCategoryPresets.suggestTagsForService(
                formatted,
                currentPreset: StepCategoryPresets.detectBestPreset(widget.business.categoryType, widget.business.defaultCategoryTemplateId),
              );
      } else if (stepIdx == 1) {
        _step2Chips.remove(oldChip);
        _step2Chips.add(formatted);
      } else if (stepIdx == 2) {
        _step3Chips.remove(oldChip);
        _step3Chips.add(formatted);
      } else if (stepIdx == 3) {
        _negativeChips.remove(oldChip);
        _negativeChips.add(formatted);
      }
      _regenerateSimulatorReview();
    });
    Navigator.pop(ctx);
  }

  // ── Legacy Phrase Pools Editor View ────────────────────────────────────────
  Widget _buildLegacyPhrasePoolEditor() {
    final cur = _selectedCategoryIndex >= 0 && _selectedCategoryIndex < _categories.length
        ? _categories[_selectedCategoryIndex]
        : null;

    return Row(
      children: [
        // Category Sidebar
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Categories', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 20),
                      onPressed: () {
                        setState(() {
                          _categories.add(_CategoryDraft(name: 'Category ${_categories.length + 1}', phrasePool: []));
                          _selectedCategoryIndex = _categories.length - 1;
                        });
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categories[i];
                    final isSel = i == _selectedCategoryIndex;
                    return ListTile(
                      dense: true,
                      selected: isSel,
                      selectedTileColor: const Color(0xFFEFF6FF),
                      title: Text(cat.name, style: TextStyle(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${cat.phrasePool.length} phrases', style: const TextStyle(fontSize: 11)),
                      trailing: _categories.length > 1
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () {
                                setState(() {
                                  _categories.removeAt(i);
                                  if (_selectedCategoryIndex >= _categories.length) {
                                    _selectedCategoryIndex = _categories.length - 1;
                                  }
                                });
                              },
                            )
                          : null,
                      onTap: () {
                        setState(() => _selectedCategoryIndex = i);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Phrases List for Selected Category
        Expanded(
          child: cur == null
              ? const Center(child: Text('No category selected'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newPhraseCtrl,
                              decoration: InputDecoration(
                                hintText: 'Add a new phrase for "${cur.name}"...',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onSubmitted: (val) {
                                final text = val.trim();
                                if (text.isNotEmpty) {
                                  setState(() {
                                    cur.phrasePool.add(text);
                                    _newPhraseCtrl.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final text = _newPhraseCtrl.text.trim();
                              if (text.isNotEmpty) {
                                setState(() {
                                  cur.phrasePool.add(text);
                                  _newPhraseCtrl.clear();
                                });
                              }
                            },
                            child: const Text('Add Phrase'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Phrases (${cur.phrasePool.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: cur.phrasePool.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            return ListTile(
                              dense: true,
                              title: Text(cur.phrasePool[i]),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16),
                                onPressed: () {
                                  setState(() => cur.phrasePool.removeAt(i));
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Live Smartphone Simulator Preview Panel ────────────────────────────────
  Widget _buildSmartphonePreviewPanel() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.smartphone_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Live Interactive Simulator', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Re-roll Review',
                onPressed: () {
                  setState(() => _regenerateSimulatorReview());
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header band
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            widget.business.brandName.isNotEmpty
                                ? widget.business.brandName[0].toUpperCase()
                                : 'B',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.business.brandName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Rating Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0B1528), Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Thank you for visiting!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (i) {
                              final starVal = i + 1;
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _simSelectedStars = starVal;
                                    _regenerateSimulatorReview();
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(
                                    Icons.star_rounded,
                                    size: 26,
                                    color: starVal <= _simSelectedStars ? const Color(0xFFFBBF24) : Colors.white24,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 3-Step Interactive Chips in Simulator
                    if (_mode == _EditorMode.stepChips) ...[
                      // Step 1
                      _buildSimStepGroup('1. What did you get/have?', _step1Chips, _simSelectedStep1),
                      const SizedBox(height: 8),
                      // Step 2
                      _buildSimStepGroup('2. What stood out?', _step2Chips, _simSelectedStep2),
                      const SizedBox(height: 8),
                      // Step 3
                      _buildSimStepGroup('3. How was your visit?', _step3Chips, _simSelectedStep3),
                      const SizedBox(height: 10),
                    ],
                    // Generated Review Box
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('✨ Generated Review', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              InkWell(
                                onTap: () {
                                  setState(() => _regenerateSimulatorReview());
                                },
                                child: const Row(
                                  children: [
                                    Icon(Icons.refresh, size: 14, color: Color(0xFF64748B)),
                                    SizedBox(width: 2),
                                    Text('Shuffle', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _simGeneratedReview,
                            style: const TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Google Maps Button
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFF1557D0)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Copy & Post to Google', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimStepGroup(String title, List<String> chips, Set<String> selectedSet) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: chips.take(6).map((chipText) {
            final isSel = selectedSet.contains(chipText);
            return InkWell(
              onTap: () {
                setState(() {
                  if (isSel) {
                    selectedSet.remove(chipText);
                  } else {
                    selectedSet.add(chipText);
                  }
                  _regenerateSimulatorReview();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  gradient: isSel
                      ? const LinearGradient(colors: [Color(0xFF0F274A), Color(0xFF1E40AF)])
                      : null,
                  color: isSel ? null : const Color(0xFFF1F5F9),
                  border: Border.all(color: isSel ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  chipText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    color: isSel ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildDialogFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_error != null)
            Expanded(
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            )
          else
            Expanded(
              child: Text(
                _mode == _EditorMode.stepChips
                    ? 'Active Mode: 3-Step Guided Chips ($_totalStepChipsCount total chips)'
                    : 'Active Mode: Classic Phrase Pools (${_categories.length} categories, $_totalLegacyPhrasesCount phrases)',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _saveChanges,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(_saving ? 'Saving...' : 'Save Custom Phrases'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Tags Preview & Editor Modal for Phrases Editor
// ─────────────────────────────────────────────────────────────────────────────

class _PhrasesServiceTagsModal extends StatefulWidget {
  final String serviceLabel;
  final List<String> initialTags;
  final String categoryType;
  final String? templateId;
  final ValueChanged<List<String>> onSaved;

  const _PhrasesServiceTagsModal({
    required this.serviceLabel,
    required this.initialTags,
    required this.categoryType,
    required this.templateId,
    required this.onSaved,
  });

  @override
  State<_PhrasesServiceTagsModal> createState() => _PhrasesServiceTagsModalState();
}

class _PhrasesServiceTagsModalState extends State<_PhrasesServiceTagsModal> {
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
    final preset = StepCategoryPresets.detectBestPreset(widget.categoryType, widget.templateId);
    final suggested = StepCategoryPresets.suggestTagsForService(widget.serviceLabel, currentPreset: preset);
    setState(() {
      _tags = List<String>.from(suggested);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    color: const Color(0xFFEFF6FF),
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
                          color: Color(0xFF0F172A),
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
            const Text(
              'When customers select this offering on the review page, these positive tags will appear for 1-tap positive review creation.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
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
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
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
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _tags.isEmpty
                    ? const Center(
                        child: Text(
                          'No tags yet. Click "Smart Suggestions" or add custom tags above.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
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
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
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

