// lib/providers/admin_dashboard_provider.dart
//
// Admin Dashboard State Provider (Doc 04 Admin Panel).
// Manages platform-wide count() stats (Scalability Rule #3), employee management,
// template CRUD, subscription overrides, and commission verification queue.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/branch_model.dart';
import '../models/business_model.dart';
import '../models/employee_commission_model.dart';
import '../models/employee_profile_model.dart';
import '../models/standee_fulfillment_model.dart';
import '../services/category_template_service.dart';
import '../services/firestore_service.dart';

class AdminDashboardProvider extends ChangeNotifier {
  final FirebaseFirestore _db;
  final FirestoreService _firestoreService;
  final CategoryTemplateService _templateService;

  bool _loading = false;
  String? _error;

  // ── Platform-Wide Stats (count() aggregations per Scalability Rule #3) ─────
  int _totalBusinessesCount = 0;
  int _activeBusinessesCount = 0;
  int _graceBusinessesCount = 0;
  int _pendingDraftsCount = 0;
  int _totalEmployeesCount = 0;

  int _renewalsDue30 = 0;
  int _renewalsDue15 = 0;
  int _renewalsDue7 = 0;
  int _renewalsDue1 = 0;

  double _revenueSnapshot = 0.0;
  double _onlineRevenue = 0.0;
  double _cashRevenue = 0.0;
  int _totalActiveBranches = 0;
  int _totalPendingBranches = 0;
  int _onlinePaymentsCount = 0;
  int _cashPaymentsCount = 0;

  // ── Employee Management State ──────────────────────────────────────────────
  List<EmployeeProfileModel> _employees = [];
  final Map<String, List<BusinessModel>> _employeeBusinesses = {};
  final Map<String, Map<String, double>> _employeeCommissionSummaries = {};
  final Map<String, int> _employeeTotalEnrollments = {};
  final Map<String, int> _employeeThisMonthEnrollments = {};
  final Map<String, int> _employeeManagedCount = {};

  // ── Category Template Library State ────────────────────────────────────────
  List<Map<String, dynamic>> _templates = [];
  final Map<String, List<String>> _categoryPhrasesCache = {};
  final Set<String> _loadingCategories = {};

  // ── All Businesses List (for Subscription Overrides & Management) ────────
  List<BusinessModel> _allBusinesses = [];
  final Map<String, List<BranchModel>> _businessBranches = {};
  final Map<String, ({int active, int pending, int total})> _businessBranchStats = {};

  // ── Standee Fulfillment State ──────────────────────────────────────────────
  List<StandeeFulfillmentModel> _standeeItems = [];
  bool _standeeLoading = false;
  String? _standeeError;

  // Getters
  bool get loading => _loading;
  String? get error => _error;

  int get totalBusinessesCount => _totalBusinessesCount;
  int get activeBusinessesCount => _activeBusinessesCount;
  int get graceBusinessesCount => _graceBusinessesCount;
  int get pendingDraftsCount => _pendingDraftsCount;
  int get totalEmployeesCount => _totalEmployeesCount;

  int get renewalsDue30 => _renewalsDue30;
  int get renewalsDue15 => _renewalsDue15;
  int get renewalsDue7 => _renewalsDue7;
  int get renewalsDue1 => _renewalsDue1;

  double get revenueSnapshot => _revenueSnapshot;
  double get onlineRevenue => _onlineRevenue;
  double get cashRevenue => _cashRevenue;
  int get totalActiveBranches => _totalActiveBranches;
  int get totalPendingBranches => _totalPendingBranches;
  int get onlinePaymentsCount => _onlinePaymentsCount;
  int get cashPaymentsCount => _cashPaymentsCount;

  List<EmployeeProfileModel> get employees => _employees;
  Map<String, List<BusinessModel>> get employeeBusinesses => _employeeBusinesses;
  Map<String, Map<String, double>> get employeeCommissionSummaries => _employeeCommissionSummaries;
  Map<String, int> get employeeTotalEnrollments => _employeeTotalEnrollments;
  Map<String, int> get employeeThisMonthEnrollments => _employeeThisMonthEnrollments;
  Map<String, int> get employeeManagedCount => _employeeManagedCount;

  List<Map<String, dynamic>> get templates => _templates;
  List<BusinessModel> get allBusinesses => _allBusinesses;
  Map<String, List<BranchModel>> get businessBranches => _businessBranches;
  Map<String, ({int active, int pending, int total})> get businessBranchStats => _businessBranchStats;
  List<StandeeFulfillmentModel> get standeeItems => _standeeItems;
  bool get standeeLoading => _standeeLoading;
  String? get standeeError => _standeeError;

  AdminDashboardProvider({
    FirebaseFirestore? firestore,
    FirestoreService? firestoreService,
    CategoryTemplateService? templateService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _firestoreService = firestoreService ?? FirestoreService(db: firestore ?? FirebaseFirestore.instance),
        _templateService = templateService ?? CategoryTemplateService(firestore: firestore ?? FirebaseFirestore.instance);

  /// Load initial admin overview & stats.
  Future<void> loadAdminData() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        refreshPlatformStats(),
        fetchEmployees(),
        fetchTemplates(),
        fetchAllBusinesses(),
        fetchStandeeFulfillments(),
      ]);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = 'Failed to load admin data: ${e.toString()}';
      notifyListeners();
    }
  }

  // ── 1. PLATFORM-WIDE STATS (Firestore count() Aggregation Rule #3) ────────
  Future<void> refreshPlatformStats() async {
    final now = DateTime.now();

    // 1. Total Non-Draft Businesses (active, grace_period, deleted)
    final totalQuery = _db
        .collection('businesses')
        .where('subscription_status', whereIn: ['active', 'grace_period', 'deleted']);
    final totalAggregate = await totalQuery.count().get();
    _totalBusinessesCount = totalAggregate.count ?? 0;

    // 2. Active Businesses
    final activeQuery = _db
        .collection('businesses')
        .where('subscription_status', isEqualTo: 'active');
    final activeAggregate = await activeQuery.count().get();
    _activeBusinessesCount = activeAggregate.count ?? 0;

    // 3. Grace Period Businesses
    final graceQuery = _db
        .collection('businesses')
        .where('subscription_status', isEqualTo: 'grace_period');
    final graceAggregate = await graceQuery.count().get();
    _graceBusinessesCount = graceAggregate.count ?? 0;

    // 4. Pending Drafts (Excluded from total business count)
    final pendingQuery = _db
        .collection('businesses')
        .where('subscription_status', isEqualTo: 'pending_payment');
    final pendingAggregate = await pendingQuery.count().get();
    _pendingDraftsCount = pendingAggregate.count ?? 0;

    // 5. Employees Count
    final empAggregate = await _db.collection('employees').count().get();
    _totalEmployeesCount = empAggregate.count ?? 0;

    // 6. Renewals Breakdown (30, 15, 7, 1 day windows)
    final d30 = Timestamp.fromDate(now.add(const Duration(days: 30)));
    final d15 = Timestamp.fromDate(now.add(const Duration(days: 15)));
    final d7 = Timestamp.fromDate(now.add(const Duration(days: 7)));
    final d1 = Timestamp.fromDate(now.add(const Duration(days: 1)));
    final tNow = Timestamp.fromDate(now);

    final r30 = await _db.collection('businesses')
        .where('subscription_status', isEqualTo: 'active')
        .where('renewal_date', isGreaterThanOrEqualTo: tNow)
        .where('renewal_date', isLessThanOrEqualTo: d30)
        .count().get();
    _renewalsDue30 = r30.count ?? 0;

    final r15 = await _db.collection('businesses')
        .where('subscription_status', isEqualTo: 'active')
        .where('renewal_date', isGreaterThanOrEqualTo: tNow)
        .where('renewal_date', isLessThanOrEqualTo: d15)
        .count().get();
    _renewalsDue15 = r15.count ?? 0;

    final r7 = await _db.collection('businesses')
        .where('subscription_status', isEqualTo: 'active')
        .where('renewal_date', isGreaterThanOrEqualTo: tNow)
        .where('renewal_date', isLessThanOrEqualTo: d7)
        .count().get();
    _renewalsDue7 = r7.count ?? 0;

    final r1 = await _db.collection('businesses')
        .where('subscription_status', isEqualTo: 'active')
        .where('renewal_date', isGreaterThanOrEqualTo: tNow)
        .where('renewal_date', isLessThanOrEqualTo: d1)
        .count().get();
    _renewalsDue1 = r1.count ?? 0;

    // 7. Robust Branch-Level & Payment Collection Metrics
    int activeBranchesCount = 0;
    int pendingBranchesCount = 0;
    int onlineCount = 0;
    int cashCount = 0;

    try {
      _businessBranchStats.clear();
      final allBizSnap = await _db.collection('businesses').get();
      for (final doc in allBizSnap.docs) {
        final bizData = doc.data();
        final bizStatus = bizData['subscription_status'] as String? ?? 'pending_payment';
        final bizPaymentMode = bizData['payment_mode'] as String? ?? 'pending';

        final branchesSnap = await doc.reference.collection('branches').get();
        int bActive = 0;
        int bPending = 0;

        if (branchesSnap.docs.isEmpty) {
          if (bizStatus == 'active' || bizStatus == 'grace_period') {
            activeBranchesCount++;
            bActive++;
            if (bizPaymentMode == 'cash') {
              cashCount++;
            } else {
              onlineCount++;
            }
          } else if (bizStatus == 'pending_payment') {
            pendingBranchesCount++;
            bPending++;
          }
        } else {
          for (final bDoc in branchesSnap.docs) {
            final bData = bDoc.data();
            final bStatus = bData['subscription_status'] as String? ?? (bizStatus == 'active' ? 'active' : 'pending_payment');
            final bPaymentMode = bData['payment_mode'] as String? ?? bizPaymentMode;

            if (bStatus == 'active' || bStatus == 'grace_period') {
              activeBranchesCount++;
              bActive++;
              if (bPaymentMode == 'cash') {
                cashCount++;
              } else if (bPaymentMode == 'online') {
                onlineCount++;
              } else {
                if (bizPaymentMode == 'cash') {
                  cashCount++;
                } else {
                  onlineCount++;
                }
              }
            } else if (bStatus == 'pending_payment') {
              pendingBranchesCount++;
              bPending++;
            }
          }
        }
        _businessBranchStats[doc.id] = (
          active: bActive,
          pending: bPending,
          total: bActive + bPending,
        );
      }
    } catch (_) {
      // Fallback
    }

    _totalActiveBranches = activeBranchesCount;
    _totalPendingBranches = pendingBranchesCount;
    _onlinePaymentsCount = onlineCount;
    _cashPaymentsCount = cashCount;

    _onlineRevenue = _onlinePaymentsCount * 1999.0;
    _cashRevenue = _cashPaymentsCount * 1999.0;

    // Revenue Snapshot Calculation
    _revenueSnapshot = _onlineRevenue + _cashRevenue + (_graceBusinessesCount * 999.0);
    notifyListeners();
  }

  /// Admin reverts a business from active back to pending_payment.
  Future<void> revertBusinessActivation(String businessId, {String? reason}) async {
    await _firestoreService.adminRevertBusinessActivation(businessId: businessId, reason: reason);
    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  /// Admin reverts a single branch from active back to pending_payment.
  Future<void> revertBranchActivation(String businessId, String branchId, {String? reason}) async {
    await _firestoreService.adminRevertBranchActivation(businessId: businessId, branchId: branchId, reason: reason);
    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  // ── 2. EMPLOYEE MANAGEMENT ────────────────────────────────────────────────
  Future<void> fetchEmployees() async {
    final snap = await _db.collection('employees').get();
    _employees = snap.docs.map(EmployeeProfileModel.fromDoc).toList();

    // Current month boundaries for "This Month" count
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthStartTs = Timestamp.fromDate(monthStart);

    for (final emp in _employees) {
      // 1. Total Enrollments: businesses where enrolled_by == this employee
      final enrolledSnap = await _db
          .collection('businesses')
          .where('enrolled_by', isEqualTo: emp.uid)
          .get();
      _employeeTotalEnrollments[emp.uid] = enrolledSnap.docs.length;

      // 2. This Month: enrolled_by == this employee AND created_at >= monthStart
      int thisMonth = 0;
      for (final doc in enrolledSnap.docs) {
        final data = doc.data();
        final createdAt = data['created_at'] as Timestamp?;
        if (createdAt != null && createdAt.compareTo(monthStartTs) >= 0) {
          thisMonth++;
        }
      }
      _employeeThisMonthEnrollments[emp.uid] = thisMonth;

      // 3. Managed Businesses: currently_managed_by == this employee
      final managedSnap = await _db
          .collection('businesses')
          .where('currently_managed_by', isEqualTo: emp.uid)
          .get();
      _employeeBusinesses[emp.uid] = managedSnap.docs.map(BusinessModel.fromDoc).toList();
      _employeeManagedCount[emp.uid] = managedSnap.docs.length;

      // 4. Commission summary (from employee_commissions collection)
      final commSnap = await _db
          .collection('employee_commissions')
          .where('employee_id', isEqualTo: emp.uid)
          .get();

      double pending = 0.0;
      double paid = 0.0;

      for (final doc in commSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num? ?? 0).toDouble();
        final status = data['status'] as String? ?? 'pending';

        if (status == 'pending') {
          pending += amount;
        } else if (status == 'paid') {
          paid += amount;
        }
      }

      _employeeCommissionSummaries[emp.uid] = {
        'pending': pending,
        'paid': paid,
      };
      // Populate global cache
      FirestoreService.employeeNameCache[emp.uid] = emp.name;
    }
    notifyListeners();
  }

  /// Resolves an employee UID to display name (e.g. "Rahul Sharma" or "Admin").
  String resolveEmployeeName(String? uid) {
    if (uid == null || uid.isEmpty || uid == 'admin') return 'Admin';
    for (final emp in _employees) {
      if (emp.uid == uid) return emp.name;
    }
    if (FirestoreService.employeeNameCache.containsKey(uid)) {
      return FirestoreService.employeeNameCache[uid]!;
    }
    return uid.length > 8 ? 'Emp: ${uid.substring(0, 8)}…' : uid;
  }

  /// Create new employee Auth account & Firestore doc, and trigger password-set email.
  Future<Map<String, dynamic>> createEmployee({
    required String email,
    required String displayName,
    required String phone,
    String? password,
    String? address,
  }) async {
    Map<String, dynamic> resultData = {};
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await fn.httpsCallable('createEmployeeAccount').call({
        'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        'displayName': displayName,
        'phone': phone,
        'address': address ?? '',
      });
      resultData = Map<String, dynamic>.from(result.data as Map? ?? {});
    } catch (_) {
      // Direct Firestore fallback for testing environments
      final newRef = _db.collection('employees').doc();
      await newRef.set({
        'name': displayName,
        'email': email,
        'phone': phone,
        'role': 'employee',
        'status': 'active',
        'total_enrollments': 0,
        'this_month_enrollments': 0,
        'documents_verified': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'profile': {
          'full_name': displayName,
          'email': email,
          'phone': phone,
          'address': address ?? '',
        },
        'payout': {},
        'documents': [],
      });
    }

    // Trigger standard Firebase Auth password reset/set email directly to employee
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } catch (_) {
      // Best-effort in emulator/testing environments
    }

    await fetchEmployees();
    return resultData;
  }

  /// Offboard / deactivate an employee and reassign currently_managed_by to "admin".
  Future<void> deactivateEmployee(String employeeUid) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable('offboardEmployee').call({
        'employeeUid': employeeUid,
      });
    } catch (_) {
      // Direct Firestore fallback
      await _db.collection('employees').doc(employeeUid).update({
        'status': 'inactive',
        'offboarded_at': FieldValue.serverTimestamp(),
      });

      final bizSnap = await _db
          .collection('businesses')
          .where('currently_managed_by', isEqualTo: employeeUid)
          .get();

      final batch = _db.batch();
      for (final doc in bizSnap.docs) {
        batch.update(doc.reference, {'currently_managed_by': 'admin'});
      }
      await batch.commit();
    }
    await fetchEmployees();
  }

  /// Admin verifies employee document/payout status.
  Future<void> verifyEmployeeDocuments({
    required String employeeUid,
    required String status, // 'verified' | 'rejected' | 'pending'
    String? notes,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable('verifyEmployeeDocumentsAdmin').call({
        'employeeUid': employeeUid,
        'status': status,
        if (notes != null) 'notes': notes,
      });
    } catch (_) {
      await _db.collection('employees').doc(employeeUid).update({
        'documents_verified': status,
        'documents_verified_at': FieldValue.serverTimestamp(),
      });
    }
    await fetchEmployees();
  }

  Future<void> fetchTemplates() async {
    _templates = await _templateService.getTemplateHeaders();
    notifyListeners();
  }

  bool isCategoryPhrasesLoading(String templateId, String categoryName, {String version = AppConstants.defaultPoolVersion}) {
    return _loadingCategories.contains('$templateId:$categoryName:$version');
  }

  List<String>? getCachedCategoryPhrases(String templateId, String categoryName, {String version = AppConstants.defaultPoolVersion}) {
    return _categoryPhrasesCache['$templateId:$categoryName:$version'];
  }

  Future<List<String>> fetchCategoryPhrases({
    required String templateId,
    required String categoryName,
    String version = AppConstants.defaultPoolVersion,
  }) async {
    final key = '$templateId:$categoryName:$version';
    if (_categoryPhrasesCache.containsKey(key)) {
      return _categoryPhrasesCache[key]!;
    }
    _loadingCategories.add(key);
    notifyListeners();

    final phrases = await _templateService.getCategoryPhrases(
      templateId: templateId,
      categoryName: categoryName,
      version: version,
    );

    _categoryPhrasesCache[key] = phrases;
    _loadingCategories.remove(key);
    notifyListeners();
    return phrases;
  }

  Future<void> createCategoryTemplate({
    required String templateId,
    required String businessType,
    required String categoryName,
    required String initialPhrase,
  }) async {
    await _templateService.createTemplate(
      templateId: templateId,
      businessType: businessType,
      categoryName: categoryName,
      initialPhrase: initialPhrase,
    );
    _categoryPhrasesCache.clear();
    await fetchTemplates();
  }

  Future<void> addPhraseVariant({
    required String templateId,
    required String categoryName,
    String poolVersion = AppConstants.defaultPoolVersion,
    String language = 'en',
    required String phrase,
  }) async {
    await _templateService.addPhraseVariant(
      templateId: templateId,
      categoryName: categoryName,
      poolVersion: poolVersion,
      language: language,
      phrase: phrase,
    );
    final key = '$templateId:$categoryName:$poolVersion';
    _categoryPhrasesCache.remove(key);
    await fetchCategoryPhrases(
      templateId: templateId,
      categoryName: categoryName,
      version: poolVersion,
    );
  }

  Future<void> retirePhraseVariant({
    required String templateId,
    required String categoryName,
    String poolVersion = AppConstants.defaultPoolVersion,
    String language = 'en',
    required int index,
  }) async {
    await _templateService.retirePhraseVariant(
      templateId: templateId,
      categoryName: categoryName,
      poolVersion: poolVersion,
      language: language,
      index: index,
    );
    final key = '$templateId:$categoryName:$poolVersion';
    _categoryPhrasesCache.remove(key);
    await fetchCategoryPhrases(
      templateId: templateId,
      categoryName: categoryName,
      version: poolVersion,
    );
  }

  Future<void> assignTemplateToBusiness({
    required String businessId,
    required String templateId,
  }) async {
    await _db.collection('businesses').doc(businessId).update({
      'default_category_template_id': templateId,
    });
    await fetchAllBusinesses();
  }

  Future<void> assignOverrideToBranch({
    required String businessId,
    required String branchId,
    required String overrideTemplateId,
  }) async {
    await _db
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(branchId)
        .update({
      'category_override_id': overrideTemplateId,
    });
  }

  // ── 4. SUBSCRIPTION / RENEWAL OVERRIDES & BUSINESS EDITING ─────────────────
  List<Map<String, dynamic>> _allBusinessesRaw = [];
  List<Map<String, dynamic>> get allBusinessesRaw => _allBusinessesRaw;

  Future<void> fetchAllBusinesses() async {
    final snap = await _db
        .collection('businesses')
        .orderBy('created_at', descending: true)
        .limit(100)
        .get();
    _allBusinesses = snap.docs.map(BusinessModel.fromDoc).toList();
    _allBusinessesRaw = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

    _businessBranches.clear();
    _businessBranchStats.clear();

    for (final doc in snap.docs) {
      final branchesSnap = await doc.reference.collection('branches').get();
      final branches = branchesSnap.docs
          .map((bDoc) => BranchModel.fromDoc(bDoc, businessId: doc.id))
          .toList();
      _businessBranches[doc.id] = branches;

      int bActive = 0;
      int bPending = 0;
      for (final b in branches) {
        if (b.isActive) {
          bActive++;
        } else if (b.isPendingPayment) {
          bPending++;
        }
      }
      if (branches.isEmpty) {
        final bizStatus = doc.data()['subscription_status'] as String? ?? 'pending_payment';
        if (bizStatus == 'active' || bizStatus == 'grace_period') {
          bActive = 1;
        } else {
          bPending = 1;
        }
      }
      _businessBranchStats[doc.id] = (
        active: bActive,
        pending: bPending,
        total: bActive + bPending,
      );
    }
    notifyListeners();
  }

  Future<void> updateBusinessDetailsAdmin({
    required String businessId,
    required String brandName,
    required String categoryType,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String subscriptionStatus,
  }) async {
    if (subscriptionStatus == 'pending_payment') {
      try {
        await _firestoreService.adminRevertBusinessActivation(
          businessId: businessId,
          reason: 'Status changed to Pending Payment in Admin Dashboard',
        );
      } catch (_) {}
    }
    await _db.collection('businesses').doc(businessId).update({
      'brand_name': brandName,
      'category_type': categoryType,
      'owner_name': ownerName,
      'owner_email': ownerEmail,
      'owner_phone': ownerPhone,
      'subscription_status': subscriptionStatus,
    });
    await fetchAllBusinesses();
    await refreshPlatformStats();
  }

  /// Manually override subscription status, renewal date, or grace period.
  Future<void> overrideSubscriptionStatus({
    required String businessId,
    required String newStatus,
    DateTime? newRenewalDate,
    DateTime? newGracePeriodEnds,
    required String adminUid,
    String? reason,
    String? paymentMode,
  }) async {
    final updateData = <String, dynamic>{
      'subscription_status': newStatus,
    };
    if (paymentMode != null) {
      updateData['payment_mode'] = paymentMode;
    }
    if (newRenewalDate != null) {
      updateData['renewal_date'] = Timestamp.fromDate(newRenewalDate);
    }
    if (newGracePeriodEnds != null) {
      updateData['grace_period_ends'] = Timestamp.fromDate(newGracePeriodEnds);
    } else if (newStatus == 'active') {
      updateData['grace_period_ends'] = null;
    }

    await _db.collection('businesses').doc(businessId).update(updateData);

    // Also update all branch subcollection documents
    final branchesSnap = await _db.collection('businesses').doc(businessId).collection('branches').get();
    for (final bDoc in branchesSnap.docs) {
      final bUpdate = <String, dynamic>{
        'subscription_status': newStatus,
      };
      if (paymentMode != null) {
        bUpdate['payment_mode'] = paymentMode;
      }
      await bDoc.reference.update(bUpdate);
    }

    // Audit log
    await _db.collection('subscription_override_logs').add({
      'business_id': businessId,
      'new_status': newStatus,
      'payment_mode': paymentMode,
      'renewal_date': newRenewalDate != null ? Timestamp.fromDate(newRenewalDate) : null,
      'grace_period_ends': newGracePeriodEnds != null ? Timestamp.fromDate(newGracePeriodEnds) : null,
      'overridden_by': adminUid,
      'reason': reason ?? 'Admin manual override',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  /// Delete a pending_payment draft business (admin). Removes in-memory immediately.
  Future<void> deleteDraftBusiness(String businessId) async {
    await _firestoreService.deleteDraftBusiness(businessId);
    _allBusinesses.removeWhere((b) => b.id == businessId);
    notifyListeners();
    await refreshPlatformStats();
  }

  /// Directly activates a pending_payment draft business via cash (admin).
  Future<void> adminCashActivate({
    required String businessId,
    required String adminUid,
  }) async {
    await _firestoreService.adminCashActivate(
      businessId: businessId,
      adminUid: adminUid,
    );
    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  /// Reverse activation of an active business → back to pending_payment.
  /// Voids commission, marks QR stale, writes audit log.
  Future<void> reverseActivation({
    required String businessId,
    required String adminUid,
    required String reason,
  }) async {
    await _firestoreService.reverseActivation(
      businessId: businessId,
      adminUid: adminUid,
      reason: reason,
    );
    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  // ── 5. STANDEE FULFILLMENT MANAGEMENT ─────────────────────────────────────
  Future<void> fetchStandeeFulfillments() async {
    _standeeLoading = true;
    _standeeError = null;
    notifyListeners();

    try {
      final bizSnap = await _db
          .collection(AppConstants.colBusinesses)
          .where('subscription_status', whereIn: ['active', 'grace_period', 'due_soon', 'deleted'])
          .get();

      final List<StandeeFulfillmentModel> items = [];

      for (final doc in bizSnap.docs) {
        final bizData = doc.data();
        final bizId = doc.id;
        final brandName = bizData['brand_name'] as String? ?? 'Untitled Business';
        final categoryType = bizData['category_type'] as String? ?? '';
        final ownerPhone = bizData['owner_phone'] as String?;
        final ownerEmail = bizData['owner_email'] as String?;

        final branchesSnap = await _db
            .collection(AppConstants.colBusinesses)
            .doc(bizId)
            .collection(AppConstants.colBranches)
            .get();

        for (final bDoc in branchesSnap.docs) {
          items.add(StandeeFulfillmentModel.fromDoc(
            businessId: bizId,
            businessName: brandName,
            categoryType: categoryType,
            ownerPhone: ownerPhone,
            ownerEmail: ownerEmail,
            branchDoc: bDoc,
          ));
        }
      }

      items.sort((a, b) {
        if (a.standeeStatusUpdatedAt == null && b.standeeStatusUpdatedAt == null) {
          return a.businessName.compareTo(b.businessName);
        }
        if (a.standeeStatusUpdatedAt == null) return 1;
        if (b.standeeStatusUpdatedAt == null) return -1;
        return b.standeeStatusUpdatedAt!.compareTo(a.standeeStatusUpdatedAt!);
      });

      _standeeItems = items;
      _standeeLoading = false;
      notifyListeners();
    } catch (e) {
      _standeeLoading = false;
      _standeeError = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateStandeeStatusInline({
    required String businessId,
    required String branchId,
    required String newStatus,
  }) async {
    final now = DateTime.now();
    for (final item in _standeeItems) {
      if (item.businessId == businessId && item.branchId == branchId) {
        item.standeeStatus = newStatus;
        item.standeeStatusUpdatedAt = now;
        break;
      }
    }
    notifyListeners();

    await _firestoreService.updateStandeeStatus(businessId, branchId, newStatus);
  }

  // ── 5A. PENDING CASH PAYMENTS (Build A — view on businesses) ───────────────

  /// Stream of businesses awaiting cash confirmation.
  Stream<List<BusinessModel>> watchPendingCashBusinesses() {
    return _firestoreService.watchPendingCashBusinesses();
  }

  /// Admin confirms cash receipt → business activates.
  Future<void> confirmCashAndActivate({
    required String businessId,
    required String adminUid,
    String? notes,
  }) async {
    await _firestoreService.confirmCashAndActivate(
      businessId: businessId,
      adminUid: adminUid,
      notes: notes,
    );
    await refreshPlatformStats();
  }

  // ── 5B. EMPLOYEE COMMISSION LEDGER (Build B — separate collection) ─────────

  /// Stream of employee commissions with optional filters.
  Stream<List<EmployeeCommissionModel>> watchEmployeeCommissions(
    String employeeId, {
    String? statusFilter,
    String? monthFilter,
  }) {
    return _firestoreService.watchEmployeeCommissions(
      employeeId,
      statusFilter: statusFilter,
      monthFilter: monthFilter,
    );
  }

  /// Stream of all pending commissions across all employees.
  Stream<List<EmployeeCommissionModel>> watchAllPendingCommissions({
    String? monthFilter,
  }) {
    return _firestoreService.watchAllPendingCommissions(
      monthFilter: monthFilter,
    );
  }

  /// Bulk-mark all pending commissions for an employee+month as paid.
  Future<Map<String, dynamic>> markCommissionsPaidBulk({
    required String employeeId,
    required String month,
    required String payoutReference,
    required String adminUid,
  }) async {
    return _firestoreService.markCommissionsPaidBulk(
      employeeId: employeeId,
      month: month,
      payoutReference: payoutReference,
      adminUid: adminUid,
    );
  }
}
