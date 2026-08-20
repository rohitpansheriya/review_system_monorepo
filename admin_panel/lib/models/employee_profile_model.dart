// lib/models/employee_profile_model.dart
//
// Extends the employees/{uid} schema with:
//   uid, status, totalEnrollments, thisMonthEnrollments
//   profile.*      — personal details the employee maintains
//   payout.*       — bank or UPI payout details
//   documents      — list of uploaded KYC doc references (Storage paths, NOT bytes)
//   documents_verified — "pending" | "verified" | "rejected"
//
// Firestore path: employees/{uid}  (same doc as EmployeeModel — merged schema)

import 'package:cloud_firestore/cloud_firestore.dart';

// ── PayoutMethod ─────────────────────────────────────────────────────────────

enum PayoutMethod { bank, upi }

extension PayoutMethodLabel on PayoutMethod {
  String get label => this == PayoutMethod.bank ? 'Bank Transfer' : 'UPI';
  String get value => this == PayoutMethod.bank ? 'bank' : 'upi';

  static PayoutMethod fromString(String? s) =>
      s == 'upi' ? PayoutMethod.upi : PayoutMethod.bank;
}

// ── EmployeeDocument ──────────────────────────────────────────────────────────

class EmployeeDocument {
  final String    storagePath;   // e.g. "employee_docs/{uid}/aadhaar_1691234567.jpg"
  final String    documentType;  // e.g. "Aadhaar", "PAN", "Bank passbook"
  final DateTime? uploadedAt;

  const EmployeeDocument({
    required this.storagePath,
    required this.documentType,
    this.uploadedAt,
  });

  factory EmployeeDocument.fromMap(Map<String, dynamic> m) => EmployeeDocument(
        storagePath:  m['path']          as String? ?? '',
        documentType: m['document_type'] as String? ?? '',
        uploadedAt:   (m['uploaded_at']  as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'path':          storagePath,
        'document_type': documentType,
        'uploaded_at':   uploadedAt != null
            ? Timestamp.fromDate(uploadedAt!)
            : FieldValue.serverTimestamp(),
      };
}

// ── EmployeeProfileModel ──────────────────────────────────────────────────────

class EmployeeProfileModel {
  final String uid;
  final String status; // "active" | "inactive"
  final int totalEnrollments;
  final int thisMonthEnrollments;

  // ── Profile section ──────────────────────────────────────────────────────
  final String fullName;
  final String email;
  final String phone;
  final String address;

  // ── Payout section ───────────────────────────────────────────────────────
  final PayoutMethod  payoutMethod;
  final String?       bankAccountNo;
  final String?       bankIfsc;
  final String?       upiId;

  // ── Documents section ─────────────────────────────────────────────────────
  final List<EmployeeDocument> documents;
  final String                 documentsVerified; // "pending" | "verified" | "rejected"

  const EmployeeProfileModel({
    required this.uid,
    this.status = 'active',
    this.totalEnrollments = 0,
    this.thisMonthEnrollments = 0,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.address,
    required this.payoutMethod,
    this.bankAccountNo,
    this.bankIfsc,
    this.upiId,
    required this.documents,
    required this.documentsVerified,
  });

  bool get isActive => status == 'active';
  String get name => fullName.isNotEmpty ? fullName : email;

  // ── Empty state ───────────────────────────────────────────────────────────
  static const empty = EmployeeProfileModel(
    uid:               '',
    fullName:          '',
    email:             '',
    phone:             '',
    address:           '',
    payoutMethod:      PayoutMethod.bank,
    documents:         [],
    documentsVerified: 'pending',
  );

  // ── From Firestore ────────────────────────────────────────────────────────
  factory EmployeeProfileModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    final profile = d['profile'] as Map<String, dynamic>? ?? {};
    final payout  = d['payout']  as Map<String, dynamic>? ?? {};
    final rawDocs = d['documents'] as List<dynamic>? ?? [];

    final topName  = d['name'] as String? ?? '';
    final topEmail = d['email'] as String? ?? d['contact'] as String? ?? '';
    final topPhone = d['phone'] as String? ?? '';

    return EmployeeProfileModel(
      uid:                  doc.id,
      status:               d['status'] as String? ?? (d['active'] == false ? 'inactive' : 'active'),
      totalEnrollments:     (d['total_enrollments'] as num?)?.toInt() ?? 0,
      thisMonthEnrollments: (d['this_month_enrollments'] as num?)?.toInt() ?? 0,
      fullName:             (profile['full_name'] as String? ?? '').isNotEmpty
                                ? (profile['full_name'] as String)
                                : topName,
      email:                (profile['email'] as String? ?? '').isNotEmpty
                                ? (profile['email'] as String)
                                : topEmail,
      phone:                (profile['phone'] as String? ?? '').isNotEmpty
                                ? (profile['phone'] as String)
                                : topPhone,
      address:              profile['address'] as String? ?? '',

      payoutMethod:  PayoutMethodLabel.fromString(payout['payout_method'] as String?),
      bankAccountNo: payout['bank_account_no'] as String?,
      bankIfsc:      payout['bank_ifsc']        as String?,
      upiId:         payout['upi_id']           as String?,

      documents: rawDocs
          .map((e) => EmployeeDocument.fromMap(e as Map<String, dynamic>))
          .toList(),
      documentsVerified: d['documents_verified'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> profilePayload() => {
        'profile.full_name': fullName,
        'profile.email':     email,
        'profile.phone':     phone,
        'profile.address':   address,
      };

  Map<String, dynamic> payoutPayload() {
    final m = <String, dynamic>{
      'payout.payout_method': payoutMethod.value,
      'documents_verified': 'pending',
    };
    if (payoutMethod == PayoutMethod.bank) {
      m['payout.bank_account_no'] = bankAccountNo ?? '';
      m['payout.bank_ifsc']       = bankIfsc      ?? '';
      m['payout.upi_id']          = null;
    } else {
      m['payout.upi_id']           = upiId         ?? '';
      m['payout.bank_account_no']  = null;
      m['payout.bank_ifsc']        = null;
    }
    return m;
  }

  EmployeeProfileModel copyWith({
    String?               uid,
    String?               status,
    int?                  totalEnrollments,
    int?                  thisMonthEnrollments,
    String?               fullName,
    String?               email,
    String?               phone,
    String?               address,
    PayoutMethod?         payoutMethod,
    String?               bankAccountNo,
    String?               bankIfsc,
    String?               upiId,
    List<EmployeeDocument>? documents,
    String?               documentsVerified,
  }) => EmployeeProfileModel(
    uid:                  uid                  ?? this.uid,
    status:               status               ?? this.status,
    totalEnrollments:     totalEnrollments     ?? this.totalEnrollments,
    thisMonthEnrollments: thisMonthEnrollments ?? this.thisMonthEnrollments,
    fullName:          fullName          ?? this.fullName,
    email:             email             ?? this.email,
    phone:             phone             ?? this.phone,
    address:           address           ?? this.address,
    payoutMethod:      payoutMethod      ?? this.payoutMethod,
    bankAccountNo:     bankAccountNo     ?? this.bankAccountNo,
    bankIfsc:          bankIfsc          ?? this.bankIfsc,
    upiId:             upiId             ?? this.upiId,
    documents:         documents         ?? this.documents,
    documentsVerified: documentsVerified ?? this.documentsVerified,
  );

  bool get isVerified => documentsVerified == 'verified';
}
