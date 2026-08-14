// lib/services/qr_stub_service.dart
// Calls post-enrollment services after the Firestore batch commit.
//
// QR generation (doc 09): Calls the existing generateBranchQr callable.
//   The function is built — this is fire-and-forget (enrollment succeeds
//   even if QR generation fails; the admin can re-trigger from the panel).
//
// Owner provisioning (doc 02): STUB — not yet implemented.
//   When doc 02 is built, replace the TODO block with:
//     - Create Firebase Auth user for the owner
//     - Send magic-link / password-reset email
//     - Write owner_auth_uid back to businesses/{bizId}

import 'package:cloud_functions/cloud_functions.dart';
import '../core/constants.dart';

class QrStubService {
  final FirebaseFunctions _functions;

  QrStubService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Called after enrollment batch commit.
  /// [businessId] and [branchId] are the newly created document IDs.
  Future<void> postEnrollment({
    required String businessId,
    required String branchId,
    required String ownerEmail,
    required String ownerName,
  }) async {
    // ── QR/NFC generation (doc 09 — already built) ──────────────────────────
    try {
      await _functions.httpsCallable(AppConstants.fnGenerateBranchQr).call({
        'businessId': businessId,
        'branchId':   branchId,
      });
      // ignore: avoid_print
      print('QrStubService: QR generation triggered for branch $branchId');
    } on FirebaseFunctionsException catch (e) {
      // Non-fatal — admin can re-trigger from panel.
      // ignore: avoid_print
      print('QrStubService: QR generation failed (${e.code}): ${e.message}. Admin can retry.');
    } catch (e) {
      // ignore: avoid_print
      print('QrStubService: QR generation unexpected error: $e');
    }

    // ── Owner provisioning (doc 02) ──────────────────────────────────────────
    try {
      await _functions.httpsCallable('provisionOwner').call({
        'businessId': businessId,
      });
      // ignore: avoid_print
      print('QrStubService: Owner account provisioned for business $businessId');
    } catch (e) {
      // ignore: avoid_print
      print('QrStubService: Owner provisioning error (non-fatal, webhook will retry): $e');
    }
  }
}
