// lib/services/auth_service.dart
// Handles Firebase Auth sign-in, custom claim verification, sign-out.
// Role enforcement happens here — NOT just in UI.

import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants.dart';

class AuthResult {
  final bool success;
  final String? role;
  final String? error;
  const AuthResult({required this.success, this.role, this.error});
}

class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  FirebaseAuth get instance => _auth;

  /// Signs in with email and password, then verifies custom claim role.
  /// Returns the role string ('admin' | 'employee') or an error.
  Future<AuthResult> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        return const AuthResult(success: false, error: 'Sign-in failed: no user returned.');
      }

      // Force-refresh token so custom claims are up-to-date.
      final idToken = await user.getIdTokenResult(true);
      final role = idToken.claims?[AppConstants.claimRole] as String?;

      if (role == AppConstants.roleAdmin ||
          role == AppConstants.roleEmployee ||
          role == AppConstants.roleOwner) {
        return AuthResult(success: true, role: role);
      } else {
        // Reject at the app level — sign out immediately.
        await _auth.signOut();
        return const AuthResult(
          success: false,
          error: 'Access denied: this account does not have access to this portal.',
        );
      }
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _friendlyError(e));
    } catch (e) {
      return AuthResult(success: false, error: 'Unexpected error: $e');
    }
  }

  /// Sends a password reset email to set or reset account password.
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null; // success
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e);
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  /// Returns the current user's role from their token claims.
  /// Returns null if not signed in or claim is absent.
  Future<String?> getCurrentRole() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final token = await user.getIdTokenResult();
    return token.claims?[AppConstants.claimRole] as String?;
  }

  /// Returns the current user's UID, or null if not signed in.
  String? get currentUid => _auth.currentUser?.uid;

  Future<void> signOut() => _auth.signOut();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'This email is not registered in our system. Please check the email or contact admin.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been deactivated. Contact your admin.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Authentication error.';
    }
  }
}
