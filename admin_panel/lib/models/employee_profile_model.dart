// lib/models/employee_profile_model.dart
//
// Extends the employees/{uid} schema with:
//   profile.*      — personal details the employee maintains
//   payout.*       — bank or UPI payout details
//   documents      — list of uploaded KYC doc references (Storage paths, NOT bytes)
//   documents_verified — "pending" | "verified"  (set to "pending" by client,
//                        only admin/Cloud Function may flip to "verified")
//
// Firestore path: employees/{uid}  (same doc as EmployeeModel — merged schema)
// This model is read alongside EmployeeModel; neither replaces the other.

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
// A single uploaded KYC / ID document reference.
// Bytes are NEVER stored in Firestore — only the Storage path + metadata.

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
  final String                 documentsVerified; // "pending" | "verified"

  const EmployeeProfileModel({
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

  // ── Empty state ───────────────────────────────────────────────────────────
  static const empty = EmployeeProfileModel(
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

    return EmployeeProfileModel(
      fullName:  profile['full_name'] as String? ?? '',
      email:     profile['email']     as String? ?? '',
      phone:     profile['phone']     as String? ?? '',
      address:   profile['address']   as String? ?? '',

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

  // ── Firestore payloads (never write the whole model — write only the
  //    sub-map that changed so we don't accidentally clobber sibling fields) ─

  Map<String, dynamic> profilePayload() => {
        'profile.full_name': fullName,
        'profile.email':     email,
        'profile.phone':     phone,
        'profile.address':   address,
      };

  Map<String, dynamic> payoutPayload() {
    final m = <String, dynamic>{
      'payout.payout_method': payoutMethod.value,
      // Reset verification whenever payout details change (security safeguard).
      'documents_verified': 'pending',
    };
    if (payoutMethod == PayoutMethod.bank) {
      m['payout.bank_account_no'] = bankAccountNo ?? '';
      m['payout.bank_ifsc']       = bankIfsc      ?? '';
      m['payout.upi_id']          = null; // clear old UPI when switching to bank
    } else {
      m['payout.upi_id']           = upiId         ?? '';
      m['payout.bank_account_no']  = null; // clear old bank when switching to UPI
      m['payout.bank_ifsc']        = null;
    }
    return m;
  }

  // ── copyWith ──────────────────────────────────────────────────────────────
  EmployeeProfileModel copyWith({
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
