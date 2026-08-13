// lib/providers/profile_provider.dart
//
// Manages the employee's own profile (My Profile screen).
//
// State machine: streams the employees/{uid} doc in real-time.
// Every payout or document change resets documents_verified to "pending"
// (enforced in FirestoreService payload methods AND in Firestore security rules).

import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/employee_profile_model.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

enum ProfileSaveStatus { idle, saving, success, error }

class ProfileProvider extends ChangeNotifier {
  final FirestoreService _firestore;
  final StorageService   _storage;

  ProfileProvider({
    required FirestoreService firestoreService,
    required StorageService   storageService,
  })  : _firestore = firestoreService,
        _storage   = storageService;

  // ── State ─────────────────────────────────────────────────────────────────
  EmployeeProfileModel _profile    = EmployeeProfileModel.empty;
  ProfileSaveStatus    _status     = ProfileSaveStatus.idle;
  String?              _error;
  bool                 _uploading  = false; // document upload in progress
  String?              _uid;
  StreamSubscription<EmployeeProfileModel>? _sub;

  EmployeeProfileModel get profile    => _profile;
  ProfileSaveStatus    get status     => _status;
  String?              get error      => _error;
  bool                 get uploading  => _uploading;
  bool                 get isSaving   => _status == ProfileSaveStatus.saving;

  // ── Start / stop listening ────────────────────────────────────────────────

  void startListening(String uid) {
    if (_uid == uid) return; // already listening
    _uid = uid;
    _sub?.cancel();
    _sub = _firestore.watchEmployeeProfile(uid).listen(
      (profile) {
        _profile = profile;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Save profile details ──────────────────────────────────────────────────

  Future<String?> saveProfile({
    required String fullName,
    required String email,
    required String phone,
    required String address,
  }) async {
    if (_uid == null) return 'Not authenticated.';
    _setSaving();
    try {
      final updated = _profile.copyWith(
        fullName: fullName.trim(),
        email:    email.trim(),
        phone:    phone.trim(),
        address:  address.trim(),
      );
      await _firestore.updateEmployeeProfile(_uid!, updated);
      // Stream will auto-update _profile via the Firestore listener.
      _status = ProfileSaveStatus.success;
      notifyListeners();
      return null;
    } catch (e) {
      return _setError('Failed to save profile: $e');
    }
  }

  // ── Save payout details ───────────────────────────────────────────────────

  Future<String?> savePayoutDetails({
    required PayoutMethod payoutMethod,
    String? bankAccountNo,
    String? bankIfsc,
    String? upiId,
  }) async {
    if (_uid == null) return 'Not authenticated.';

    // Validate
    if (payoutMethod == PayoutMethod.bank) {
      if ((bankAccountNo ?? '').trim().isEmpty) {
        return 'Bank account number is required.';
      }
      if ((bankIfsc ?? '').trim().isEmpty) {
        return 'IFSC code is required.';
      }
    } else {
      if ((upiId ?? '').trim().isEmpty) {
        return 'UPI ID is required.';
      }
    }

    _setSaving();
    try {
      final updated = _profile.copyWith(
        payoutMethod:  payoutMethod,
        bankAccountNo: bankAccountNo?.trim(),
        bankIfsc:      bankIfsc?.trim(),
        upiId:         upiId?.trim(),
        // documentsVerified will be reset to "pending" by payoutPayload()
      );
      await _firestore.updateEmployeePayoutDetails(_uid!, updated);
      _status = ProfileSaveStatus.success;
      notifyListeners();
      return null;
    } catch (e) {
      return _setError('Failed to save payout details: $e');
    }
  }

  // ── Upload document ───────────────────────────────────────────────────────

  Future<String?> uploadDocument({
    required Uint8List  bytes,
    required String     mimeType,
    required String     documentType,
  }) async {
    if (_uid == null) return 'Not authenticated.';
    if (documentType.trim().isEmpty) return 'Please select a document type.';

    _uploading = true;
    notifyListeners();
    try {
      // 1 — Upload bytes to Storage → get path
      final path = await _storage.uploadDocument(_uid!, bytes, mimeType);

      // 2 — Append path reference to Firestore doc + reset verification
      await _firestore.appendEmployeeDocument(_uid!, path, documentType.trim());

      _uploading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _uploading = false;
      notifyListeners();
      return 'Upload failed: $e';
    }
  }

  // ── Remove document ───────────────────────────────────────────────────────

  Future<String?> removeDocument(String storagePath) async {
    if (_uid == null) return 'Not authenticated.';
    _setSaving();
    try {
      await _firestore.removeEmployeeDocument(_uid!, storagePath);
      _status = ProfileSaveStatus.success;
      notifyListeners();
      return null;
    } catch (e) {
      return _setError('Failed to remove document: $e');
    }
  }

  // ── Get download URL for a document ──────────────────────────────────────

  Future<String?> getDocumentUrl(String storagePath) async {
    try {
      return await _storage.getDownloadUrl(storagePath);
    } catch (e) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setSaving() {
    _status = ProfileSaveStatus.saving;
    _error  = null;
    notifyListeners();
  }

  String _setError(String message) {
    _status = ProfileSaveStatus.error;
    _error  = message;
    notifyListeners();
    return message;
  }

  void clearStatus() {
    _status = ProfileSaveStatus.idle;
    _error  = null;
    notifyListeners();
  }
}
