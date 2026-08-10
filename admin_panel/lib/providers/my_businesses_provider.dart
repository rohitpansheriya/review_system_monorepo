// lib/providers/my_businesses_provider.dart
//
// Manages paginated, filtered, date-windowed list of the employee's businesses.
//
// Design:
//   - Default window = last 7 days (extendable via loadOlderWindow())
//   - Limit = 20 per page, cursor-based pagination (Firestore DocumentSnapshot)
//   - Filter enum: all / pending / successful (applied at query level, not in-memory)
//   - State machine: idle → loading → loaded / error
//   - Load more: appends next page without replacing existing list

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/business_model.dart';
import '../services/firestore_service.dart';

enum PaymentFilter { all, pending, successful }

extension PaymentFilterLabel on PaymentFilter {
  String get label {
    switch (this) {
      case PaymentFilter.pending:    return 'Pending payment';
      case PaymentFilter.successful: return 'Successful payment';
      case PaymentFilter.all:        return 'All';
    }
  }

  String get queryValue {
    switch (this) {
      case PaymentFilter.pending:    return 'pending';
      case PaymentFilter.successful: return 'successful';
      case PaymentFilter.all:        return 'all';
    }
  }
}

class MyBusinessesProvider extends ChangeNotifier {
  final FirestoreService _firestore;

  // ── Filter & window state ─────────────────────────────────────────────────
  PaymentFilter _filter = PaymentFilter.all;
  DateTime _since = DateTime.now().subtract(const Duration(days: 7));

  PaymentFilter get filter => _filter;
  DateTime get since => _since;

  // ── Page state ────────────────────────────────────────────────────────────
  List<BusinessModel> _businesses = [];
  bool     _loading     = false;
  bool     _loadingMore = false;
  bool     _hasMore     = true;
  String?  _error;
  DocumentSnapshot? _lastDoc;
  String?  _currentEmployeeId;

  static const int _pageSize = 20;

  List<BusinessModel> get businesses  => _businesses;
  bool                get loading     => _loading;
  bool                get loadingMore => _loadingMore;
  bool                get hasMore     => _hasMore;
  String?             get error       => _error;

  // ── Pending activation (post-checkout webhook wait) ───────────────────────
  // Set after Razorpay checkout SUCCESS callback. The business remains
  // pending_payment until the webhook fires. Home screen shows a
  // "Finalizing payment…" banner and polls this single business doc.
  String? _pendingActivationId;
  String? get pendingActivationId => _pendingActivationId;

  void setPendingActivation(String? businessId) {
    _pendingActivationId = businessId;
    notifyListeners();
  }

  void clearPendingActivation() {
    _pendingActivationId = null;
    notifyListeners();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  MyBusinessesProvider({required FirestoreService firestoreService})
      : _firestore = firestoreService;

  /// Initial load — called by the screen in initState.
  Future<void> loadFirst(String employeeId) async {
    _currentEmployeeId = employeeId;
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Apply a new filter and reload from the first page.
  Future<void> applyFilter(PaymentFilter filter) async {
    if (_filter == filter) return;
    _filter = filter;
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Load the next page using the cursor from the last fetch.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _currentEmployeeId == null) return;
    await _fetch(isFirstPage: false);
  }

  /// Extend the date window by 30 days and reload.
  /// Lets employees reach businesses enrolled more than 7 days ago.
  Future<void> loadOlderWindow() async {
    _since = _since.subtract(const Duration(days: 30));
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Re-run the current filter + window from scratch (pull-to-refresh).
  Future<void> refresh() async {
    if (_currentEmployeeId == null) return;
    _reset();
    await _fetch(isFirstPage: true);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _reset() {
    _businesses = [];
    _lastDoc    = null;
    _hasMore    = true;
    _error      = null;
  }

  Future<void> _fetch({required bool isFirstPage}) async {
    if (_currentEmployeeId == null) return;

    if (isFirstPage) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    notifyListeners();

    try {
      // For pagination we need the actual DocumentSnapshot cursor, not just the model.
      // We fetch raw QuerySnapshot to extract the last document.
      final page = await _firestore.fetchMyBusinessesPage(
        employeeId:  _currentEmployeeId!,
        statusFilter: _filter.queryValue,
        since:       _since,
        startAfter:  isFirstPage ? null : _lastDoc,
        limit:       _pageSize,
      );

      // Derive cursor: fetch the actual doc snapshot of the last returned item
      if (page.isNotEmpty) {
        _lastDoc = await _firestore.getLastDoc(page.last.id);
      }

      if (isFirstPage) {
        _businesses = page;
      } else {
        _businesses = [..._businesses, ...page];
      }

      _hasMore = page.length >= _pageSize;
      _error   = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading     = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Removes a business from the local list after successful delete.
  void removeLocal(String businessId) {
    _businesses = _businesses.where((b) => b.id != businessId).toList();
    notifyListeners();
  }

  /// Replaces a business in the local list after a successful edit.
  void replaceLocal(BusinessModel updated) {
    _businesses = _businesses
        .map((b) => b.id == updated.id ? updated : b)
        .toList();
    notifyListeners();
  }
}
