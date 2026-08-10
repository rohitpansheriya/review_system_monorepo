// lib/services/firestore_service.dart
// All Firestore reads and writes for the employee panel.
// Enforces: employee can only write businesses they enroll.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../core/constants.dart';
import '../models/branch_draft.dart';
import '../models/branch_model.dart';
import '../models/business_model.dart';
import '../models/commission_record_model.dart';
import '../models/employee_model.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // ── Employee ──────────────────────────────────────────────────────────────

  Future<EmployeeModel?> getEmployee(String uid) async {
    final doc = await _db.collection(AppConstants.colEmployees).doc(uid).get();
    if (!doc.exists) return null;
    return EmployeeModel.fromDoc(doc);
  }

  Stream<EmployeeModel?> watchEmployee(String uid) {
    return _db
        .collection(AppConstants.colEmployees)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? EmployeeModel.fromDoc(doc) : null);
  }

  // ── Category templates ────────────────────────────────────────────────────

  /// Returns all templates. If collection is empty, returns [].
  /// Never throws — graceful empty-state per doc 07 constraint.
  Future<List<Map<String, dynamic>>> getCategoryTemplates() async {
    try {
      final snap = await _db.collection(AppConstants.colTemplates).get();
      return snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Duplicate Place ID guard ────────────────────────────────────

  /// Returns true if any NON-draft business branch already has this Place ID.
  /// Drafts (pending_payment) are excluded so re-enrolling the same location
  /// after an abandoned draft doesn't create a false duplicate block.
  Future<bool> placeIdExists(String placeId) async {
    if (placeId.isEmpty) return false;
    // Check all branches with this place_id whose parent business is not a draft.
    // We do two queries: one for active, one for grace_period + deleted,
    // then combine — Firestore doesn't support != on collection group queries.
    // Simpler: query collectionGroup with the place_id, then filter in-memory
    // to exclude pending_payment parent docs (acceptable: small result set).
    final snap = await _db
        .collectionGroup(AppConstants.colBranches)
        .where('place_id', isEqualTo: placeId)
        .limit(10) // place_id duplicates should never be more than a handful
        .get();
    for (final branchDoc in snap.docs) {
      // Parent path: businesses/{bizId}/branches/{branchId}
      final bizId = branchDoc.reference.parent.parent?.id;
      if (bizId == null) continue;
      final bizSnap = await _db
          .collection(AppConstants.colBusinesses)
          .doc(bizId)
          .get();
      final status = bizSnap.data()?['subscription_status'] as String?;
      if (status != AppConstants.statusPendingPayment) {
        return true; // a paying business already has this Place ID
      }
    }
    return false;
  }

  // ── Enrollment — draft batch write (pending_payment) ──────────────────

  /// Atomically creates a DRAFT enrollment:
  ///   businesses/{bizId}            (subscription_status = "pending_payment")
  ///   businesses/{bizId}/branches/{id} × N  (one per BranchDraft)
  ///
  /// KEY DIFFERENCES from a fully-active enrollment:
  ///   • subscription_status = "pending_payment"  (not "active")
  ///   • renewal_date OMITTED — clock only starts on payment confirmation
  ///   • grace_period_ends OMITTED (rule: must be absent at create time)
  ///   • employee counters NOT incremented here — incremented in the
  ///     payment webhook (activateDraft) when payment is confirmed
  ///   • qr_code_id / nfc_tag_id = null on branches — generated on activation
  ///
  /// A draft is a complete, validated record — the ONLY thing missing is payment.
  /// Returns a map with 'businessId' and 'branchIds'.
  Future<Map<String, dynamic>> enrollBusiness({
    required String employeeId,
    required String brandName,
    required String logoUrl,
    required String categoryType,
    required String? templateId,
    required String ownerEmail,
    required String ownerName,
    required String ownerPhone,
    required List<BranchDraft> branches,
  }) async {
    assert(branches.isNotEmpty, 'Must enroll at least one branch');

    final bizRef = _db.collection(AppConstants.colBusinesses).doc();

    final batch = _db.batch();

    // 1 — Business document (draft — status = pending_payment, NO renewal clock)
    batch.set(bizRef, {
      'brand_name':                   brandName,
      'logo_url':                     logoUrl,
      'category_type':                categoryType,
      'default_category_template_id': templateId,
      'enrolled_by':                  employeeId,
      'enrolled_by_original':         employeeId,
      'currently_managed_by':         employeeId,
      // PENDING_PAYMENT: invisible to all production lifecycle jobs.
      'subscription_status':          AppConstants.statusPendingPayment,
      // renewal_date OMITTED: clock starts only in the payment webhook.
      // grace_period_ends OMITTED: security rules require this key to be absent.
      'owner_auth_uid':               null,  // STUB: set by doc-02 owner provisioning
      'owner_email':                  ownerEmail,
      'owner_name':                   ownerName,
      'owner_phone':                  ownerPhone,
      'created_at':                   FieldValue.serverTimestamp(),
    });

    // 2 — Branch subdocs (all in same batch — atomic, no orphan business)
    final branchIds = <String>[];
    for (final draft in branches) {
      final branchRef = bizRef.collection(AppConstants.colBranches).doc();
      batch.set(branchRef, draft.toFirestore());
      branchIds.add(branchRef.id);
    }

    // NOTE: employee counters (total_enrollments / this_month_enrollments) are
    // NOT incremented here. They increment in the payment webhook on activation
    // so that counts reflect PAID enrollments only.

    await batch.commit();
    return {'businessId': bizRef.id, 'branchIds': branchIds};
  }

  // ── My businesses — paginated, filtered, date-windowed ───────────────────

  /// Payment-status filter enum shared between provider and service.
  // (Defined here so service and provider share the same type without a third file.)

  /// Fetches ONE page of businesses for an employee.
  ///
  /// Parameters:
  ///   [employeeId]   — restricts to enrolled_by == employeeId
  ///   [statusFilter] — 'pending' | 'successful' | 'all'
  ///                    'successful' means active + grace_period (paid at some point)
  ///                    'all' means pending + successful; never includes 'deleted'
  ///   [since]        — lower bound on created_at (for 7-day default window)
  ///   [startAfter]   — cursor document for pagination (null = first page)
  ///   [limit]        — page size (default 20)
  ///
  /// Returns list of BusinessModel. Caller checks length < limit to know if more exist.
  Future<List<BusinessModel>> fetchMyBusinessesPage({
    required String employeeId,
    required String statusFilter,
    required DateTime since,
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.colBusinesses)
        .where('enrolled_by', isEqualTo: employeeId)
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('created_at', descending: true);

    // Apply status filter at query level — never in-memory
    if (statusFilter == 'pending') {
      q = q.where('subscription_status', isEqualTo: AppConstants.statusPendingPayment);
    } else if (statusFilter == 'successful') {
      q = q.where('subscription_status',
          whereIn: [AppConstants.statusActive, AppConstants.statusGracePeriod]);
    } else {
      // 'all' → exclude deleted only
      q = q.where('subscription_status',
          whereNotIn: [AppConstants.statusDeleted]);
    }

    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }

    final snap = await q.limit(limit).get();
    return snap.docs.map(BusinessModel.fromDoc).toList();
  }

  /// Returns the last DocumentSnapshot from a page for cursor-based pagination.
  /// Callers use this as [startAfter] for the next page.
  Future<DocumentSnapshot?> getLastDoc(String businessId) async {
    final doc = await _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .get();
    return doc.exists ? doc : null;
  }

  /// Returns all branches for a given business as a one-shot read.
  /// Used by BusinessDetailScreen and BusinessEditScreen.
  Future<List<BranchModel>> getBranches(String businessId) async {
    final snap = await _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection(AppConstants.colBranches)
        .get();
    return snap.docs
        .map((doc) => BranchModel.fromDoc(doc, businessId: businessId))
        .toList();
  }

  // ── Edit — employee can fix enrollment mistakes ───────────────────────────

  /// Updates allowed business-level fields.
  /// NEVER passes payment/lifecycle fields through — both client-side strip
  /// and server-side security rules enforce this.
  Future<void> updateBusiness(String businessId, {
    required String brandName,
    required String logoUrl,
    required String categoryType,
    String? templateId,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
  }) async {
    await _db.collection(AppConstants.colBusinesses).doc(businessId).update({
      'brand_name':                   brandName,
      'logo_url':                     logoUrl,
      'category_type':                categoryType,
      'default_category_template_id': templateId,
      'owner_name':                   ownerName,
      'owner_email':                  ownerEmail,
      'owner_phone':                  ownerPhone,
      // Payment/lifecycle fields intentionally omitted:
      // subscription_status, renewal_date, grace_period_ends,
      // enrolled_by, enrolled_by_original, owner_auth_uid — never touched here.
    });
  }

  /// Updates allowed branch-level fields.
  /// Explicitly blocks stats_summary (Cloud Function writes only).
  Future<void> updateBranch(
    String businessId,
    String branchId, {
    required String branchName,
    required String address,
    required String whatsappNumber,
    required String whatsappMonitoredBy,
    String? placeId,
    String? googleReviewLink,
    required Map<String, String> starRoutingConfig,
    String? categoryOverrideId,
    String? standeeStatus,
  }) async {
    final data = <String, dynamic>{
      'branch_name':           branchName,
      'address':               address,
      'whatsapp_number':       whatsappNumber,
      'whatsapp_monitored_by': whatsappMonitoredBy,
      'place_id':              placeId,
      'google_review_link':    googleReviewLink,
      'star_routing_config':   starRoutingConfig,
      'category_override_id':  categoryOverrideId,
    };
    if (standeeStatus != null &&
        AppConstants.standeeStatuses.contains(standeeStatus)) {
      data['standee_status']            = standeeStatus;
      data['standee_status_updated_at'] = FieldValue.serverTimestamp();
    }
    // stats_summary intentionally omitted — Cloud Function writes only.
    await _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection(AppConstants.colBranches)
        .doc(branchId)
        .update(data);
  }

  // ── Delete — pending_payment drafts only ─────────────────────────────────

  /// Deletes a draft business (pending_payment) and ALL its branch subdocs.
  /// Called only when subscription_status == "pending_payment" — enforced
  /// here client-side AND by Firestore security rules server-side.
  /// commission_records are intentionally NOT deleted (audit trail).
  Future<void> deleteDraftBusiness(String businessId) async {
    final batch = _db.batch();

    // 1 — delete all branch subdocs
    final branchSnap = await _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection(AppConstants.colBranches)
        .get();
    for (final doc in branchSnap.docs) {
      batch.delete(doc.reference);
    }

    // 2 — delete the business doc itself
    batch.delete(_db.collection(AppConstants.colBusinesses).doc(businessId));

    await batch.commit();
  }

  // ── Duplicate Place ID guard (edit variant) ───────────────────────────────

  /// Same as placeIdExists() but excludes [currentBusinessId] so editing
  /// an existing business with its own Place ID doesn't self-block.
  Future<bool> placeIdExistsForEdit(String placeId, String currentBusinessId) async {
    if (placeId.isEmpty) return false;
    final snap = await _db
        .collectionGroup(AppConstants.colBranches)
        .where('place_id', isEqualTo: placeId)
        .limit(10)
        .get();
    for (final branchDoc in snap.docs) {
      final bizId = branchDoc.reference.parent.parent?.id;
      if (bizId == null || bizId == currentBusinessId) continue;
      final bizSnap = await _db
          .collection(AppConstants.colBusinesses)
          .doc(bizId)
          .get();
      final status = bizSnap.data()?['subscription_status'] as String?;
      if (status != AppConstants.statusPendingPayment) return true;
    }
    return false;
  }

  // ── Standee fulfillment (Change 2) ────────────────────────────────────────

  /// Updates standee_status + standee_status_updated_at for a branch.
  /// Only valid status values from AppConstants.standeeStatuses are accepted.
  /// The employee uses this to track the physical acrylic standee lifecycle.
  Future<void> updateStandeeStatus(
    String businessId,
    String branchId,
    String newStatus,
  ) async {
    assert(
      AppConstants.standeeStatuses.contains(newStatus),
      'Invalid standee status: $newStatus',
    );
    await _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection(AppConstants.colBranches)
        .doc(branchId)
        .update({
      'standee_status':            newStatus,
      'standee_status_updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Plain printable QR download (Change 1) ────────────────────────────────

  /// Returns a download URL for the plain printable QR PNG stored at
  /// [storagePath] (e.g. "qr_codes/{branchId}_plain.png").
  ///
  /// Firebase Storage `getDownloadURL()` returns a URL that is valid until
  /// the file is deleted or the Storage bucket's token is rotated.
  /// On the web the URL is returned directly without needing a signed URL.
  Future<String> getPlainQrDownloadUrl(String storagePath) async {
    final ref = FirebaseStorage.instance.ref(storagePath);
    return ref.getDownloadURL();
  }

  // ── Resend payment link (Change 3) ────────────────────────────────────────

  /// Calls the resendPaymentLink Cloud Function for a pending_payment business.
  /// Returns { shortUrl, paymentLinkId } from the function.
  Future<Map<String, dynamic>> resendPaymentLink(String businessId) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final result = await fn
        .httpsCallable(AppConstants.fnResendPaymentLink)
        .call({'businessId': businessId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── Commission records ────────────────────────────────────────────────────

  Stream<List<CommissionRecordModel>> watchMyCommissions(String employeeId) {
    return _db
        .collection(AppConstants.colCommission)
        .where('employee_id', isEqualTo: employeeId)
        .orderBy('date_claimed', descending: true)
        .snapshots()
        .asyncMap((snap) async {
          // Join business names client-side (no cross-collection query needed)
          final results = <CommissionRecordModel>[];
          for (final doc in snap.docs) {
            final record = CommissionRecordModel.fromDoc(doc);
            String? bizName;
            try {
              final biz = await _db
                  .collection(AppConstants.colBusinesses)
                  .doc(record.businessId)
                  .get();
              bizName = biz.data()?['brand_name'] as String?;
            } catch (_) {}
            results.add(CommissionRecordModel.fromDoc(doc, businessName: bizName));
          }
          return results;
        });
  }

  /// Creates a cash commission record (status = "pending").
  /// Two-step verification (doc 06) is deferred — record stays pending.
  Future<void> logCashPayment({
    required String employeeId,
    required String businessId,
    required double amount,
  }) async {
    await _db.collection(AppConstants.colCommission).add(
      CommissionRecordModel.newCashRecord(
        employeeId: employeeId,
        businessId: businessId,
        amount: amount,
      ),
    );
  }
}
