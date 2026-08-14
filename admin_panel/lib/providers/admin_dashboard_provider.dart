// lib/providers/admin_dashboard_provider.dart
//
// Admin Dashboard State Provider (Doc 04 Admin Panel).
// Manages platform-wide count() stats (Scalability Rule #3), employee management,
// template CRUD, subscription overrides, and commission verification queue.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/business_model.dart';
import '../models/commission_record_model.dart';
import '../models/employee_profile_model.dart';
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

  // ── Employee Management State ──────────────────────────────────────────────
  List<EmployeeProfileModel> _employees = [];
  Map<String, List<BusinessModel>> _employeeBusinesses = {};
  Map<String, Map<String, double>> _employeeCommissionSummaries = {};

  // ── Category Template Library State ────────────────────────────────────────
  List<Map<String, dynamic>> _templates = [];

  // ── All Businesses List (for Subscription Overrides & Management) ────────
  List<BusinessModel> _allBusinesses = [];

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

  List<EmployeeProfileModel> get employees => _employees;
  Map<String, List<BusinessModel>> get employeeBusinesses => _employeeBusinesses;
  Map<String, Map<String, double>> get employeeCommissionSummaries => _employeeCommissionSummaries;

  List<Map<String, dynamic>> get templates => _templates;
  List<BusinessModel> get allBusinesses => _allBusinesses;

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

    // Revenue Snapshot Calculation
    _revenueSnapshot = (_activeBusinessesCount * 1999.0) + (_graceBusinessesCount * 999.0);
    notifyListeners();
  }

  // ── 2. EMPLOYEE MANAGEMENT ────────────────────────────────────────────────
  Future<void> fetchEmployees() async {
    final snap = await _db.collection('employees').get();
    _employees = snap.docs.map(EmployeeProfileModel.fromDoc).toList();

    // Fetch businesses & commission summaries for each employee
    for (final emp in _employees) {
      // Businesses enrolled or currently managed by employee
      final bizSnap = await _db
          .collection('businesses')
          .where('currently_managed_by', isEqualTo: emp.uid)
          .get();
      _employeeBusinesses[emp.uid] = bizSnap.docs.map(BusinessModel.fromDoc).toList();

      // Commission summary for employee
      final commSnap = await _db
          .collection('commission_records')
          .where('employee_id', isEqualTo: emp.uid)
          .get();

      double pending = 0.0;
      double verified = 0.0;
      double paid = 0.0;

      for (final doc in commSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num? ?? 0).toDouble();
        final status = data['status'] as String? ?? 'pending';

        if (status == 'pending' || status == 'disputed') {
          pending += amount;
        } else if (status == 'verified') {
          verified += amount;
        } else if (status == 'paid') {
          paid += amount;
        }
      }

      _employeeCommissionSummaries[emp.uid] = {
        'pending': pending,
        'verified': verified,
        'paid': paid,
      };
    }
    notifyListeners();
  }

  /// Create new employee Auth account & Firestore doc.
  Future<void> createEmployee({
    required String email,
    required String password,
    required String displayName,
    required String phone,
    String? address,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable('createEmployeeAccount').call({
        'email': email,
        'password': password,
        'displayName': displayName,
        'phone': phone,
        'address': address ?? '',
      });
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
        'profile': {'address': address ?? ''},
        'payout': {},
        'documents': [],
      });
    }
    await fetchEmployees();
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

  // ── 3. CATEGORY TEMPLATE LIBRARY (Doc 07 CRUD UI) ─────────────────────────
  Future<void> fetchTemplates() async {
    _templates = await _firestoreService.getCategoryTemplates();
    notifyListeners();
  }

  Future<void> addPhraseVariant({
    required String templateId,
    required String categoryName,
    required String poolVersion,
    required String language,
    required String phrase,
  }) async {
    await _templateService.addPhraseVariant(
      templateId: templateId,
      categoryName: categoryName,
      poolVersion: poolVersion,
      language: language,
      phrase: phrase,
    );
    await fetchTemplates();
  }

  Future<void> retirePhraseVariant({
    required String templateId,
    required String categoryName,
    required String poolVersion,
    required String language,
    required int index,
  }) async {
    await _templateService.retirePhraseVariant(
      templateId: templateId,
      categoryName: categoryName,
      poolVersion: poolVersion,
      language: language,
      index: index,
    );
    await fetchTemplates();
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

  // ── 4. SUBSCRIPTION / RENEWAL OVERRIDES ──────────────────────────────────
  Future<void> fetchAllBusinesses() async {
    final snap = await _db
        .collection('businesses')
        .orderBy('created_at', descending: true)
        .limit(100)
        .get();
    _allBusinesses = snap.docs.map(BusinessModel.fromDoc).toList();
    notifyListeners();
  }

  /// Manually override subscription status, renewal date, or grace period.
  Future<void> overrideSubscriptionStatus({
    required String businessId,
    required String newStatus,
    DateTime? newRenewalDate,
    DateTime? newGracePeriodEnds,
    required String adminUid,
    String? reason,
  }) async {
    final updateData = <String, dynamic>{
      'subscription_status': newStatus,
    };
    if (newRenewalDate != null) {
      updateData['renewal_date'] = Timestamp.fromDate(newRenewalDate);
    }
    if (newGracePeriodEnds != null) {
      updateData['grace_period_ends'] = Timestamp.fromDate(newGracePeriodEnds);
    } else if (newStatus == 'active') {
      updateData['grace_period_ends'] = null;
    }

    await _db.collection('businesses').doc(businessId).update(updateData);

    // Audit log
    await _db.collection('subscription_override_logs').add({
      'business_id': businessId,
      'new_status': newStatus,
      'renewal_date': newRenewalDate != null ? Timestamp.fromDate(newRenewalDate) : null,
      'grace_period_ends': newGracePeriodEnds != null ? Timestamp.fromDate(newGracePeriodEnds) : null,
      'overridden_by': adminUid,
      'reason': reason ?? 'Admin manual override',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await refreshPlatformStats();
    await fetchAllBusinesses();
  }

  // ── 5. COMMISSION VERIFICATION QUEUE & PAYOUT ─────────────────────────────
  Stream<List<CommissionRecordModel>> watchCommissionQueue() {
    return _firestoreService.watchCommissionVerificationQueue();
  }

  Future<void> adminConfirmCashPayment({
    required String recordId,
    required String adminUid,
    String? notes,
  }) async {
    await _firestoreService.adminConfirmCashPayment(
      recordId: recordId,
      adminUid: adminUid,
      notes: notes,
    );
  }

  Future<void> markCommissionPaid({
    required String recordId,
    required String payoutReference,
    required String adminUid,
  }) async {
    await _firestoreService.markCommissionPaid(
      recordId: recordId,
      payoutReference: payoutReference,
      adminUid: adminUid,
    );
  }
}
