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
  double _newEnrollmentsRevenue = 0.0;
  double _renewalsRevenue = 0.0;
  int _newEnrollmentsCount = 0;
  int _renewalsCount = 0;
  int _totalActiveBranches = 0;
  int _totalPendingBranches = 0;
  int _onlinePaymentsCount = 0;
  int _cashPaymentsCount = 0;

  // ── Month Filter State for Revenue Analytics ──────────────────────────────
  String? _selectedRevenueMonth; // null = All Time, or 'YYYY-MM'
  List<String> _availableRevenueMonths = [];
  final List<_BusinessRevenueEntry> _revenueEntries = [];

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
  final Map<String, ({int active, int grace, int pending, int deleted, int total})> _businessBranchStats = {};

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
  double get newEnrollmentsRevenue => _newEnrollmentsRevenue;
  double get renewalsRevenue => _renewalsRevenue;
  int get newEnrollmentsCount => _newEnrollmentsCount;
  int get renewalsCount => _renewalsCount;
  int get totalActiveBranches => _totalActiveBranches;
  int get totalPendingBranches => _totalPendingBranches;
  int get onlinePaymentsCount => _onlinePaymentsCount;
  int get cashPaymentsCount => _cashPaymentsCount;

  String? get selectedRevenueMonth => _selectedRevenueMonth;
  List<String> get availableRevenueMonths => _availableRevenueMonths;

  void setSelectedRevenueMonth(String? month) {
    _selectedRevenueMonth = month;
    _recalculateRevenue();
    notifyListeners();
  }

  List<EmployeeProfileModel> get employees => _employees;
  Map<String, List<BusinessModel>> get employeeBusinesses => _employeeBusinesses;
  Map<String, Map<String, double>> get employeeCommissionSummaries => _employeeCommissionSummaries;
  Map<String, int> get employeeTotalEnrollments => _employeeTotalEnrollments;
  Map<String, int> get employeeThisMonthEnrollments => _employeeThisMonthEnrollments;
  Map<String, int> get employeeManagedCount => _employeeManagedCount;

  List<Map<String, dynamic>> get templates => _templates;
  List<BusinessModel> get allBusinesses => _allBusinesses;
  Map<String, List<BranchModel>> get businessBranches => _businessBranches;
  Map<String, ({int active, int grace, int pending, int deleted, int total})> get businessBranchStats => _businessBranchStats;
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
  Future<void> loadAdminData({bool forceReload = false}) async {
    final isFirstLoad = _allBusinesses.isEmpty && _employees.isEmpty;
    if (isFirstLoad || forceReload) {
      _loading = true;
      _error = null;
      notifyListeners();
    }

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

    final d30 = Timestamp.fromDate(now.add(const Duration(days: 30)));
    final d15 = Timestamp.fromDate(now.add(const Duration(days: 15)));
    final d7 = Timestamp.fromDate(now.add(const Duration(days: 7)));
    final d1 = Timestamp.fromDate(now.add(const Duration(days: 1)));
    final tNow = Timestamp.fromDate(now);

    // Run all count aggregations concurrently in parallel
    final results = await Future.wait([
      _db.collection('businesses').where('subscription_status', whereIn: ['active', 'grace_period', 'deleted']).count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'active').count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'grace_period').count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'pending_payment').count().get(),
      _db.collection('employees').count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'active').where('renewal_date', isGreaterThanOrEqualTo: tNow).where('renewal_date', isLessThanOrEqualTo: d30).count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'active').where('renewal_date', isGreaterThanOrEqualTo: tNow).where('renewal_date', isLessThanOrEqualTo: d15).count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'active').where('renewal_date', isGreaterThanOrEqualTo: tNow).where('renewal_date', isLessThanOrEqualTo: d7).count().get(),
      _db.collection('businesses').where('subscription_status', isEqualTo: 'active').where('renewal_date', isGreaterThanOrEqualTo: tNow).where('renewal_date', isLessThanOrEqualTo: d1).count().get(),
    ]);

    _totalBusinessesCount = results[0].count ?? 0;
    _activeBusinessesCount = results[1].count ?? 0;
    _graceBusinessesCount = results[2].count ?? 0;
    _pendingDraftsCount = results[3].count ?? 0;
    _totalEmployeesCount = results[4].count ?? 0;

    _renewalsDue30 = results[5].count ?? 0;
    _renewalsDue15 = results[6].count ?? 0;
    _renewalsDue7 = results[7].count ?? 0;
    _renewalsDue1 = results[8].count ?? 0;

    // Revenue Snapshot Calculation
    _revenueSnapshot = _newEnrollmentsRevenue + _renewalsRevenue;
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

    // Parallelize all per-employee queries concurrently
    final empTasks = _employees.map((emp) async {
      FirestoreService.employeeNameCache[emp.uid] = emp.name;

      final results = await Future.wait([
        _db.collection('businesses').where('enrolled_by', isEqualTo: emp.uid).get(),
        _db.collection('employee_commissions').where('employee_id', isEqualTo: emp.uid).get(),
      ]);

      final enrolledSnap = results[0];
      final commSnap = results[1];

      _employeeTotalEnrollments[emp.uid] = enrolledSnap.docs.length;

      int thisMonth = 0;
      for (final doc in enrolledSnap.docs) {
        final data = doc.data();
        final createdAt = data['created_at'] as Timestamp?;
        if (createdAt != null && createdAt.compareTo(monthStartTs) >= 0) {
          thisMonth++;
        }
      }
      _employeeThisMonthEnrollments[emp.uid] = thisMonth;

      _employeeBusinesses[emp.uid] = enrolledSnap.docs.map(BusinessModel.fromDoc).toList();
      _employeeManagedCount[emp.uid] = enrolledSnap.docs.length;

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
    });

    await Future.wait(empTasks);
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

  /// Deactivate an employee. Disables login and marks profile inactive.
  /// Enrolled businesses remain with enrolled_by preserved and handled directly by Admin.
  Future<void> deactivateEmployee(String employeeUid) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable('offboardEmployee').call({
        'employeeUid': employeeUid,
      });
    } catch (_) {
      // Direct Firestore fallback
      await _db.collection('employees').doc(employeeUid).update({
        'active': false,
        'status': 'inactive',
        'offboarded_at': FieldValue.serverTimestamp(),
      });
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
    required List<String> phrases,
  }) async {
    await _templateService.createTemplate(
      templateId: templateId,
      businessType: businessType,
      categoryName: categoryName,
      phrases: phrases,
    );
    _categoryPhrasesCache.clear();
    await fetchTemplates();
  }

  Future<void> addCategory({
    required String templateId,
    required String categoryName,
    required List<String> phrases,
  }) async {
    await _templateService.addCategory(
      templateId: templateId,
      categoryName: categoryName,
      phrases: phrases,
    );
    _categoryPhrasesCache.clear();
    await fetchTemplates();
    await fetchCategoryPhrases(
      templateId: templateId,
      categoryName: categoryName,
      version: AppConstants.defaultPoolVersion,
    );
  }

  Future<void> deleteCategory({
    required String templateId,
    required String categoryName,
  }) async {
    await _templateService.deleteCategory(
      templateId: templateId,
      categoryName: categoryName,
    );
    _categoryPhrasesCache.clear();
    await fetchTemplates();
  }

  Future<void> addPhrasesBulk({
    required String templateId,
    required String categoryName,
    required List<String> phrases,
    String poolVersion = AppConstants.defaultPoolVersion,
    String language = 'en',
  }) async {
    await _templateService.addPhrasesBulk(
      templateId: templateId,
      categoryName: categoryName,
      phrases: phrases,
      poolVersion: poolVersion,
      language: language,
    );
    final key = '$templateId:$categoryName:$poolVersion';
    _categoryPhrasesCache.remove(key);
    await fetchCategoryPhrases(
      templateId: templateId,
      categoryName: categoryName,
      version: poolVersion,
    );
  }

  Future<void> addPhraseVariant({
    required String templateId,
    required String categoryName,
    String poolVersion = AppConstants.defaultPoolVersion,
    String language = 'en',
    required String phrase,
  }) async {
    return addPhrasesBulk(
      templateId: templateId,
      categoryName: categoryName,
      phrases: [phrase],
      poolVersion: poolVersion,
      language: language,
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

  /// Instant local removal of a deleted business from memory & lists
  void removeBusinessLocally(String businessId) {
    _allBusinesses.removeWhere((b) => b.id == businessId);
    _allBusinessesRaw.removeWhere((m) => m['id'] == businessId);
    _businessBranches.remove(businessId);
    _businessBranchStats.remove(businessId);
    for (final empId in _employeeBusinesses.keys) {
      _employeeBusinesses[empId]?.removeWhere((b) => b.id == businessId);
    }
    _totalBusinessesCount = (_totalBusinessesCount - 1).clamp(0, 999999);
    notifyListeners();
  }

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

    int totalActiveBranches = 0;
    int totalPendingBranches = 0;

    // Concurrently fetch branches and compute metrics for all businesses in parallel
    final branchTasks = snap.docs.map((doc) async {
      final bizData = doc.data();
      final isTest = bizData['is_test_account'] as bool? ?? false;
      final bizStatus = bizData['subscription_status'] as String? ?? 'pending_payment';
      final bizPaymentMode = bizData['payment_mode'] as String? ?? 'pending';
      final isBizDraft = bizStatus == 'pending_payment' || bizStatus == AppConstants.statusPendingPayment;

      final branchesSnap = await doc.reference.collection('branches').get();
      final branches = branchesSnap.docs
          .map((bDoc) => BranchModel.fromDoc(bDoc, businessId: doc.id))
          .toList();

      int bActive = 0;
      int bGrace = 0;
      int bPending = 0;
      int bDeleted = 0;

      for (final b in branches) {
        // If parent business is in pending_payment, ALL its branches are strictly pending
        if (isBizDraft) {
          bPending++;
          continue;
        }

        if (b.subscriptionStatus == AppConstants.statusActive) {
          bActive++;
        } else if (b.subscriptionStatus == AppConstants.statusGracePeriod) {
          bGrace++;
        } else if (b.subscriptionStatus == AppConstants.statusPendingPayment) {
          bPending++;
        } else if (b.subscriptionStatus == AppConstants.statusDeleted) {
          bDeleted++;
        } else {
          bPending++;
        }
      }

      if (branches.isEmpty) {
        if (isBizDraft) {
          bPending = 1;
        } else if (bizStatus == 'active') {
          bActive = 1;
        } else if (bizStatus == 'grace_period') {
          bGrace = 1;
        } else if (bizStatus == 'deleted') {
          bDeleted = 1;
        } else {
          bPending = 1;
        }
      }

      // Compute revenue for this business if active/grace and not a test account
      _BusinessRevenueEntry? revEntry;

      if (!isBizDraft && !isTest && (bizStatus == 'active' || bizStatus == 'grace_period')) {
        final bizSetupFeePaid = (bizData['setup_fee_paid'] as num?)?.toDouble() ??
            (bizData['amount_paid'] as num?)?.toDouble();
        final bizRenewalAmountPaid = (bizData['renewal_amount_paid'] as num?)?.toDouble();

        // 1. Setup Revenue calculation (Actual paid amount > Branch sum > Fallback)
        double setupAmount = 0.0;
        if (bizSetupFeePaid != null && bizSetupFeePaid > 0) {
          setupAmount = bizSetupFeePaid;
        } else {
          double branchSetupSum = 0.0;
          bool hasExplicitBranchFees = false;
          for (final b in branches) {
            if (b.subscriptionStatus == AppConstants.statusActive ||
                b.subscriptionStatus == AppConstants.statusGracePeriod) {
              if (b.setupFeePaid != null && b.setupFeePaid! > 0) {
                branchSetupSum += b.setupFeePaid!;
                hasExplicitBranchFees = true;
              }
            }
          }
          if (hasExplicitBranchFees && branchSetupSum > 0) {
            setupAmount = branchSetupSum;
          } else {
            setupAmount = (bActive > 0 ? bActive : 1) * 1999.0;
          }
        }

        // 2. Renewals Revenue
        double renewalsAmount = 0.0;
        int renewalsCount = 0;
        if (bizRenewalAmountPaid != null && bizRenewalAmountPaid > 0) {
          renewalsAmount = bizRenewalAmountPaid;
          renewalsCount = (bizRenewalAmountPaid / 999.0).round();
        } else {
          final created = (bizData['created_at'] as Timestamp?)?.toDate();
          final renewal = (bizData['renewal_date'] as Timestamp?)?.toDate();
          if (created != null && renewal != null) {
            final daysDiff = renewal.difference(created).inDays;
            if (daysDiff > 370) {
              final extraYears = ((daysDiff - 365) / 365).ceil();
              renewalsCount = extraYears;
              renewalsAmount = extraYears * (999.0 * (bActive > 0 ? bActive : 1));
            }
          }
        }

        // Derive payment/enrollment month
        final dt = (bizData['cash_payment_confirmed_at'] as Timestamp?)?.toDate() ??
            (bizData['activated_at'] as Timestamp?)?.toDate() ??
            (bizData['created_at'] as Timestamp?)?.toDate() ??
            DateTime.now();
        final y = dt.year.toString().padLeft(4, '0');
        final m = dt.month.toString().padLeft(2, '0');
        final bizMonth = '$y-$m';

        revEntry = _BusinessRevenueEntry(
          businessId: doc.id,
          month: bizMonth,
          paymentMode: bizPaymentMode,
          setupAmount: setupAmount,
          renewalsAmount: renewalsAmount,
          renewalsCount: renewalsCount,
          activeBranches: bActive,
        );
      }

      return (
        doc.id,
        branches,
        (
          active: bActive,
          grace: bGrace,
          pending: bPending,
          deleted: bDeleted,
          total: bActive + bGrace + bPending + bDeleted,
        ),
        bActive,
        bPending,
        revEntry,
      );
    });

    final results = await Future.wait(branchTasks);
    _revenueEntries.clear();
    final monthSet = <String>{};

    for (final r in results) {
      _businessBranches[r.$1] = r.$2;
      _businessBranchStats[r.$1] = r.$3;
      totalActiveBranches += r.$4;
      totalPendingBranches += r.$5;
      if (r.$6 != null) {
        _revenueEntries.add(r.$6!);
        monthSet.add(r.$6!.month);
      }
    }

    final sortedMonths = monthSet.toList()..sort((a, b) => b.compareTo(a));
    _availableRevenueMonths = sortedMonths;
    _totalActiveBranches = totalActiveBranches;
    _totalPendingBranches = totalPendingBranches;

    _recalculateRevenue();
    notifyListeners();
  }

  void _recalculateRevenue() {
    double totalOnline = 0.0;
    double totalCash = 0.0;
    int onlineCount = 0;
    int cashCount = 0;
    double totalRenewals = 0.0;
    int renewalsCount = 0;

    for (final entry in _revenueEntries) {
      if (_selectedRevenueMonth != null && entry.month != _selectedRevenueMonth) {
        continue;
      }
      if (entry.paymentMode == 'cash') {
        totalCash += entry.setupAmount;
        cashCount += 1;
      } else {
        totalOnline += entry.setupAmount;
        onlineCount += 1;
      }
      totalRenewals += entry.renewalsAmount;
      renewalsCount += entry.renewalsCount;
    }

    _onlinePaymentsCount = onlineCount;
    _cashPaymentsCount = cashCount;
    _onlineRevenue = totalOnline;
    _cashRevenue = totalCash;
    _newEnrollmentsCount = onlineCount + cashCount;
    _newEnrollmentsRevenue = _onlineRevenue + _cashRevenue;
    _renewalsCount = renewalsCount;
    _renewalsRevenue = totalRenewals;
    _revenueSnapshot = _newEnrollmentsRevenue + _renewalsRevenue;
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
    final cleanEmail = ownerEmail.trim().toLowerCase();
    final isDup = await _firestoreService.ownerEmailExistsForEdit(cleanEmail, businessId);
    if (isDup) {
      throw Exception('Owner email "$cleanEmail" is already registered to another business.');
    }

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
      'owner_email': cleanEmail,
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

class _BusinessRevenueEntry {
  final String businessId;
  final String month; // 'YYYY-MM'
  final String paymentMode;
  final double setupAmount;
  final double renewalsAmount;
  final int renewalsCount;
  final int activeBranches;

  const _BusinessRevenueEntry({
    required this.businessId,
    required this.month,
    required this.paymentMode,
    required this.setupAmount,
    required this.renewalsAmount,
    required this.renewalsCount,
    required this.activeBranches,
  });
}

