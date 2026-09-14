// lib/providers/my_businesses_provider.dart
//
// Manages paginated, filtered, date-windowed list of the employee's businesses.
//
// Design:
//   - Default window = Current Month (1st to last day)
//   - Flexible date filters: This Month, Specific Month, Custom Date Range, All Time
//   - Limit = 20 per page, cursor-based pagination (Firestore DocumentSnapshot)
//   - Filter enum: all / pending / successful (applied at query level, not in-memory)
//   - State machine: idle → loading → loaded / error
//   - Load more: appends next page without replacing existing list

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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

  // ── Filter & Date Range state ─────────────────────────────────────────────
  PaymentFilter _filter = PaymentFilter.all;
  DateTime? _startDate;
  DateTime? _endDate;
  String _dateLabel = 'This Month';
  bool _isAllTime = false;
  String? _selectedMonthKey; // e.g. "2026-09"

  PaymentFilter get filter => _filter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  String get dateLabel => _dateLabel;
  bool get isAllTime => _isAllTime;
  String? get selectedMonthKey => _selectedMonthKey;

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
      : _firestore = firestoreService {
    _initDefaultDates();
  }

  void _initDefaultDates() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1, 0, 0, 0);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    _dateLabel = DateFormat('MMMM yyyy').format(now);
    _selectedMonthKey = DateFormat('yyyy-MM').format(now);
    _isAllTime = false;
  }

  /// Initial load — called by the screen in initState.
  Future<void> loadFirst(String employeeId) async {
    _currentEmployeeId = employeeId;
    if (_startDate == null && !_isAllTime) {
      _initDefaultDates();
    }
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Apply a new status filter (all / pending / successful) and reload.
  Future<void> applyFilter(PaymentFilter filter) async {
    if (_filter == filter) return;
    _filter = filter;
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Filter by "This Month".
  Future<void> setThisMonth() async {
    _initDefaultDates();
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Filter by a specific Month & Year.
  Future<void> setMonth(int year, int month) async {
    _startDate = DateTime(year, month, 1, 0, 0, 0);
    _endDate = DateTime(year, month + 1, 0, 23, 59, 59, 999);
    _dateLabel = DateFormat('MMMM yyyy').format(_startDate!);
    _selectedMonthKey = DateFormat('yyyy-MM').format(_startDate!);
    _isAllTime = false;
    _reset();
    await _fetch(isFirstPage: true);
  }

  int get currentYear => _startDate?.year ?? DateTime.now().year;
  int get currentMonth => _startDate?.month ?? DateTime.now().month;

  /// Move backward by 1 month.
  Future<void> previousMonth() async {
    final cur = _startDate ?? DateTime.now();
    final prev = DateTime(cur.year, cur.month - 1, 1);
    await setMonth(prev.year, prev.month);
  }

  /// Move forward by 1 month.
  Future<void> nextMonth() async {
    final cur = _startDate ?? DateTime.now();
    final next = DateTime(cur.year, cur.month + 1, 1);
    await setMonth(next.year, next.month);
  }

  /// Filter by custom Start and End Date range.
  Future<void> setDateRange(DateTime start, DateTime end) async {
    _startDate = DateTime(start.year, start.month, start.day, 0, 0, 0);
    _endDate = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    _dateLabel = '${DateFormat('d MMM yyyy').format(_startDate!)} – ${DateFormat('d MMM yyyy').format(_endDate!)}';
    _selectedMonthKey = null;
    _isAllTime = false;
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Filter to show All Time (no date constraints).
  Future<void> setAllTime() async {
    _startDate = null;
    _endDate = null;
    _dateLabel = 'All Time';
    _selectedMonthKey = 'all';
    _isAllTime = true;
    _reset();
    await _fetch(isFirstPage: true);
  }

  /// Load the next page using the cursor from the last fetch.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _currentEmployeeId == null) return;
    await _fetch(isFirstPage: false);
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
      final page = await _firestore.fetchMyBusinessesPage(
        employeeId:   _currentEmployeeId!,
        statusFilter: _filter.queryValue,
        startDate:    _startDate,
        endDate:      _endDate,
        startAfter:   isFirstPage ? null : _lastDoc,
        limit:        _pageSize,
      );

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
