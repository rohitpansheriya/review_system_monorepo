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
        _qrService = qrStubService;

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
      if (!b.starRoutingComplete) {
        return '$label: please set routing for all 5 stars.';
      }
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

  // ── Place auto-search (per branch) ───────────────────────────────────────

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

      // 4 — In single mode, set branch_name = brand_name if empty
      if (_mode == EnrollMode.single) {
        _branches[0].name = brandName.trim().isEmpty ? 'Main' : brandName.trim();
      }

      // 5 — Atomic batch write (business + N branches + counter)
      final result = await _firestore.enrollBusiness(
        employeeId:   employeeId,
        brandName:    brandName.trim(),
        logoUrl:      logoUrl ?? '',
        categoryType: categoryType,
        templateId:   templateId,
        ownerEmail:   ownerEmail.trim(),
        ownerName:    ownerName.trim(),
        ownerPhone:   ownerPhone.trim(),
        branches:     List.of(_branches), // snapshot at submit time
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
    _mode         = EnrollMode.single;
    brandName     = '';
    categoryType  = '';
    templateId    = null;
    logoBytes     = null;
    logoMimeType  = null;
    logoUrl       = null;
    logoUploading = false;
    ownerName     = '';
    ownerEmail    = '';
    ownerPhone    = '';
    _branches     = [BranchDraft()];
    _status       = EnrollStatus.idle;
    _error        = null;
    _successBizId = null;
    notifyListeners();
  }
}
