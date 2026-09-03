// lib/models/lead_model.dart
//
// Represents an inbound website lead captured from the public landing page.

import 'package:cloud_firestore/cloud_firestore.dart';

class LeadModel {
  final String id;
  final String name;
  final String businessName;
  final String phone;
  final String city;
  final String message;
  final String status; // 'lead', 'contacted', 'converted', 'archived'
  final String source;
  final DateTime createdAt;

  const LeadModel({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phone,
    required this.city,
    required this.message,
    required this.status,
    required this.source,
    required this.createdAt,
  });

  factory LeadModel.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    DateTime dt;
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      dt = rawTs.toDate();
    } else {
      final rawCreatedAt = data['created_at'] as String?;
      if (rawCreatedAt != null) {
        dt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
      } else {
        dt = DateTime.now();
      }
    }

    return LeadModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Lead',
      businessName: data['business_name'] as String? ?? '—',
      phone: data['phone'] as String? ?? '—',
      city: data['city'] as String? ?? '—',
      message: data['message'] as String? ?? '',
      status: data['status'] as String? ?? 'lead',
      source: data['source'] as String? ?? 'landing_page',
      createdAt: dt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'business_name': businessName,
      'phone': phone,
      'city': city,
      'message': message,
      'status': status,
      'source': source,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
