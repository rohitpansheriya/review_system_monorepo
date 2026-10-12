// lib/providers/enroll_provider.dart
// Manages all enrollment form state.
//
// KEY DESIGN DECISIONS:
//   - Single-location mode:  one BranchDraft, branch name = brand name (auto)
//   - Multi-branch mode:     List<BranchDraft>, branch name required each
//   - Same Firestore schema either way (businesses + N branches subdocs)
//   - submit() passes all branches to FirestoreService in one WriteBatch

import 'package:flutter/foundation.dart';
import '../models/branch_draft.dart';
import '../services/firestore_service.dart';
import '../services/places_service.dart';
import '../services/qr_stub_service.dart';
import '../services/storage_service.dart';
import '../core/string_utils.dart';
import '../core/step_category_presets.dart';

enum EnrollMode { single, multi }
enum EnrollStatus { idle, submitting, success, error }

class EnrollProvider extends ChangeNotifier {
  final FirestoreService _firestore;
  final StorageService   _storage;
  final PlacesService    _places;
  final QrStubService    _qrService;

  EnrollProvider({
    required FirestoreService firestoreService,
    required StorageService   storageService,
    required PlacesService    placesService,
    required QrStubService    qrStubService,
  })  : _firestore = firestoreService,
        _storage   = storageService,
        _places    = placesService,
        _qrService = qrStubService {
    final preset = StepCategoryPresets.detectBestPreset('', null);
    step1Chips = List<String>.from(preset.step1);
    step2Chips = List<String>.from(preset.step2);
    step3Chips = List<String>.from(preset.step3);
    negativeFeedbackChips = List<String>.from(preset.negativeChips);
    archetype = preset.archetype;
    serviceTags = {};
    for (final s in step1Chips) {
      serviceTags[s] = List<String>.from(
        preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset),
      );
    }
  }

  // ── Mode ──────────────────────────────────────────────────────────────────
  EnrollMode _mode = EnrollMode.single;
  EnrollMode get mode => _mode;

  void setMode(EnrollMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    // Reset branches: single always has exactly 1; multi starts with 1 too.
    _branches = [BranchDraft()];
    notifyListeners();
  }

  // ── Business-level fields ─────────────────────────────────────────────────
  String brandName    = '';
  String categoryType = '';
  String? templateId;

  // Logo
  Uint8List? logoBytes;
  String?    logoMimeType;
  String?    logoUrl;
  bool       logoUploading = false;

  // Owner contact
  String ownerName  = '';
  String ownerEmail = '';
  String ownerPhone = '';

  // Review Language Preference: 'english' (default), 'hinglish', 'mixed'
  String reviewLanguagePreference = 'english';

  void setReviewLanguagePreference(String pref) {
    if (reviewLanguagePreference == pref) return;
    reviewLanguagePreference = pref;
    notifyListeners();
  }

  // ── 3-Step Guided Review Chips & Private Feedback ────────────────────────
  List<String> step1Chips = [];
  List<String> step2Chips = [];
  List<String> step3Chips = [];
  List<String> negativeFeedbackChips = [];
  Map<String, List<String>> serviceTags = {};
  String? archetype;
  bool isChipsCustomized = false;

  void applyCategoryPreset(String catType, String? tId) {
    categoryType = catType;
    templateId = tId;
    final preset = StepCategoryPresets.detectBestPreset(catType, tId);
    step1Chips = List<String>.from(preset.step1);
    step2Chips = List<String>.from(preset.step2);
    step3Chips = List<String>.from(preset.step3);
    negativeFeedbackChips = List<String>.from(preset.negativeChips);
    archetype = preset.archetype;
    serviceTags = {};
    for (final s in step1Chips) {
      serviceTags[s] = List<String>.from(
        preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset),
      );
    }
    isChipsCustomized = false;
    notifyListeners();
  }

  void addChip(int step, String chip) {
    final formatted = step == 4
        ? chip.trim()
        : StringUtils.formatChipText(chip, step: step, archetype: archetype);
    if (formatted.isEmpty) return;

    bool isDuplicate(List<String> list, String text) {
      final cleanNew = StringUtils.stripLeadingEmoji(text).toLowerCase();
      return list.any((item) => StringUtils.stripLeadingEmoji(item).toLowerCase() == cleanNew);
    }

    if (step == 1 && !isDuplicate(step1Chips, formatted)) {
      step1Chips.add(formatted);
      final preset = StepCategoryPresets.detectBestPreset(categoryType, templateId);
      final suggested = StepCategoryPresets.suggestTagsForService(formatted, currentPreset: preset);
      serviceTags[formatted] = List<String>.from(suggested);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 2 && !isDuplicate(step2Chips, formatted)) {
      step2Chips.add(formatted);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 3 && !isDuplicate(step3Chips, formatted)) {
      step3Chips.add(formatted);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 4 && !isDuplicate(negativeFeedbackChips, formatted)) {
      negativeFeedbackChips.add(formatted);
      isChipsCustomized = true;
      notifyListeners();
    }
  }

  void removeChip(int step, String chip) {
    if (step == 1) {
      step1Chips.remove(chip);
      serviceTags.remove(chip);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 2) {
      step2Chips.remove(chip);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 3) {
      step3Chips.remove(chip);
      isChipsCustomized = true;
      notifyListeners();
    } else if (step == 4) {
      negativeFeedbackChips.remove(chip);
      isChipsCustomized = true;
      notifyListeners();
    }
  }

  List<String> getTagsForService(String service) {
    if (serviceTags.containsKey(service) && serviceTags[service]!.isNotEmpty) {
      return List<String>.from(serviceTags[service]!);
    }
    final preset = StepCategoryPresets.detectBestPreset(categoryType, templateId);
    final suggested = StepCategoryPresets.suggestTagsForService(service, currentPreset: preset);
    serviceTags[service] = List<String>.from(suggested);
    return List<String>.from(suggested);
  }

  void updateTagsForService(String service, List<String> tags) {
    serviceTags[service] = List<String>.from(tags);
    isChipsCustomized = true;
    notifyListeners();
  }

  void addTagToService(String service, String tag) {
    final clean = tag.trim();
    if (clean.isEmpty) return;
    final current = serviceTags[service] ?? [];
    if (!current.contains(clean)) {
      serviceTags[service] = [...current, clean];
      isChipsCustomized = true;
      notifyListeners();
    }
  }

  void removeTagFromService(String service, String tag) {
    final current = serviceTags[service] ?? [];
    serviceTags[service] = current.where((t) => t != tag).toList();
    isChipsCustomized = true;
    notifyListeners();
  }

  void resetTagsForService(String service) {
    final preset = StepCategoryPresets.detectBestPreset(categoryType, templateId);
    serviceTags[service] = StepCategoryPresets.suggestTagsForService(service, currentPreset: preset);
    isChipsCustomized = true;
    notifyListeners();
  }

  void resetChipsToPreset() {
    final preset = StepCategoryPresets.detectBestPreset(categoryType, templateId);
    step1Chips = List<String>.from(preset.step1);
    step2Chips = List<String>.from(preset.step2);
    step3Chips = List<String>.from(preset.step3);
    negativeFeedbackChips = List<String>.from(preset.negativeChips);
    archetype = preset.archetype;
    serviceTags = {};
    for (final s in step1Chips) {
      serviceTags[s] = List<String>.from(
        preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset),
      );
    }
    isChipsCustomized = false;
    notifyListeners();
  }

  // Test / Demo Mode (Solution 2)
  bool isTestAccount = false;

  void setIsTestAccount(bool value) {
    isTestAccount = value;
    notifyListeners();
  }

  // ── Branches ──────────────────────────────────────────────────────────────
  List<BranchDraft> _branches = [BranchDraft()];
  List<BranchDraft> get branches => List.unmodifiable(_branches);

  BranchDraft branchAt(int index) => _branches[index];

  bool get isMulti => _mode == EnrollMode.multi;

  void addBranch() {
    _branches.add(BranchDraft());
    notifyListeners();
  }

  void removeBranch(int index) {
    if (_branches.length <= 1) return; // always keep at least one
    _branches.removeAt(index);
    notifyListeners();
  }

  /// Called by BranchFormWidget whenever a draft field changes.
  /// BranchDraft is mutable in-place; this just triggers a rebuild.
  void notifyBranchChanged() => notifyListeners();

  // ── Status ────────────────────────────────────────────────────────────────
  EnrollStatus _status = EnrollStatus.idle;
  String? _error;
  String? _successBizId;

  EnrollStatus get status       => _status;
  String?      get error        => _error;
  String?      get successBizId => _successBizId;
  bool         get isSubmitting => _status == EnrollStatus.submitting;

  // ── Validation ────────────────────────────────────────────────────────────

  static final RegExp _e164India = RegExp(r'^\+91[6-9]\d{9}$');

  static bool _validPhone(String v) => _e164India.hasMatch(v.trim());

  /// Returns null if valid, an error string if not.
  String? get validationError {
    if (brandName.trim().isEmpty)  return 'Business name is required.';
    if (ownerEmail.trim().isEmpty) return 'Owner email is required.';
    if (ownerName.trim().isEmpty)  return 'Owner name is required.';
    if (ownerPhone.trim().isEmpty) return 'Owner phone is required.';
    if (!_validPhone(ownerPhone)) {
      return 'Owner phone must be a valid 10-digit Indian mobile (starts with 6–9).';
    }
    if (_mode == EnrollMode.multi && _branches.isEmpty) {
      return 'Add at least one branch.';
    }
    for (int i = 0; i < _branches.length; i++) {
      final b = _branches[i];
      final label = _mode == EnrollMode.multi ? 'Branch ${i + 1}' : 'Branch';
      if (isMulti && b.name.trim().isEmpty) {
        return '$label: branch name is required.';
      }
      if (b.whatsappNumber.trim().isEmpty) {
        return '$label: WhatsApp number is required.';
      }
      if (!_validPhone(b.whatsappNumber)) {
        return '$label: WhatsApp must be a valid 10-digit Indian mobile (starts with 6–9).';
      }
      // Change 5: whatsapp_monitored_by is required so the team always knows
      // who handles incoming 1–3 star WhatsApp messages.
      if (b.whatsappMonitoredBy.trim().isEmpty) {
        return '$label: WhatsApp monitored-by contact is required.';
      }
      if (b.address.trim().isEmpty) {
        return '$label: address is required.';
      }
      // Star selection commented out for simplified flow
      // if (!b.starRoutingComplete) {
      //   return '$label: please set routing for all 5 stars.';
      // }
    }
    return null;
  }

  bool get allBranchesComplete => _branches.every(
    (b) => b.isComplete(requireBranchName: isMulti),
  );

  // ── Logo ──────────────────────────────────────────────────────────────────

  void setLogo(Uint8List bytes, String mimeType) {
    logoBytes    = bytes;
    logoMimeType = mimeType;
    logoUrl      = null;
    notifyListeners();
  }

  Future<void> _uploadLogo() async {
    if (logoBytes == null || logoMimeType == null) return;
    logoUploading = true;
    notifyListeners();
    try {
      logoUrl = await _storage.uploadLogo(logoBytes!, logoMimeType!);
    } finally {
      logoUploading = false;
      notifyListeners();
    }
  }

  // ── Place auto-search (Global & per branch) ───────────────────────────────

  PlaceCandidate? autoFilledPlace;
  List<PlaceCandidate> topLevelCandidates = [];
  bool isTopLevelSearching = false;
  String? topLevelSearchError;

  void clearTopLevelSearch() {
    topLevelCandidates = [];
    topLevelSearchError = null;
    isTopLevelSearching = false;
    notifyListeners();
  }

  void clearAutoFilledPlace() {
    autoFilledPlace = null;
    notifyListeners();
  }

  /// Global search on Google Places (Business Name + City)
  Future<void> searchTopLevelPlaces(String businessName, String city) async {
    final bName = businessName.trim();
    final cName = city.trim();
    if (bName.isEmpty || cName.isEmpty) return;

    isTopLevelSearching = true;
    topLevelSearchError = null;
    topLevelCandidates  = [];
    notifyListeners();

    try {
      final results = await _places.search(bName, cName);
      topLevelCandidates  = results;
      topLevelSearchError = results.isEmpty
          ? 'No matching business found on Google Maps. Try different keywords or city.'
          : null;
    } catch (e) {
      topLevelCandidates  = [];
      topLevelSearchError = 'Search failed — check network or enter manually below.';
    } finally {
      isTopLevelSearching = false;
      notifyListeners();
    }
  }

  /// Auto-fills business name, category, archetype, chips, address, phone, and ratings from a PlaceCandidate.
  void applyPlaceAutoFill(
    PlaceCandidate candidate, {
    List<Map<String, dynamic>>? availableTemplates,
    int branchIndex = 0,
  }) {
    autoFilledPlace = candidate;

    // 1. Business Name
    if (candidate.name.trim().isNotEmpty) {
      brandName = candidate.name.trim();
    }

    // 2. Intelligent Category / Archetype detection
    String? matchedTemplateId;
    String matchedCategoryType = '';

    final searchKeys = <String>[];
    if (candidate.primaryType != null && candidate.primaryType!.isNotEmpty) {
      searchKeys.add(candidate.primaryType!.replaceAll('_', ' ').toLowerCase());
    }
    for (final t in candidate.types) {
      searchKeys.add(t.replaceAll('_', ' ').toLowerCase());
    }
    searchKeys.add(candidate.name.toLowerCase());

    // Try matching available Firestore templates first
    if (availableTemplates != null && availableTemplates.isNotEmpty) {
      for (final tmpl in availableTemplates) {
        final tId   = (tmpl['id'] as String? ?? '').toLowerCase();
        final tName = (tmpl['name'] as String? ?? '').toLowerCase();
        final tType = (tmpl['business_type'] as String? ?? '').toLowerCase();

        for (final key in searchKeys) {
          if (tId == key || tName == key || tType == key ||
              tName.contains(key) || (key.length > 3 && key.contains(tName)) ||
              tType.contains(key) || (key.length > 3 && key.contains(tType))) {
            matchedTemplateId   = tmpl['id'] as String?;
            matchedCategoryType = tmpl['business_type'] as String? ?? tmpl['name'] as String? ?? tmpl['id'] as String;
            break;
          }
        }
        if (matchedTemplateId != null) break;
      }
    }

    // Fall back to detecting preset from dictionary
    final bestPreset = StepCategoryPresets.detectBestPreset(
      searchKeys.join(' '),
      matchedTemplateId,
    );

    if (matchedCategoryType.isEmpty) {
      matchedCategoryType = bestPreset.name;
    }

    applyCategoryPreset(matchedCategoryType, matchedTemplateId ?? bestPreset.id);

    // 3. Auto-fill Branch
    if (branchIndex >= 0 && branchIndex < _branches.length) {
      final draft = _branches[branchIndex];
      draft.confirmCandidate(candidate);
      if (_mode == EnrollMode.single) {
        draft.name = brandName;
      } else if (draft.name.trim().isEmpty) {
        draft.name = '${candidate.name} (Main)';
      }
    }

    // 4. Pre-fill Owner phone if ownerPhone is empty and phone was found
    if (ownerPhone.trim().isEmpty && candidate.phoneNumber != null) {
      final digits = candidate.phoneNumber!.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) {
        ownerPhone = '+91$digits';
      } else if (digits.length == 11 && digits.startsWith('0') && RegExp(r'^[6-9]').hasMatch(digits.substring(1))) {
        ownerPhone = '+91${digits.substring(1)}';
      } else if (digits.length == 12 && digits.startsWith('91') && RegExp(r'^[6-9]').hasMatch(digits.substring(2))) {
        ownerPhone = '+91${digits.substring(2)}';
      }
    }

    topLevelCandidates = [];
    topLevelSearchError = null;
    notifyListeners();
  }

  /// Fetches rich details by Place ID and auto-fills.
  Future<bool> fetchAndApplyPlaceDetails(
    String placeId, {
    List<Map<String, dynamic>>? availableTemplates,
    int branchIndex = 0,
  }) async {
    final candidate = await _places.getDetails(placeId);
    if (candidate == null) return false;
    applyPlaceAutoFill(
      candidate,
      availableTemplates: availableTemplates,
      branchIndex: branchIndex,
    );
    return true;
  }

  /// Searches Places for a specific branch by index.
  Future<void> searchPlaces(int branchIndex, String businessName, String city) async {
    final draft = _branches[branchIndex];
    draft.isSearching = true;
    draft.searchError = null;
    draft.candidates  = [];
    notifyListeners();

    try {
      final results = await _places.search(businessName, city);
      draft.candidates  = results;
      draft.searchError = results.isEmpty
          ? 'No matches found — try a different name or enter manually.'
          : null;
    } catch (e) {
      draft.candidates  = [];
      draft.searchError = 'Search failed — use manual entry below.';
    } finally {
      draft.isSearching = false;
      notifyListeners();
    }
  }

  // ── Duplicate Place ID guard ───────────────────────────────────────────────

  /// Returns an error string if any non-null Place ID in the current batch
  /// already exists in Firestore, else null.
  Future<String?> _checkDuplicatePlaceIds() async {
    for (int i = 0; i < _branches.length; i++) {
      final pid = _branches[i].placeId;
      if (pid == null || pid.isEmpty) continue;
      final exists = await _firestore.placeIdExists(pid);
      if (exists) {
        final label = isMulti ? 'Branch ${i + 1}' : 'Branch';
        return '$label: a business with Place ID "$pid" already exists. '
            'Use a different Place ID or leave it blank.';
      }
    }
    return null;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<String?> submit(String employeeId) async {
    if (_status == EnrollStatus.submitting) {
      return 'Submission is already in progress.';
    }

    // 1 — Validate
    final err = validationError;
    if (err != null) return err;

    _status = EnrollStatus.submitting;
    _error  = null;
    notifyListeners();

    try {
      // 2 — Upload logo if selected
      if (logoBytes != null && logoUrl == null) await _uploadLogo();

      // 3 — Duplicate Place ID guard (per branch)
      final dupErr = await _checkDuplicatePlaceIds();
      if (dupErr != null) {
        _status = EnrollStatus.error;
        _error  = dupErr;
        notifyListeners();
        return _error;
      }

      // 3b — Duplicate Owner Email guard
      if (ownerEmail.trim().isNotEmpty) {
        final emailExists = await _firestore.ownerEmailExists(ownerEmail.trim());
        if (emailExists) {
          _status = EnrollStatus.error;
          _error  = 'Owner email "${ownerEmail.trim()}" is already registered to another business. If this owner has another location, please add it as a new branch under their existing business instead.';
          notifyListeners();
          return _error;
        }
      }

      // 4 — In single mode, set branch_name = brand_name if empty
      if (_mode == EnrollMode.single) {
        _branches[0].name = brandName.trim().isEmpty ? 'Main' : brandName.trim();
      }

      // 4b — Automatically normalize fields
      final cleanBrandName = StringUtils.toTitleCase(StringUtils.collapseWhitespace(brandName));
      final cleanOwnerName = StringUtils.toTitleCase(StringUtils.collapseWhitespace(ownerName));
      for (final b in _branches) {
        b.name = StringUtils.toTitleCase(StringUtils.collapseWhitespace(b.name));
        b.whatsappMonitoredBy = StringUtils.toTitleCase(StringUtils.collapseWhitespace(b.whatsappMonitoredBy));
        b.address = StringUtils.collapseWhitespace(b.address);
        if (b.placeId != null) {
          b.setPlaceId(b.placeId!);
        }
      }

      // 5 — Atomic batch write (business + N branches + counter)
      // Test / Demo mode is strictly restricted to Admin (employeeId == 'admin')
      final effectiveIsTest = (employeeId == 'admin') && isTestAccount;
      Map<String, List<String>>? customStepCats;
      if (step1Chips.isNotEmpty || step2Chips.isNotEmpty || step3Chips.isNotEmpty) {
        customStepCats = {
          'step1': List<String>.from(step1Chips),
          'step2': List<String>.from(step2Chips),
          'step3': List<String>.from(step3Chips),
        };
      }

      final result = await _firestore.enrollBusiness(
        employeeId:               employeeId,
        brandName:                cleanBrandName,
        logoUrl:                  logoUrl ?? '',
        categoryType:             categoryType,
        templateId:               templateId,
        ownerEmail:               ownerEmail.trim().toLowerCase(),
        ownerName:                cleanOwnerName,
        ownerPhone:               ownerPhone.trim(),
        isTestAccount:            effectiveIsTest,
        reviewLanguagePreference: reviewLanguagePreference,
        customStepCategories:     customStepCats,
        customServiceTags:        serviceTags,
        customArchetype:          archetype,
        negativeFeedbackChips:    negativeFeedbackChips.isNotEmpty ? negativeFeedbackChips : null,
        branches:                 List.of(_branches), // snapshot at submit time
      );

      final businessId = result['businessId'] as String;
      final branchIds  = List<String>.from(result['branchIds'] as List);
      _successBizId    = businessId;

      // 6 — Post-enrollment stubs (QR + owner provisioning) — fire and forget
      for (final branchId in branchIds) {
        _qrService.postEnrollment(
          businessId: businessId,
          branchId:   branchId,
          ownerEmail: ownerEmail.trim(),
          ownerName:  ownerName.trim(),
        );
      }

      _status = EnrollStatus.success;
      notifyListeners();
      return null; // success

    } catch (e) {
      _status = EnrollStatus.error;
      _error  = 'Enrollment failed: ${e.toString()}';
      notifyListeners();
      return _error;
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void reset() {
    _mode                    = EnrollMode.single;
    isTestAccount            = false;
    brandName                = '';
    categoryType             = '';
    templateId               = null;
    reviewLanguagePreference = 'english';
    logoBytes                = null;
    logoMimeType             = null;
    logoUrl                  = null;
    logoUploading            = false;
    ownerName                = '';
    ownerEmail               = '';
    ownerPhone               = '';
    autoFilledPlace          = null;
    topLevelCandidates       = [];
    isTopLevelSearching      = false;
    topLevelSearchError      = null;
    final preset             = StepCategoryPresets.detectBestPreset('', null);
    step1Chips               = List<String>.from(preset.step1);
    step2Chips               = List<String>.from(preset.step2);
    step3Chips               = List<String>.from(preset.step3);
    negativeFeedbackChips    = List<String>.from(preset.negativeChips);
    archetype                = preset.archetype;
    serviceTags              = {};
    for (final s in step1Chips) {
      serviceTags[s] = List<String>.from(
        preset.serviceTags[s] ?? StepCategoryPresets.suggestTagsForService(s, currentPreset: preset),
      );
    }
    isChipsCustomized        = false;
    _branches                = [BranchDraft()];
    _status                  = EnrollStatus.idle;
    _error                   = null;
    _successBizId            = null;
    notifyListeners();
  }
}
