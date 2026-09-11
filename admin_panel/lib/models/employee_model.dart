// lib/models/employee_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeModel {
  final String id;
  final String name;
  final String contact; // email
  final String role;
  final bool active;
  final int totalEnrollments;
  final int thisMonthEnrollments;

  const EmployeeModel({
    required this.id,
    required this.name,
    required this.contact,
    required this.role,
    required this.active,
    required this.totalEnrollments,
    required this.thisMonthEnrollments,
  });

  factory EmployeeModel.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final d = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    return EmployeeModel(
      id:                   doc.id,
      name:                 d['name']?.toString() ?? '',
      contact:              d['contact']?.toString() ?? '',
      role:                 d['role']?.toString() ?? '',
      active:               d['active'] as bool? ?? true,
      totalEnrollments:     (d['total_enrollments'] as num?)?.toInt() ?? 0,
      thisMonthEnrollments: (d['this_month_enrollments'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name':                   name,
    'contact':                contact,
    'role':                   role,
    'active':                 active,
    'total_enrollments':      totalEnrollments,
    'this_month_enrollments': thisMonthEnrollments,
  };
}
