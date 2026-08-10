// lib/providers/commission_provider.dart
// Streams commission records for the current employee.
// Also exposes the logCashPayment action.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/commission_record_model.dart';
import '../models/business_model.dart';
import '../services/firestore_service.dart';

class CommissionProvider extends ChangeNotifier {
  final FirestoreService _firestore;

  List<CommissionRecordModel> _records   = [];
  List<BusinessModel>         _myBizList = []; // for cash payment dialog picker
  bool    _loading   = true;
  bool    _submitting = false;
  String? _error;
  StreamSubscription? _sub;

  List<CommissionRecordModel> get records    => _records;
  List<BusinessModel>         get myBizList  => _myBizList;
  bool                        get loading    => _loading;
  bool                        get submitting => _submitting;
  String?                     get error      => _error;

  CommissionProvider({required FirestoreService firestoreService})
      : _firestore = firestoreService;

  void startListening(String employeeId) {
    _sub?.cancel();
    _loading = true;
    notifyListeners();

    _sub = _firestore.watchMyCommissions(employeeId).listen(
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

    // Load businesses for cash payment dialog picker — one-shot, not a stream.
    // Uses a 3-year window to capture all ever-enrolled businesses.
    _firestore.fetchMyBusinessesPage(
      employeeId:   employeeId,
      statusFilter: 'all',
      since:        DateTime.now().subtract(const Duration(days: 1095)), // ~3 yrs
      limit:        100,
    ).then((list) {
      _myBizList = list;
      notifyListeners();
    }).catchError((_) {}); // biz list failure is non-critical
  }

  /// Logs a cash payment. Creates a pending commission_records doc.
  /// Two-step verification (doc 06) is deferred.
  Future<String?> logCashPayment({
    required String employeeId,
    required String businessId,
    required double amount,
  }) async {
    if (amount <= 0) return 'Amount must be greater than zero.';
    _submitting = true;
    _error      = null;
    notifyListeners();
    try {
      await _firestore.logCashPayment(
        employeeId: employeeId,
        businessId: businessId,
        amount:     amount,
      );
      _submitting = false;
      notifyListeners();
      return null;
    } catch (e) {
      _submitting = false;
      _error      = e.toString();
      notifyListeners();
      return _error;
    }
  }

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
