// lib/providers/auth_provider.dart
// APP-LEVEL provider. Holds auth state, role, and employee doc.
// Listens to Firebase Auth state changes; single source of truth for identity.
//
// IMPORTANT: This class extends ChangeNotifier and is passed directly as
// GoRouter's refreshListenable in main.dart — every notifyListeners() call
// causes the router to re-evaluate its redirect, making navigation automatic.

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/employee_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../core/constants.dart';

enum AuthStatus { unknown, unauthenticated, authenticated, accessDenied }

class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final FirestoreService _firestoreService;

  AuthStatus _status = AuthStatus.unknown;
  String? _role;
  EmployeeModel? _employee;
  String? _error;
  bool _loading = false;

  AuthStatus get status      => _status;
  String?    get role        => _role;
  EmployeeModel? get employee => _employee;
  String?    get error       => _error;
  bool       get loading     => _loading;

  bool get isEmployee => _role == AppConstants.roleEmployee;
  bool get isAdmin    => _role == AppConstants.roleAdmin;
  bool get isOwner    => _role == AppConstants.roleOwner;

  String? get uid => _authService.currentUid;
  User? get user => FirebaseAuth.instance.currentUser;
  String? get email => user?.email;

  AppAuthProvider({
    required AuthService authService,
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _firestoreService = firestoreService {
    // Listen to Firebase Auth state changes.
    // This fires on: sign-in, sign-out, token refresh, session expiry.
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _status   = AuthStatus.unauthenticated;
      _role     = null;
      _employee = null;
      _loading  = false;  // Clear any stale loading state
      notifyListeners();  // → GoRouter re-evaluates redirect → goes to /login
      return;
    }

    // Force-refresh the ID token to get the latest custom claims.
    // (Claims are set server-side by the seed script / admin functions.)
    IdTokenResult token;
    try {
      token = await user.getIdTokenResult(true);
    } catch (e) {
      // Token refresh failed — treat as unauthenticated to avoid stuck state.
      _status  = AuthStatus.unauthenticated;
      _role    = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final role = token.claims?[AppConstants.claimRole] as String?;

    if (role != AppConstants.roleEmployee &&
        role != AppConstants.roleAdmin &&
        role != AppConstants.roleOwner) {
      await _authService.signOut();
      _status  = AuthStatus.accessDenied;
      _error   = 'Access denied: invalid role for this portal.';
      _role    = null;
      _loading = false;
      notifyListeners();
      return;
    }

    _role   = role;
    _status = AuthStatus.authenticated;

    // Load employee Firestore doc (only for employee role)
    if (role == AppConstants.roleEmployee) {
      try {
        _employee = await _firestoreService.getEmployee(user.uid);
      } catch (_) {
        // Employee doc missing or Firestore error — still authenticated, just no doc
        _employee = null;
      }
    }

    _loading = false;
    notifyListeners(); // → GoRouter re-evaluates redirect → navigates to /businesses or /admin
  }

  /// Sign in with email and password.
  /// Returns an error string on failure, null on success.
  /// Navigation is handled automatically by GoRouter via refreshListenable.
  Future<String?> signIn(String email, String password) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final result = await _authService.signIn(email, password)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => const AuthResult(
              success: false,
              error: 'Sign-in timed out. Check your connection and try again.',
            ),
          );

      if (!result.success) {
        _loading = false;
        _error   = result.error;
        notifyListeners();
        return result.error;
      }

      // On success: _loading stays true until _onAuthStateChanged fires and
      // sets it to false after loading the employee doc and setting status.
      // This prevents a flash of the login form before navigation completes.
      return null;

    } catch (e) {
      _loading = false;
      _error   = 'Unexpected error: ${e.toString()}';
      notifyListeners();
      return _error;
    }
  }

  Future<void> signOut() async {
    _loading = false;
    await _authService.signOut();
    // _onAuthStateChanged fires and clears state / triggers router redirect.
  }

  /// Sends a password reset/setup link to the specified email address.
  /// Returns null on success or an error message on failure.
  Future<String?> sendPasswordResetEmail(String email) async {
    return await _authService.sendPasswordResetEmail(email);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
