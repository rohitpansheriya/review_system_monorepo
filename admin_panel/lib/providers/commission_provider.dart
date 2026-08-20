// lib/providers/commission_provider.dart
// Streams employee commissions from the new employee_commissions collection.
// Read-only for employees — no log cash payment action.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/employee_commission_model.dart';
import '../services/firestore_service.dart';

class CommissionProvider extends ChangeNotifier {
  final FirestoreService _firestore;

  List<EmployeeCommissionModel> _records = [];
  bool    _loading   = true;
  String? _error;
  StreamSubscription? _sub;

  // Filter state
  String? _statusFilter;
  String? _monthFilter;

  List<EmployeeCommissionModel> get records    => _records;
  bool                          get loading    => _loading;
  String?                       get error      => _error;
  String?                       get statusFilter => _statusFilter;
  String?                       get monthFilter  => _monthFilter;

  CommissionProvider({required FirestoreService firestoreService})
      : _firestore = firestoreService;

  String? _currentEmployeeId;

  void startListening(String employeeId) {
    _currentEmployeeId = employeeId;
    _resubscribe();
  }

  void setStatusFilter(String? status) {
    _statusFilter = status;
    _resubscribe();
  }

  void setMonthFilter(String? month) {
    _monthFilter = month;
    _resubscribe();
  }

  void _resubscribe() {
    if (_currentEmployeeId == null) return;
    _sub?.cancel();
    _loading = true;
    notifyListeners();

    _sub = _firestore.watchEmployeeCommissions(
      _currentEmployeeId!,
      statusFilter: _statusFilter,
      monthFilter: _monthFilter,
    ).listen(
      (list) {
        _records = list;
        _loading = false;
        notifyListeners();
      },
      onError: (e) {
        _error   = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  // Computed totals
  double get totalPending =>
      _records.where((r) => r.isPending).fold(0.0, (sum, r) => sum + r.amount);

  double get totalPaid =>
      _records.where((r) => r.isPaid).fold(0.0, (sum, r) => sum + r.amount);

  double get totalAll =>
      _records.fold(0.0, (sum, r) => sum + r.amount);

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
