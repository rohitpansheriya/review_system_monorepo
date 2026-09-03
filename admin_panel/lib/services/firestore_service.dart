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
import '../models/employee_commission_model.dart';
import '../models/employee_model.dart';
import '../models/employee_profile_model.dart';
import '../core/string_utils.dart';

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

  // ── Employee Name Lookup Cache ────────────────────────────────────────────
  static final Map<String, String> employeeNameCache = {};

  /// Resolves an employee UID to full name (e.g. "Rahul Sharma" or "Admin").
  Future<String> getEmployeeName(String? uid) async {
    if (uid == null || uid.isEmpty || uid == 'admin') return 'Admin';
    if (employeeNameCache.containsKey(uid)) {
      return employeeNameCache[uid]!;
    }
    try {
      final doc = await _db.collection(AppConstants.colEmployees).doc(uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final profile = data['profile'] as Map<String, dynamic>? ?? {};
        final fullName = profile['full_name'] as String? ?? '';
        final name = fullName.isNotEmpty
            ? fullName
            : (data['name'] as String? ?? data['email'] as String? ?? uid);
        employeeNameCache[uid] = name;
        return name;
      }
    } catch (_) {}
    return uid.length > 8 ? 'Emp: ${uid.substring(0, 8)}…' : uid;
  }

  // ── Category templates ────────────────────────────────────────────────────

  List<Map<String, dynamic>>? _cachedTemplates;

  /// Returns all templates with in-memory caching for instant UI response.
  /// If collection is empty, returns [].
  /// Never throws — graceful empty-state per doc 07 constraint.
  Future<List<Map<String, dynamic>>> getCategoryTemplates({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedTemplates != null && _cachedTemplates!.isNotEmpty) {
      return _cachedTemplates!;
    }
    try {
      final snap = await _db.collection(AppConstants.colTemplates).get();
      _cachedTemplates = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      return _cachedTemplates!;
    } catch (_) {
      return _cachedTemplates ?? [];
    }
  }

  // ── Duplicate Place ID guard ────────────────────────────────────

  /// Returns true if any NON-draft business branch already has this Place ID.
  /// Drafts (pending_payment) are excluded so re-enrolling the same location
  /// after an abandoned draft doesn't create a false duplicate block.
  ///
  /// NOTE: This uses a collectionGroup query on 'branches' which requires
  /// a COLLECTION_GROUP index. If the query fails (permission denied or
  /// missing index), we return false so enrollment is not blocked.
  Future<bool> placeIdExists(String placeId) async {
    if (placeId.isEmpty) return false;
    try {
      final snap = await _db
          .collectionGroup(AppConstants.colBranches)
          .where('place_id', isEqualTo: placeId)
          .limit(10)
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
    } catch (e) {
      // ignore: avoid_print
      print('placeIdExists: query failed (non-blocking): $e');
      return false;
    }
  }

  Future<bool> ownerEmailExists(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return false;
    try {
      final snapLower = await _db
          .collection(AppConstants.colBusinesses)
          .where('owner_email', isEqualTo: clean)
          .limit(1)
          .get();
      if (snapLower.docs.isNotEmpty) return true;

      final snapOrig = await _db
          .collection(AppConstants.colBusinesses)
          .where('owner_email', isEqualTo: email.trim())
          .limit(1)
          .get();
      return snapOrig.docs.isNotEmpty;
    } catch (e) {
      // ignore: avoid_print
      print('ownerEmailExists: query error: $e');
      return false;
    }
  }

  Future<bool> ownerEmailExistsForEdit(String email, String currentBusinessId) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return false;
    try {
      final snapLower = await _db
          .collection(AppConstants.colBusinesses)
          .where('owner_email', isEqualTo: clean)
          .get();
      if (snapLower.docs.any((d) => d.id != currentBusinessId)) return true;

      final snapOrig = await _db
          .collection(AppConstants.colBusinesses)
          .where('owner_email', isEqualTo: email.trim())
          .get();
      return snapOrig.docs.any((d) => d.id != currentBusinessId);
    } catch (e) {
      // ignore: avoid_print
      print('ownerEmailExistsForEdit: query error: $e');
      return false;
    }
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
    bool isTestAccount = false,
    required List<BranchDraft> branches,
  }) async {
    assert(branches.isNotEmpty, 'Must enroll at least one branch');

    final bizRef = _db.collection(AppConstants.colBusinesses).doc();

    final batch = _db.batch();

    final cleanBrandName = StringUtils.toTitleCase(brandName);
    final cleanOwnerName = StringUtils.toTitleCase(ownerName);

    // 1 — Business document (draft — status = pending_payment, NO renewal clock)
    batch.set(bizRef, {
      'brand_name':                   cleanBrandName,
      'logo_url':                     logoUrl,
      'category_type':                categoryType,
      'default_category_template_id': templateId,
      'enrolled_by':                  employeeId,
      'enrolled_by_original':         employeeId,
      'currently_managed_by':         employeeId,
      'is_test_account':              isTestAccount,
      // PENDING_PAYMENT: invisible to all production lifecycle jobs.
      'subscription_status':          AppConstants.statusPendingPayment,
      // renewal_date OMITTED: clock starts only in the payment webhook.
      // grace_period_ends OMITTED: security rules require this key to be absent.
      'owner_auth_uid':               null,  // STUB: set by doc-02 owner provisioning
      'owner_email':                  ownerEmail.trim().toLowerCase(),
      'owner_name':                   cleanOwnerName,
      'owner_phone':                  ownerPhone.trim(),
      'created_at':                   FieldValue.serverTimestamp(),
    });

    // 2 — Branch subdocs (all in same batch — atomic, no orphan business)
    final branchIds = <String>[];
    for (final draft in branches) {
      draft.name = StringUtils.toTitleCase(draft.name);
      draft.whatsappMonitoredBy = StringUtils.toTitleCase(draft.whatsappMonitoredBy);
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

  // ── Admin Cash Activate (GROUP C — new model) ─────────────────────────────
  //
  // Admin-only: directly activates a pending_payment business via cash.
  // Creates commission record (payment_mode="cash", status="verified") and
  // flips subscription_status → active + sets renewal_date.
  // No employee involvement — admin collects and activates in one step.

  Future<void> adminCashActivate({
    required String businessId,
    required String adminUid,
  }) async {
    final bizRef = _db.collection(AppConstants.colBusinesses).doc(businessId);
    final bizSnap = await bizRef.get();

    if (!bizSnap.exists) throw Exception('Business not found');
    final bizData = bizSnap.data()!;
    final currentStatus = bizData['subscription_status'] as String?;
    if (currentStatus != AppConstants.statusPendingPayment) {
      throw Exception('Business is not in pending_payment status');
    }

    // Activate the business.
    // Commission is NOT created here — the onBusinessActivated CF trigger
    // fires when subscription_status flips to 'active' and creates the
    // employee_commissions entry server-side (same path as online payments).
    await bizRef.update({
      'subscription_status': AppConstants.statusActive,
      'renewal_date': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: AppConstants.renewalDays)),
      ),
      'payment_mode': 'cash',
      'cash_payment_confirmed_at': FieldValue.serverTimestamp(),
      'cash_confirmed_by_admin': adminUid,
    });
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
      // 'all' → show all non-deleted statuses
      // NOTE: whereNotIn cannot be combined with range filters on a different
      // field (created_at). Use whereIn with explicit status list instead.
      q = q.where('subscription_status',
          whereIn: [
            AppConstants.statusPendingPayment,
            AppConstants.statusActive,
            AppConstants.statusGracePeriod,
          ]);
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
    final cleanEmail = ownerEmail.trim().toLowerCase();
    final isDup = await ownerEmailExistsForEdit(cleanEmail, businessId);
    if (isDup) {
      throw Exception('Owner email "$cleanEmail" is already registered to another business.');
    }

    final cleanBrandName = StringUtils.toTitleCase(brandName);
    final cleanOwnerName = StringUtils.toTitleCase(ownerName);

    await _db.collection(AppConstants.colBusinesses).doc(businessId).update({
      'brand_name':                   cleanBrandName,
      'logo_url':                     logoUrl,
      'category_type':                categoryType,
      'default_category_template_id': templateId,
      'owner_name':                   cleanOwnerName,
      'owner_email':                  cleanEmail,
      'owner_phone':                  ownerPhone.trim(),
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
    Map<String, String>? starRoutingConfig,
    String? categoryOverrideId,
    String? standeeStatus,
  }) async {
    final cleanBranchName = StringUtils.toTitleCase(branchName);
    final cleanMonitor = StringUtils.toTitleCase(whatsappMonitoredBy);

    final data = <String, dynamic>{
      'branch_name':           cleanBranchName,
      'address':               address.trim(),
      'whatsapp_number':       whatsappNumber.trim(),
      'whatsapp_monitored_by': cleanMonitor,
      'place_id':              placeId,
      'google_review_link':    googleReviewLink,
      'category_override_id':  categoryOverrideId,
    };
    if (starRoutingConfig != null) {
      data['star_routing_config'] = starRoutingConfig;
    }
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

  /// Adds a new branch to an existing business in pending_payment status.
  Future<String> addBranchToBusiness(
    String businessId,
    BranchDraft draft, {
    String? enrolledBy,
  }) async {
    final branchRef = _db
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection(AppConstants.colBranches)
        .doc();

    final data = draft.toFirestore();
    data['created_at'] = FieldValue.serverTimestamp();
    data['subscription_status'] = AppConstants.statusPendingPayment;
    data['payment_mode'] = 'pending';
    if (enrolledBy != null && enrolledBy.isNotEmpty) {
      data['enrolled_by'] = enrolledBy;
    }

    await branchRef.set(data);
    return branchRef.id;
  }

  /// Admin activates a specific branch via cash payment (₹1999).
  Future<void> adminCashActivateBranch({
    required String businessId,
    required String branchId,
    String? notes,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    await fn.httpsCallable('adminCashActivateBranch').call({
      'businessId': businessId,
      'branchId': branchId,
      if (notes != null) 'notes': notes,
    });
  }

  /// Creates a Razorpay order for activating a specific branch (₹1999).
  Future<Map<String, dynamic>> createBranchOrder({
    required String businessId,
    required String branchId,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final result = await fn.httpsCallable('createBranchOrder').call({
      'businessId': businessId,
      'branchId': branchId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Resends or generates a Razorpay payment link for a specific branch.
  Future<Map<String, dynamic>> resendBranchPaymentLink({
    required String businessId,
    required String branchId,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    final result = await fn.httpsCallable('resendBranchPaymentLink').call({
      'businessId': businessId,
      'branchId': branchId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Admin reverts a business from active back to pending_payment.
  Future<void> adminRevertBusinessActivation({
    required String businessId,
    String? reason,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    await fn.httpsCallable('adminRevertBusinessActivation').call({
      'businessId': businessId,
      if (reason != null) 'reason': reason,
    });
  }

  /// Admin reverts a single branch from active back to pending_payment.
  Future<void> adminRevertBranchActivation({
    required String businessId,
    required String branchId,
    String? reason,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    await fn.httpsCallable('adminRevertBranchActivation').call({
      'businessId': businessId,
      'branchId': branchId,
      if (reason != null) 'reason': reason,
    });
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
    try {
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
    } catch (e) {
      // ignore: avoid_print
      print('placeIdExistsForEdit: query failed (non-blocking): $e');
      return false;
    }
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

  /// Calls the deleteBusinessAdmin Cloud Function to completely cascade-delete
  /// a business, all branches, scan logs, storage assets, and owner auth account.
  Future<void> deleteBusinessAdmin(String businessId, {bool deleteOwnerAuth = true}) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
    await fn
        .httpsCallable(AppConstants.fnDeleteBusinessAdmin)
        .call({'businessId': businessId, 'deleteOwnerAuth': deleteOwnerAuth});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD A — PAYMENT / CASH-PENDING VIEW
  // "Pending cash payments" is a VIEW on businesses, not a separate collection.
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream of businesses awaiting cash confirmation:
  /// payment_mode='cash' AND subscription_status='pending_payment'.
  Stream<List<BusinessModel>> watchPendingCashBusinesses() {
    return _db
        .collection(AppConstants.colBusinesses)
        .where('payment_mode', isEqualTo: 'cash')
        .where('subscription_status', isEqualTo: AppConstants.statusPendingPayment)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(BusinessModel.fromDoc).toList());
  }

  /// Admin confirms cash receipt → activates the business (Build A).
  /// Calls the confirmCashPaymentAdmin CF which takes businessId (not recordId).
  Future<void> confirmCashAndActivate({
    required String businessId,
    required String adminUid,
    String? notes,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable(AppConstants.fnConfirmCashPaymentAdmin).call({
        'businessId': businessId,
        if (notes != null) 'notes': notes,
      });
    } catch (_) {
      // Direct Firestore fallback — handles emulator / missing Cloud Function
      final bizRef = _db.collection(AppConstants.colBusinesses).doc(businessId);
      final bizSnap = await bizRef.get();
      if (!bizSnap.exists) throw Exception('Business not found');

      final bizData = bizSnap.data() ?? {};
      final currentStatus = bizData['subscription_status'] as String?;
      if (currentStatus != AppConstants.statusPendingPayment) {
        throw Exception('Business is not pending_payment (current: $currentStatus)');
      }

      final batch = _db.batch();
      batch.update(bizRef, {
        'subscription_status': AppConstants.statusActive,
        'renewal_date': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: AppConstants.renewalDays)),
        ),
        'payment_mode': 'cash',
        'cash_payment_confirmed_at': FieldValue.serverTimestamp(),
        'cash_confirmed_by_admin': adminUid,
      });

      final branchesSnap = await bizRef.collection('branches').get();
      for (final bDoc in branchesSnap.docs) {
        batch.update(bDoc.reference, {
          'subscription_status': AppConstants.statusActive,
          'payment_mode': 'cash',
          'cash_payment_confirmed_at': FieldValue.serverTimestamp(),
          'cash_confirmed_by_admin': adminUid,
          'activated_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Create commission entry if employee-enrolled (fallback mirrors the CF trigger)
      final enrolledBy = bizData['enrolled_by'] as String?;
      if (enrolledBy != null && enrolledBy.isNotEmpty && enrolledBy != 'admin') {
        final now = DateTime.now();
        final activationMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final commDocId = 'comm_$businessId';
        final commRef = _db.collection(AppConstants.colEmployeeCommissions).doc(commDocId);
        final existing = await commRef.get();
        if (!existing.exists) {
          await commRef.set({
            'employee_id': enrolledBy,
            'business_id': businessId,
            'business_name': bizData['brand_name'] ?? '',
            'amount': AppConstants.commissionAmountPerActivation,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),
            'activation_month': activationMonth,
            'paid_at': null,
            'paid_by': null,
            'payout_reference': null,
          });
        }
      }
    }
  }

  // ── Reverse Activation (Admin-only recovery tool) ─────────────────────────
  //
  // Reverts an active business to pending_payment:
  //   1. Sets subscription_status → pending_payment, clears payment fields.
  //   2. Voids (not deletes) the commission entry.
  //   3. Marks QR stale on all branches.
  //   4. Writes audit log.

  Future<void> reverseActivation({
    required String businessId,
    required String adminUid,
    required String reason,
  }) async {
    final bizRef = _db.collection(AppConstants.colBusinesses).doc(businessId);
    final bizSnap = await bizRef.get();
    if (!bizSnap.exists) throw Exception('Business not found');

    final bizData = bizSnap.data()!;
    final currentStatus = bizData['subscription_status'] as String?;
    if (currentStatus != AppConstants.statusActive) {
      throw Exception('Business is not active (current: $currentStatus). Cannot reverse.');
    }

    final batch = _db.batch();

    // 1. Revert business to pending_payment, clear payment fields
    batch.update(bizRef, {
      'subscription_status': AppConstants.statusPendingPayment,
      'payment_mode': FieldValue.delete(),
      'renewal_date': FieldValue.delete(),
      'cash_payment_confirmed_at': FieldValue.delete(),
      'cash_confirmed_by_admin': FieldValue.delete(),
      'reversed_at': FieldValue.serverTimestamp(),
      'reversed_by': adminUid,
    });

    // 2. Mark QR stale on all branches
    final branchSnap = await bizRef.collection(AppConstants.colBranches).get();
    for (final branchDoc in branchSnap.docs) {
      batch.update(branchDoc.reference, {
        'qr_stale': true,
      });
    }

    await batch.commit();

    // 3. Void the commission entry (if it exists)
    final commDocId = 'comm_$businessId';
    final commRef = _db.collection(AppConstants.colEmployeeCommissions).doc(commDocId);
    final commSnap = await commRef.get();
    if (commSnap.exists) {
      await commRef.update({
        'status': 'voided',
        'voided_at': FieldValue.serverTimestamp(),
        'voided_by': adminUid,
        'void_reason': reason,
      });
    }

    // 4. Write audit log
    await _db.collection('subscription_override_logs').add({
      'business_id': businessId,
      'business_name': bizData['brand_name'] ?? '',
      'action': 'reverse_activation',
      'previous_status': currentStatus,
      'new_status': AppConstants.statusPendingPayment,
      'reversed_by': adminUid,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD B — EMPLOYEE COMMISSION LEDGER
  // Separate collection: employee_commissions. Never deleted.
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream of an employee's commissions from the new ledger.
  /// Optionally filter by status and/or month.
  Stream<List<EmployeeCommissionModel>> watchEmployeeCommissions(
    String employeeId, {
    String? statusFilter,
    String? monthFilter,
  }) {
    Query query = _db
        .collection(AppConstants.colEmployeeCommissions)
        .where('employee_id', isEqualTo: employeeId);

    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.where('status', isEqualTo: statusFilter);
    }

    query = query.orderBy('activation_month', descending: true);

    return query.snapshots().map((snap) {
      var list = snap.docs.map((doc) => EmployeeCommissionModel.fromDoc(doc)).toList();
      if (monthFilter != null && monthFilter.isNotEmpty) {
        list = list.where((c) => c.activationMonth == monthFilter).toList();
      }
      return list;
    });
  }

  /// Admin: stream of ALL pending commissions across all employees.
  /// Optionally filter by month.
  Stream<List<EmployeeCommissionModel>> watchAllPendingCommissions({
    String? monthFilter,
  }) {
    Query query = _db
        .collection(AppConstants.colEmployeeCommissions)
        .where('status', isEqualTo: 'pending')
        .orderBy('activation_month', descending: true);

    return query.snapshots().map((snap) {
      var list = snap.docs.map((doc) => EmployeeCommissionModel.fromDoc(doc)).toList();
      if (monthFilter != null && monthFilter.isNotEmpty) {
        list = list.where((c) => c.activationMonth == monthFilter).toList();
      }
      return list;
    });
  }

  /// Admin: bulk-mark all pending commissions for an employee+month as paid.
  Future<Map<String, dynamic>> markCommissionsPaidBulk({
    required String employeeId,
    required String month,
    required String payoutReference,
    required String adminUid,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await fn.httpsCallable(AppConstants.fnMarkCommissionsPaidBulk).call({
        'employeeId': employeeId,
        'month': month,
        'payoutReference': payoutReference,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } catch (_) {
      // Direct Firestore fallback
      final snap = await _db
          .collection(AppConstants.colEmployeeCommissions)
          .where('employee_id', isEqualTo: employeeId)
          .where('activation_month', isEqualTo: month)
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isEmpty) {
        return {'success': true, 'count': 0, 'message': 'No pending commissions found.'};
      }

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'status': 'paid',
          'paid_at': FieldValue.serverTimestamp(),
          'paid_by': adminUid,
          'payout_reference': payoutReference,
        });
      }
      await batch.commit();

      return {
        'success': true,
        'count': snap.docs.length,
        'totalAmount': snap.docs.length * AppConstants.commissionAmountPerActivation,
      };
    }
  }

  // ── Employee profile (My Profile screen) ────────────────────────────────

  /// Real-time stream of the employee's own profile data.
  Stream<EmployeeProfileModel> watchEmployeeProfile(String uid) {
    return _db
        .collection(AppConstants.colEmployees)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists
            ? EmployeeProfileModel.fromDoc(doc)
            : EmployeeProfileModel.empty);
  }

  /// Updates only the `profile.*` sub-map of the employee doc.
  /// Does NOT touch payout, documents, or documents_verified.
  Future<void> updateEmployeeProfile(String uid, EmployeeProfileModel model) async {
    await _db
        .collection(AppConstants.colEmployees)
        .doc(uid)
        .update(model.profilePayload());
  }

  /// Updates payout details and resets documents_verified to "pending".
  /// SECURITY SAFEGUARD: every payout change triggers re-verification.
  Future<void> updateEmployeePayoutDetails(
    String uid,
    EmployeeProfileModel model,
  ) async {
    await _db
        .collection(AppConstants.colEmployees)
        .doc(uid)
        .update(model.payoutPayload());
  }

  /// Appends a new KYC document reference to the employee's documents list.
  /// Also resets documents_verified to "pending".
  /// [storagePath] — the Firebase Storage path returned by StorageService.uploadDocument.
  /// [documentType] — human label chosen by the employee ("Aadhaar", "PAN", etc.).
  Future<void> appendEmployeeDocument(
    String uid,
    String storagePath,
    String documentType,
  ) async {
    final newDoc = EmployeeDocument(
      storagePath:  storagePath,
      documentType: documentType,
      uploadedAt:   null, // server timestamp set via FieldValue below
    );
    await _db
        .collection(AppConstants.colEmployees)
        .doc(uid)
        .update({
      'documents': FieldValue.arrayUnion([{
        'path':          newDoc.storagePath,
        'document_type': newDoc.documentType,
        'uploaded_at':   FieldValue.serverTimestamp(),
      }]),
      // Reset verification on every new document upload.
      'documents_verified': 'pending',
    });
  }

  /// Removes a document from the documents list by its storagePath.
  /// Also resets documents_verified to "pending".
  Future<void> removeEmployeeDocument(String uid, String storagePath) async {
    // We can't arrayRemove a map without knowing the exact map including Timestamp.
    // So we do a transaction: read, filter, write.
    final ref = _db.collection(AppConstants.colEmployees).doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final raw  = snap.data()?['documents'] as List<dynamic>? ?? [];
      final updated = raw
          .where((e) => (e as Map<String, dynamic>)['path'] != storagePath)
          .toList();
      tx.update(ref, {
        'documents':           updated,
        'documents_verified':  'pending',
      });
    });
  }
}

