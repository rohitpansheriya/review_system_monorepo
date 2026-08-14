// lib/providers/owner_dashboard_provider.dart
//
// State provider for the Business Owner Dashboard.
// Handles business & branch reads, pre-aggregated stats rollup, category toggling,
// star-routing updates, and renewal payment status checks.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/business_model.dart';
import '../models/branch_model.dart';
import '../services/firestore_service.dart';

class OwnerDashboardProvider extends ChangeNotifier {
  final FirebaseFirestore _db;

  BusinessModel? _business;
  List<BranchModel> _branches = [];
  Map<String, dynamic>? _assignedTemplate;
  List<Map<String, dynamic>> _renewalNotifications = [];

  String _selectedBranchId = 'all'; // 'all' or branchId
  bool _loading = false;
  String? _error;

  BusinessModel? get business => _business;
  List<BranchModel> get branches => _branches;
  Map<String, dynamic>? get assignedTemplate => _assignedTemplate;
  List<Map<String, dynamic>> get renewalNotifications => _renewalNotifications;

  String get selectedBranchId => _selectedBranchId;
  bool get loading => _loading;
  String? get error => _error;

  bool get isSingleBranch => _branches.length <= 1;
  bool get isActive => _business?.subscriptionStatus == 'active';
  bool get isGracePeriod => _business?.subscriptionStatus == 'grace_period';
  bool get isDeleted => _business?.subscriptionStatus == 'deleted';
  bool get isPendingPayment => _business?.subscriptionStatus == 'pending_payment';

  OwnerDashboardProvider({
    FirestoreService? firestoreService,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  void setSelectedBranch(String branchId) {
    _selectedBranchId = branchId;
    notifyListeners();
  }

  /// Initial load for authenticated owner dashboard.
  Future<void> loadOwnerData(String ownerUid) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Fetch business where owner_auth_uid == ownerUid
      final bizSnap = await _db
          .collection('businesses')
          .where('owner_auth_uid', isEqualTo: ownerUid)
          .limit(1)
          .get();

      if (bizSnap.docs.isEmpty) {
        _business = null;
        _branches = [];
        _loading = false;
        _error = 'No business associated with this owner account.';
        notifyListeners();
        return;
      }

      _business = BusinessModel.fromDoc(bizSnap.docs.first);

      // 2. Fetch all branches under businesses/{businessId}/branches
      final branchesSnap = await _db
          .collection('businesses')
          .doc(_business!.id)
          .collection('branches')
          .get();

      _branches = branchesSnap.docs
          .map((d) => BranchModel.fromDoc(d, businessId: _business!.id))
          .toList();

      if (_branches.isNotEmpty && _selectedBranchId == 'all' && isSingleBranch) {
        _selectedBranchId = _branches.first.id;
      }

      // 3. Load assigned category template
      final tplId = _business!.defaultCategoryTemplateId ?? 'ice_cream_v1';
      final tplSnap = await _db.collection('category_templates').doc(tplId).get();
      if (tplSnap.exists) {
        _assignedTemplate = tplSnap.data();
      }

      // 4. Fetch renewal reminder notifications for dashboard banner (Doc 08)
      try {
        final notifSnap = await _db
            .collection('notifications')
            .where('recipient', isEqualTo: ownerUid)
            .where('read', isEqualTo: false)
            .limit(5)
            .get();
        _renewalNotifications = notifSnap.docs.map((d) => d.data()).toList();
      } catch (_) {
        _renewalNotifications = [];
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = 'Failed to load owner data: ${e.toString()}';
      notifyListeners();
    }
  }

  /// SCALABILITY RULE #1 / #2:
  /// Aggregates pre-aggregated stats_summary across branches.
  /// DOES NOT QUERY RAW scan_logs.
  Map<String, dynamic> getAggregatedStats() {
    if (_branches.isEmpty) {
      return {
        'total_scans': 0,
        'google_reviews_opened': 0,
        'star_distribution': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
      };
    }

    if (_selectedBranchId != 'all') {
      final target = _branches.firstWhere(
        (b) => b.id == _selectedBranchId,
        orElse: () => _branches.first,
      );
      return _extractBranchStats(target);
    }

    // Rollup across all branches
    int totalScans = 0;
    int googleOpened = 0;
    final Map<String, int> stars = {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0};

    for (final branch in _branches) {
      final stats = _extractBranchStats(branch);
      totalScans += (stats['total_scans'] as num? ?? 0).toInt();
      googleOpened += (stats['google_reviews_opened'] as num? ?? 0).toInt();
      final starMap = stats['star_distribution'] as Map<String, dynamic>? ?? {};
      starMap.forEach((k, v) {
        stars[k] = (stars[k] ?? 0) + (v as num? ?? 0).toInt();
      });
    }

    return {
      'total_scans': totalScans,
      'google_reviews_opened': googleOpened,
      'star_distribution': stars,
    };
  }

  Map<String, dynamic> _extractBranchStats(BranchModel branch) {
    return {
      'total_scans': branch.totalScans,
      'google_reviews_opened': branch.googleReviewsOpened,
      'star_distribution': branch.starDistribution,
    };
  }

  /// Screen 2: Toggle category active status on business level.
  /// Gated: Read-only in grace_period / expired.
  Future<void> toggleCategory(String categoryName, bool active) async {
    if (_business == null) return;
    if (isGracePeriod || isDeleted) {
      throw Exception('Category editing is read-only during grace period. Renew subscription to edit.');
    }

    final currentActive = Map<String, bool>.from(_business!.activeCategories);
    currentActive[categoryName] = active;

    await _db
        .collection('businesses')
        .doc(_business!.id)
        .update({'active_categories': currentActive});

    _business = _business!.copyWith(activeCategories: currentActive);
    notifyListeners();
  }

  /// Screen 3: Update star routing config for a branch.
  Future<void> updateStarRouting(
    String branchId,
    Map<String, String> newConfig,
  ) async {
    if (_business == null) return;

    await _db
        .collection('businesses')
        .doc(_business!.id)
        .collection('branches')
        .doc(branchId)
        .update({'star_routing_config': newConfig});

    // Update in-memory branch list immediately
    final idx = _branches.indexWhere((b) => b.id == branchId);
    if (idx != -1) {
      _branches[idx] = _branches[idx].copyWith(starRoutingConfig: newConfig);
      notifyListeners();
    }
  }

  /// Refresh owner dashboard state.
  Future<void> refresh(String ownerUid) async {
    await loadOwnerData(ownerUid);
  }
}
