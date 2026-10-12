// lib/screens/business_detail/business_edit_screen.dart
//
// Inline edit of an enrolled business's detail fields.
// Reuses BranchFormWidget (from enrollment) for branch editing — no fork.
//
// EDITABLE (employee):
//   Business: brand_name, logo_url, category_type, default_category_template_id,
//             owner_name, owner_email, owner_phone
//   Branch:   branch_name, address, whatsapp_number, whatsapp_monitored_by,
//             place_id, star_routing_config, category_override_id, standee_status
//
// NOT EDITABLE (payment/lifecycle owned):
//   subscription_status, renewal_date, grace_period_ends,
//   enrolled_by, enrolled_by_original, owner_auth_uid,
//   qr_code_id, nfc_tag_id (generated on activation)
//
// BUG FIXES (this version):
//   Bug 1 — On validation failure, FocusNode.requestFocus() + Scrollable.ensureVisible()
//            on the first invalid field so the user is taken to the problem.
//   Bug 2 — Logo upload control always rendered (whether logo_url is set or not).
//            Uses the same ImagePickerWeb + dart:ui dimension-check pattern as enroll.
//   Bug 3 — After save, calls MyBusinessesProvider.replaceLocal(updatedModel) BEFORE
//            navigating, so the list and any cached detail view update instantly.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_web/image_picker_web.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/image_utils.dart';
import '../../core/phone_field.dart';
import '../../core/step_category_presets.dart';
import '../../core/string_utils.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../models/employee_profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_empty_state.dart';
import '../enroll/branch_form_widget.dart';
import 'business_phrases_editor_dialog.dart';

class BusinessEditScreen extends StatefulWidget {
  final BusinessModel business;
  const BusinessEditScreen({super.key, required this.business});

  @override
  State<BusinessEditScreen> createState() => _BusinessEditScreenState();
}

class _BusinessEditScreenState extends State<BusinessEditScreen>
    with SingleTickerProviderStateMixin {
  // ── Scroll controller (Bug 1) ────────────────────────────────────────────
  final _scrollCtrl = ScrollController();

  // ── Form controllers ─────────────────────────────────────────────────────
  final _formKey        = GlobalKey<FormState>();
  late final TextEditingController _brandNameCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _ownerEmailCtrl;
  String _ownerPhoneE164 = '';

  // ── FocusNodes (Bug 1) ───────────────────────────────────────────────────
  final _brandNameFocus  = FocusNode();
  final _ownerNameFocus  = FocusNode();
  final _ownerEmailFocus = FocusNode();

  // ── Template / category ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _templates = [];
  bool   _templatesLoading = true;
  String _selectedCategoryType = '';
  String? _selectedTemplateId;
  String? _selectedArchetype;
  String _reviewLanguagePreference = 'english';

  // ── 3-Step Guided Review & Negative Chips State ─────────────────────────
  late TabController _tabController;
  final TextEditingController _addChipCtrl = TextEditingController();
  final FocusNode _addChipFocus = FocusNode();
  final List<String> _step1Chips = [];
  final List<String> _step2Chips = [];
  final List<String> _step3Chips = [];
  final List<String> _negativeChips = [];
  bool _isChipsCustomized = false;

  // ── Enrolled by employee (admin edit) ────────────────────────────────────
  List<EmployeeProfileModel> _employees = [];
  String _selectedEnrolledBy = 'admin';

  // ── Logo — Bug 2: always rendered, upload wired via StorageService ────────
  String     _logoUrl          = '';
  Uint8List? _logoBytes;
  String?    _logoMimeType;
  bool       _logoUploading    = false;
  String?    _logoRejection;   // dimension / decode error message

  // ── Branches ─────────────────────────────────────────────────────────────
  List<BranchDraft> _branchDrafts = [];
  List<String>      _branchIds    = [];
  bool   _branchesLoading = true;
  bool   _showErrors      = false;

  // ── Save ─────────────────────────────────────────────────────────────────
  bool    _saving    = false;
  String? _saveError;
  String? _ownerEmailError;
  String? _ownerNameError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    final biz = widget.business;
    _brandNameCtrl            = TextEditingController(text: biz.brandName);
    _ownerNameCtrl            = TextEditingController(text: biz.ownerName  ?? '');
    _ownerEmailCtrl           = TextEditingController(text: biz.ownerEmail ?? '');
    _ownerPhoneE164           = biz.ownerPhone ?? '';
    _selectedCategoryType     = biz.categoryType;
    _selectedTemplateId       = biz.defaultCategoryTemplateId;
    _selectedArchetype        = biz.archetype;
    _selectedEnrolledBy       = biz.enrolledBy.isEmpty ? 'admin' : biz.enrolledBy;
    _reviewLanguagePreference = biz.reviewLanguagePreference;
    _logoUrl                  = biz.logoUrl;

    if (biz.stepCategories != null && biz.hasStepCategories) {
      _step1Chips.addAll(biz.stepCategories!['step1'] ?? []);
      _step2Chips.addAll(biz.stepCategories!['step2'] ?? []);
      _step3Chips.addAll(biz.stepCategories!['step3'] ?? []);
      _selectedArchetype = biz.archetype ?? 'food_dining';
      _isChipsCustomized = biz.hasCustomPhrases;
    } else {
      final preset = StepCategoryPresets.detectBestPreset(biz.categoryType, biz.defaultCategoryTemplateId);
      _step1Chips.addAll(preset.step1);
      _step2Chips.addAll(preset.step2);
      _step3Chips.addAll(preset.step3);
      _selectedArchetype = preset.archetype;
      _isChipsCustomized = false;
    }

    if (biz.negativeFeedbackChips != null && biz.negativeFeedbackChips!.isNotEmpty) {
      _negativeChips.addAll(biz.negativeFeedbackChips!);
    } else {
      final preset = StepCategoryPresets.detectBestPreset(biz.categoryType, biz.defaultCategoryTemplateId);
      _negativeChips.addAll(preset.negativeChips);
    }

    final svc = context.read<FirestoreService>();
    final cached = svc.getCachedBranches(biz.id);
    if (cached != null && cached.isNotEmpty) {
      _branchIds       = cached.map((b) => b.id).toList();
      _branchDrafts    = cached.map(_branchToDraft).toList();
      _branchesLoading = false;
    }

    _loadTemplates();
    _loadEmployees();
    _loadBranches();
  }

  Future<void> _loadEmployees() async {
    final svc = context.read<FirestoreService>();
    final emps = await svc.getEmployeesList();
    if (!mounted) return;
    setState(() {
      _employees = emps;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addChipCtrl.dispose();
    _addChipFocus.dispose();
    _scrollCtrl.dispose();
    _brandNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _brandNameFocus.dispose();
    _ownerNameFocus.dispose();
    _ownerEmailFocus.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadTemplates() async {
    final svc       = context.read<FirestoreService>();
    final templates = await svc.getCategoryTemplates();
    if (!mounted) return;
    setState(() {
      _templates        = templates;
      _templatesLoading = false;

      // 1. Match by ID if present
      String? foundId;
      if (_selectedTemplateId != null && _selectedTemplateId!.isNotEmpty) {
        final match = templates.where((t) => t['id'] == _selectedTemplateId);
        if (match.isNotEmpty) {
          foundId = match.first['id'] as String?;
          _selectedCategoryType = match.first['business_type'] as String? ??
              match.first['name'] as String? ??
              _selectedCategoryType;
        }
      }

      // 2. Match by category name
      if (foundId == null && _selectedCategoryType.isNotEmpty) {
        final match = templates.where((t) {
          final bType = (t['business_type'] as String? ?? '').toLowerCase();
          final name = (t['name'] as String? ?? '').toLowerCase();
          final target = _selectedCategoryType.toLowerCase();
          return bType == target || name == target;
        });
        if (match.isNotEmpty) {
          foundId = match.first['id'] as String?;
        }
      }

      // 3. Fallback to best preset detection
      if (foundId == null) {
        final detected = StepCategoryPresets.detectBestPreset(
          _selectedCategoryType,
          widget.business.defaultCategoryTemplateId,
        );
        final match = templates.where((t) => t['id'] == detected.id);
        if (match.isNotEmpty) {
          foundId = match.first['id'] as String?;
        }
      }

      _selectedTemplateId = foundId;
    });
  }

  void _applyCategoryPreset(String catType, String? tId) {
    setState(() {
      _selectedCategoryType = catType;
      _selectedTemplateId = tId;
      final preset = StepCategoryPresets.detectBestPreset(catType, tId);
      _selectedArchetype = preset.archetype;
      _step1Chips.clear();
      _step2Chips.clear();
      _step3Chips.clear();
      _negativeChips.clear();
      _step1Chips.addAll(preset.step1);
      _step2Chips.addAll(preset.step2);
      _step3Chips.addAll(preset.step3);
      _negativeChips.addAll(preset.negativeChips);
      _isChipsCustomized = false;
    });
  }

  void _resetChipsToPreset() {
    setState(() {
      final preset = StepCategoryPresets.detectBestPreset(_selectedCategoryType, _selectedTemplateId);
      _selectedArchetype = preset.archetype;
      _step1Chips.clear();
      _step2Chips.clear();
      _step3Chips.clear();
      _negativeChips.clear();
      _step1Chips.addAll(preset.step1);
      _step2Chips.addAll(preset.step2);
      _step3Chips.addAll(preset.step3);
      _negativeChips.addAll(preset.negativeChips);
      _isChipsCustomized = false;
    });
  }

  void _handleAddChip() {
    final text = _addChipCtrl.text.trim();
    if (text.isEmpty) return;
    final currentStep = _tabController.index + 1;
    final formatted = currentStep == 4
        ? StringUtils.formatChipText(text)
        : StringUtils.formatChipText(text, step: currentStep, archetype: _selectedArchetype);
    if (formatted.isEmpty) return;

    bool isDuplicate(List<String> list, String t) {
      final cleanNew = StringUtils.stripLeadingEmoji(t).toLowerCase();
      return list.any((item) => StringUtils.stripLeadingEmoji(item).toLowerCase() == cleanNew);
    }

    setState(() {
      if (currentStep == 1 && !isDuplicate(_step1Chips, formatted)) {
        _step1Chips.add(formatted);
        _isChipsCustomized = true;
      } else if (currentStep == 2 && !isDuplicate(_step2Chips, formatted)) {
        _step2Chips.add(formatted);
        _isChipsCustomized = true;
      } else if (currentStep == 3 && !isDuplicate(_step3Chips, formatted)) {
        _step3Chips.add(formatted);
        _isChipsCustomized = true;
      } else if (currentStep == 4 && !isDuplicate(_negativeChips, formatted)) {
        _negativeChips.add(formatted);
        _isChipsCustomized = true;
      }
      _addChipCtrl.clear();
      _addChipFocus.requestFocus();
    });
  }

  void _handleRemoveChip(int step, String chip) {
    setState(() {
      if (step == 1) {
        _step1Chips.remove(chip);
        _isChipsCustomized = true;
      } else if (step == 2) {
        _step2Chips.remove(chip);
        _isChipsCustomized = true;
      } else if (step == 3) {
        _step3Chips.remove(chip);
        _isChipsCustomized = true;
      } else if (step == 4) {
        _negativeChips.remove(chip);
        _isChipsCustomized = true;
      }
    });
  }

  Future<void> _loadBranches() async {
    final svc      = context.read<FirestoreService>();
    final branches = await svc.getBranches(widget.business.id);
    if (!mounted) return;
    setState(() {
      _branchIds       = branches.map((b) => b.id).toList();
      _branchDrafts    = branches.map(_branchToDraft).toList();
      _branchesLoading = false;
    });
  }

  BranchDraft _branchToDraft(BranchModel b) {
    final d = BranchDraft();
    d.name                = b.branchName;
    d.address             = b.address;
    d.whatsappNumber      = b.whatsappNumber;
    d.whatsappMonitoredBy = b.whatsappMonitoredBy;
    d.placeId             = b.placeId;
    d.googleReviewLink    = b.googleReviewLink;
    for (final entry in b.starRoutingConfig.entries) {
      d.starRouting[entry.key] = entry.value;
    }
    return d;
  }

  // ── Logo — Bug 2: pick + dimension check (same pattern as enroll_screen) ──

  Future<void> _pickLogoWithValidation() async {
    setState(() => _logoRejection = null);
    final result = await ImagePickerWeb.getImageInfo();
    if (result == null || !mounted) return;

    final bytes = result.data;
    if (bytes == null) return;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();

      if (w < AppConstants.minLogoPx || h < AppConstants.minLogoPx) {
        if (mounted) {
          setState(() => _logoRejection =
              'Logo too small — minimum ${AppConstants.minLogoPx}×'
              '${AppConstants.minLogoPx} px. Uploaded: $w×$h px.');
        }
        return;
      }
    } catch (_) {
      // Dimension decode failed — allow the upload
    }

    // Auto-resize and compress logo client-side to max 384px
    final optimizedBytes = await ImageUtils.resizeAndCompressLogo(bytes, maxDimension: 384);

    if (mounted) {
      setState(() {
        _logoBytes    = optimizedBytes;
        _logoMimeType = 'image/png';
        _logoRejection = null;
      });
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────

  static final RegExp _validIndianPhone = RegExp(r'^\+91[6-9]\d{9}$');

  String? get _validationError {
    if (_brandNameCtrl.text.trim().isEmpty) return 'Business name is required.';
    if (_ownerNameCtrl.text.trim().isEmpty) return 'Owner name is required.';
    if (_ownerEmailCtrl.text.trim().isEmpty) return 'Owner email is required.';
    if (!_validIndianPhone.hasMatch(_ownerPhoneE164.trim())) {
      return 'Owner phone must be a valid 10-digit Indian mobile (starts with 6–9).';
    }
    if (_branchDrafts.isEmpty) return 'At least one branch is required.';
    final multiBranch = _branchDrafts.length > 1;
    for (int i = 0; i < _branchDrafts.length; i++) {
      final d     = _branchDrafts[i];
      final label = multiBranch ? 'Branch ${i + 1}' : 'Branch';
      if (multiBranch && d.name.trim().isEmpty)     return '$label: branch name is required.';
      if (d.whatsappNumber.trim().isEmpty)          return '$label: WhatsApp number is required.';
      if (!_validIndianPhone.hasMatch(d.whatsappNumber.trim())) {
        return '$label: WhatsApp must be a valid 10-digit Indian mobile (starts with 6–9).';
      }
      if (d.whatsappMonitoredBy.trim().isEmpty)     return '$label: "Monitored by" is required.';
      if (d.address.trim().isEmpty)                 return '$label: address is required.';
      if (!d.starRoutingComplete)                   return '$label: set routing for all 5 star ratings.';
    }
    return null;
  }

  // ── Bug 1: focus + scroll to first invalid field ─────────────────────────

  void _focusFirstError([String? specificError]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusNode? target;
      final errLower = (specificError ?? _validationError ?? '').toLowerCase();

      if (errLower.contains('email') || _ownerEmailError != null || _ownerEmailCtrl.text.trim().isEmpty) {
        target = _ownerEmailFocus;
      } else if (errLower.contains('business name') || errLower.contains('brand') || _brandNameCtrl.text.trim().isEmpty) {
        target = _brandNameFocus;
      } else if (errLower.contains('owner name') || _ownerNameCtrl.text.trim().isEmpty) {
        target = _ownerNameFocus;
      }

      if (target != null) {
        target.requestFocus();
        if (target.context != null) {
          Scrollable.ensureVisible(
            target.context!,
            duration:  const Duration(milliseconds: 400),
            curve:     Curves.easeInOutCubic,
            alignment: 0.2,
          );
        }
      }
    });
  }

  // ── Save — Bug 2 (upload if staged) + Bug 3 (replaceLocal) ───────────────

  Future<void> _save() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _showErrors = true;
      _saveError = null;
      _ownerEmailError = null;
    });

    final valErr = _validationError;
    if (valErr != null) {
      setState(() => _saving = false);
      _focusFirstError(valErr); // Bug 1
      return;
    }

    final svc        = context.read<FirestoreService>();
    final storageSvc = context.read<StorageService>();
    final auth       = context.read<AppAuthProvider>();
    final enrolledBy = auth.isAdmin ? 'admin' : (auth.uid ?? '');
    
    for (final draft in _branchDrafts) {
      if (draft.placeId != null && draft.placeId!.isNotEmpty) {
        final exists = await svc.placeIdExistsForEdit(
            draft.placeId!, widget.business.id);
        if (exists && mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Place ID "${draft.placeId}" is already registered to another business.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
          return;
        }
      }
    }

    final editEmail = _ownerEmailCtrl.text.trim();
    if (editEmail.isNotEmpty) {
      final emailExists = await svc.ownerEmailExistsForEdit(editEmail, widget.business.id);
      if (emailExists && mounted) {
        setState(() {
          _saving = false;
          _ownerEmailError = 'Owner email "$editEmail" is already registered to another business.';
          _showErrors = true;
        });
        _focusFirstError(_ownerEmailError);
        return;
      }
    }

    try {
      // Bug 2: upload staged logo bytes if the user picked a new logo
      String finalLogoUrl = _logoUrl;
      if (_logoBytes != null && _logoMimeType != null) {
        setState(() => _logoUploading = true);
        finalLogoUrl = await storageSvc.uploadLogo(_logoBytes!, _logoMimeType!);
        if (mounted) setState(() { _logoUrl = finalLogoUrl; _logoUploading = false; });
      }

      final cleanBrandName = StringUtils.toTitleCase(_brandNameCtrl.text.trim());
      final cleanOwnerName = StringUtils.toTitleCase(_ownerNameCtrl.text.trim());

      final customStepCats = <String, List<String>>{
        'step1': List<String>.from(_step1Chips),
        'step2': List<String>.from(_step2Chips),
        'step3': List<String>.from(_step3Chips),
      };

      // 1 — Update business-level fields
      await svc.updateBusiness(
        widget.business.id,
        brandName:                cleanBrandName,
        logoUrl:                  finalLogoUrl,
        categoryType:             _selectedCategoryType.trim(),
        templateId:               _selectedTemplateId,
        stepCategories:           customStepCats,
        negativeFeedbackChips:    List<String>.from(_negativeChips),
        archetype:                _selectedArchetype,
        reviewLanguagePreference: _reviewLanguagePreference,
        hasCustomPhrases:         _isChipsCustomized || widget.business.hasCustomPhrases,
        ownerName:                cleanOwnerName,
        ownerEmail:               _ownerEmailCtrl.text.trim(),
        ownerPhone:               _ownerPhoneE164.trim(),
        enrolledBy:               auth.isAdmin ? _selectedEnrolledBy : null,
      );

      // 2 — Update existing branches OR insert newly added branches
      for (int i = 0; i < _branchDrafts.length; i++) {
        final draft = _branchDrafts[i];
        final cleanBranchName = StringUtils.toTitleCase(draft.name.trim());
        final cleanMonitor = StringUtils.toTitleCase(draft.whatsappMonitoredBy.trim());
        draft.name = cleanBranchName;
        draft.whatsappMonitoredBy = cleanMonitor;

        if (i < _branchIds.length) {
          await svc.updateBranch(
            widget.business.id,
            _branchIds[i],
            branchName:          cleanBranchName,
            address:             draft.address.trim(),
            whatsappNumber:      draft.whatsappNumber.trim(),
            whatsappMonitoredBy: cleanMonitor,
            placeId:             draft.placeId,
            googleReviewLink:    draft.googleReviewLink,
            starRoutingConfig:   draft.starRoutingAsMap,
            categoryOverrideId:  null,
          );
        } else {
          await svc.addBranchToBusiness(widget.business.id, draft, enrolledBy: enrolledBy);
        }
      }

      if (mounted) {
        // Bug 3: update the in-memory model so list + any cached detail view
        // reflect new values immediately — no page refresh needed.
        final updated = widget.business.copyWith(
          brandName:                 _brandNameCtrl.text.trim(),
          logoUrl:                   finalLogoUrl,
          categoryType:              _selectedCategoryType.trim(),
          defaultCategoryTemplateId: _selectedTemplateId,
          stepCategories:            customStepCats,
          negativeFeedbackChips:     List<String>.from(_negativeChips),
          archetype:                 _selectedArchetype,
          reviewLanguagePreference:  _reviewLanguagePreference,
          hasCustomPhrases:          _isChipsCustomized || widget.business.hasCustomPhrases,
          ownerName:                 _ownerNameCtrl.text.trim(),
          ownerEmail:                _ownerEmailCtrl.text.trim(),
          ownerPhone:                _ownerPhoneE164.trim(),
          enrolledBy:                auth.isAdmin ? _selectedEnrolledBy : widget.business.enrolledBy,
          currentlyManagedBy:        auth.isAdmin ? _selectedEnrolledBy : widget.business.currentlyManagedBy,
        );
        context.read<MyBusinessesProvider>().replaceLocal(updated);

        if (auth.isAdmin) {
          try {
            final adminProvider = context.read<AdminDashboardProvider>();
            await adminProvider.fetchAllBusinesses();
            await adminProvider.fetchEmployees();
          } catch (_) {}
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Changes saved successfully'),
            ],
          ),
          backgroundColor: AppColors.activeFg,
          behavior:        SnackBarBehavior.floating,
          duration:        const Duration(seconds: 4),
        ));
        // Admin → Overrides screen, Employee → My Enrolled Businesses
        final isAdmin = context.read<AppAuthProvider>().isAdmin;
        context.go(isAdmin ? '/admin' : '/businesses');
      }
    } catch (e) {
      setState(() { _saveError = e.toString(); _saving = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _buildChipCustomizer(ColorScheme scheme) {
    final currentStep = _tabController.index + 1;
    final currentList = currentStep == 1
        ? _step1Chips
        : (currentStep == 2
            ? _step2Chips
            : (currentStep == 3 ? _step3Chips : _negativeChips));

    final stepHints = [
      'e.g., 🍕 Wood-fired Pizza, ☕ Cold Brew, 💆 Balayage Hair Spa',
      'e.g., 🧀 Rich Cheese Pull, ⚡ Fast Turnaround, 😋 Authentic Taste',
      'e.g., ✨ Cozy Vibe, 😊 Attentive Staff, 🧼 Hygienic Seating',
      'e.g., ⏳ Long Waiting Time, ❄️ Cold Food, 👥 Rude Behavior',
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: _isChipsCustomized
              ? AppColors.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: _isChipsCustomized ? 1.5 : 1.0,
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
                          if (_isChipsCustomized) ...[
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
                        'Customize the 1-tap options customers will see on their review screen.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isChipsCustomized)
                  TextButton.icon(
                    onPressed: _resetChipsToPreset,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Open Advanced Simulator & Phrase Editor',
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  onPressed: () async {
                    final saved = await BusinessPhrasesEditorDialog.show(context, widget.business);
                    if (saved == true && mounted) {
                      final doc = await context.read<FirestoreService>().getBusiness(widget.business.id);
                      if (doc != null && mounted) {
                        setState(() {
                          _step1Chips.clear();
                          _step2Chips.clear();
                          _step3Chips.clear();
                          _negativeChips.clear();
                          if (doc.stepCategories != null) {
                            _step1Chips.addAll(doc.stepCategories!['step1'] ?? []);
                            _step2Chips.addAll(doc.stepCategories!['step2'] ?? []);
                            _step3Chips.addAll(doc.stepCategories!['step3'] ?? []);
                          }
                          if (doc.negativeFeedbackChips != null) {
                            _negativeChips.addAll(doc.negativeFeedbackChips!);
                          }
                          _selectedArchetype = doc.archetype ?? _selectedArchetype;
                          _isChipsCustomized = doc.hasCustomPhrases;
                        });
                      }
                    }
                  },
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
              Tab(text: '1. Products & Services (${_step1Chips.length})'),
              Tab(text: '2. Highlights (${_step2Chips.length})'),
              Tab(text: '3. Experience (${_step3Chips.length})'),
              Tab(text: '⚠️ Private Feedback (${_negativeChips.length})'),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Add Input Box
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addChipCtrl,
                        focusNode: _addChipFocus,
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
                        onSubmitted: (_) => _handleAddChip(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _handleAddChip,
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
                      return Chip(
                        label: Text(
                          chipText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _handleRemoveChip(currentStep, chipText),
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

  @override
  Widget build(BuildContext context) {
    final isPending = widget.business.subscriptionStatus ==
        AppConstants.statusPendingPayment;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${widget.business.brandName}'),
        actions: [
          if (!_saving)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon:  const Icon(Icons.save_outlined),
              label: const Text('Save'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _branchesLoading || _templatesLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width > 600 ? 20 : 12,
                      vertical: 16,
                    ),
                children: [
                  // ── Status banner ──────────────────────────────────────
                  if (isPending)
                    _InfoBanner(
                      icon:    Icons.info_outline,
                      color:   AppColors.pendingFg,
                      message: 'Draft — awaiting payment. '
                          'You can still fix any enrollment mistakes here.',
                    ),
                  if (!isPending)
                    _InfoBanner(
                      icon:    Icons.check_circle_outline,
                      color:   AppColors.activeFg,
                      message: 'Active business — edits apply immediately. '
                          'Subscription fields are managed by admin.',
                    ),

                  const SizedBox(height: 20),

                  // ── Business details ───────────────────────────────────
                  _SectionHeader('Business details'),
                  const SizedBox(height: 12),

                  // Bug 1: FocusNode on brand name
                  TextFormField(
                    controller: _brandNameCtrl,
                    focusNode:  _brandNameFocus,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText:  'Business / Brand name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator:  (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged:  (_) => setState(() {}),
                  ),
                  if (_showErrors && _brandNameCtrl.text.trim().isEmpty)
                    _FieldError('Business name is required.'),
                  const SizedBox(height: 16),

                  // Category dropdown with all 50+ presets and templates
                  _templatesLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                      : DropdownButtonFormField<String>(
                          value: _templates.any((t) => t['id'] == _selectedTemplateId)
                              ? _selectedTemplateId
                              : null,
                          isExpanded:    true,
                          dropdownColor: Colors.white,
                          borderRadius:  BorderRadius.circular(14),
                          elevation:     8,
                          icon:          const Icon(Icons.keyboard_arrow_down_rounded),
                          decoration: const InputDecoration(
                            labelText:  'Business category',
                            prefixIcon: Icon(Icons.category_outlined),
                            helperText: 'Select industry category to load tailored review options',
                          ),
                          hint:  const Text('Select a category'),
                          items: _templates.map((t) => DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(
                              t['business_type'] as String? ?? t['name'] as String? ?? t['id'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )).toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            final match = _templates.firstWhere(
                              (t) => t['id'] == val,
                              orElse: () => {'business_type': val},
                            );
                            final catType = match['business_type'] as String? ??
                                match['name'] as String? ??
                                val;
                            _applyCategoryPreset(catType, val);
                          },
                        ),
                  const SizedBox(height: 16),

                  // Review Language Preference
                  DropdownButtonFormField<String>(
                    value: _reviewLanguagePreference,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 8,
                    decoration: const InputDecoration(
                      labelText: 'Review Language Preference',
                      prefixIcon: Icon(Icons.translate_rounded),
                      helperText: 'Select what language reviews will be generated and served in.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'english',
                        child: Text('English Only (Default)'),
                      ),
                      DropdownMenuItem(
                        value: 'hinglish',
                        child: Text('Hinglish Only (Roman script)'),
                      ),
                      DropdownMenuItem(
                        value: 'mixed',
                        child: Text('Mixed (English + Hinglish)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _reviewLanguagePreference = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── 3-Step Guided Review Offerings & Chips Customizer ──
                  _buildChipCustomizer(scheme),
                  const SizedBox(height: 16),

                  if (context.watch<AppAuthProvider>().isAdmin) ...[
                    DropdownButtonFormField<String>(
                      value:         _selectedEnrolledBy,
                      dropdownColor: Colors.white,
                      borderRadius:  BorderRadius.circular(14),
                      elevation:     8,
                      icon:          const Icon(Icons.keyboard_arrow_down_rounded),
                      decoration: const InputDecoration(
                        labelText: 'Enrolled by (Employee) *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        helperText: 'Credits the selected employee for enrollment & commissions',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin (Direct enrollment / No commission)'),
                        ),
                        ..._employees
                            .where((e) => !e.isAdmin)
                            .map((e) => DropdownMenuItem(
                          value: e.uid,
                          child: Text('${e.name} (${e.email})'),
                        )),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedEnrolledBy = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 20),

                  // ── Logo — Bug 2: always rendered ──────────────────────
                  _SectionHeader('Logo'),
                  const SizedBox(height: 12),
                  _LogoEditRow(
                    existingUrl:  _logoUrl,
                    stagedBytes:  _logoBytes,
                    uploading:    _logoUploading,
                    rejection:    _logoRejection,
                    onPick:       _pickLogoWithValidation,
                  ),

                  const SizedBox(height: 20),

                  // ── Owner info ─────────────────────────────────────────
                  _SectionHeader('Owner contact'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _ownerNameCtrl,
                    focusNode:  _ownerNameFocus,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Owner name *',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: _ownerNameError ?? (_showErrors && _ownerNameCtrl.text.trim().isEmpty ? 'Owner name is required.' : null),
                    ),
                    onChanged: (v) {
                      if (_ownerNameError != null) setState(() => _ownerNameError = null);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller:   _ownerEmailCtrl,
                    focusNode:    _ownerEmailFocus,
                    decoration:   InputDecoration(
                      labelText: 'Owner email *',
                      prefixIcon: const Icon(Icons.mail_outline),
                      errorText: _ownerEmailError ?? (_showErrors && _ownerEmailCtrl.text.trim().isEmpty ? 'Owner email is required.' : null),
                      errorMaxLines: 3,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (v) {
                      if (_ownerEmailError != null) setState(() => _ownerEmailError = null);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  PhoneField(
                    label:        'Owner phone *',
                    initialValue: _ownerPhoneE164,
                    showError:    _showErrors,
                    onChanged:    (e164) => setState(() => _ownerPhoneE164 = e164),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Branch section ────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader('Branches (${_branchDrafts.length})'),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _branchDrafts.add(BranchDraft());
                          });
                        },
                        icon: const Icon(Icons.add_business_outlined, size: 16),
                        label: const Text('Add Another Branch'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_branchDrafts.isEmpty)
                    AppEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No branches configured',
                      subtitle: 'Every business must have at least one branch location.',
                      actionLabel: 'Add Branch',
                      onAction: () => setState(() => _branchDrafts.add(BranchDraft())),
                    )
                  else
                    ...List.generate(_branchDrafts.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: BranchFormWidget(
                        key: ValueKey('branch_$i'),
                        branchIndex:    i,
                        draft:          _branchDrafts[i],
                        showBranchName: _branchDrafts.length > 1,
                        showError:      _showErrors,
                        ownerPhone:     _ownerPhoneE164,
                        ownerName:      _ownerNameCtrl.text,
                        onRemove:       i >= _branchIds.length && _branchDrafts.length > 1
                            ? () => setState(() => _branchDrafts.removeAt(i))
                            : null,
                        onChanged:      () => setState(() {}),
                      ),
                    )),

                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _saveError!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Save button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

// ── Logo edit row — Bug 2 ─────────────────────────────────────────────────────
// Always rendered. Shows:
//   • staged bytes preview  (in-memory pick, not yet uploaded)
//   • OR existing URL thumbnail
//   • OR placeholder
// Plus an upload / replace button.

class _LogoEditRow extends StatelessWidget {
  final String     existingUrl;
  final Uint8List? stagedBytes;
  final bool       uploading;
  final String?    rejection;
  final VoidCallback onPick;

  const _LogoEditRow({
    required this.existingUrl,
    required this.stagedBytes,
    required this.uploading,
    required this.rejection,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme      = Theme.of(context).colorScheme;
    final hasExisting = existingUrl.isNotEmpty;
    final hasStaged   = stagedBytes != null;
    final hasError    = rejection != null;

    Widget thumbnail;
    if (hasStaged) {
      thumbnail = Image.memory(
        stagedBytes!,
        width: 72, height: 72, fit: BoxFit.cover,
      );
    } else if (hasExisting) {
      thumbnail = Image.network(
        existingUrl,
        width: 72, height: 72, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(scheme),
      );
    } else {
      thumbnail = _placeholder(scheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumbnail,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasStaged
                        ? '✓ New logo selected — will upload on save'
                        : hasExisting
                            ? 'Current logo'
                            : 'No logo yet',
                    style: TextStyle(
                      fontSize:   13,
                      color:      hasStaged ? AppColors.activeFg : scheme.onSurfaceVariant,
                      fontWeight: hasStaged ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Min ${AppConstants.minLogoPx}×${AppConstants.minLogoPx} px · JPEG or PNG',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  uploading
                      ? const Row(children: [
                          SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Uploading…', style: TextStyle(fontSize: 12)),
                        ])
                      : OutlinedButton.icon(
                          onPressed: onPick,
                          icon:  Icon(
                            hasExisting || hasStaged
                                ? Icons.swap_horiz_outlined
                                : Icons.upload_outlined,
                            size: 16,
                          ),
                          label: Text(
                            hasExisting || hasStaged ? 'Replace logo' : 'Upload logo',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: hasError
                                ? BorderSide(color: scheme.error, width: 1.5)
                                : null,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          _FieldError(rejection!),
        ],
      ],
    );
  }

  static Widget _placeholder(ColorScheme scheme) => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color:        scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.add_a_photo_outlined,
          size:  28,
          color: scheme.onSurfaceVariant,
        ),
      );
}

// ── Inline field error ────────────────────────────────────────────────────────

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 12),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
        ),
      );
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

// ── Info banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   message;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 13, color: color)),
            ),
          ],
        ),
      );
}
