// lib/models/branch_draft.dart
// Form-state model for one branch during enrollment.
// This is NOT a Firestore model — it is mutable UI state held by EnrollProvider.
// BranchFormWidget reads and writes this object directly via the provider.

import '../core/string_utils.dart';
import '../services/places_service.dart';

class BranchDraft {
  // ── Identification ─────────────────────────────────────────────────────────
  /// Required in multi-branch mode; auto-set to brand name in single mode.
  String name = '';

  // ── Location ───────────────────────────────────────────────────────────────
  String whatsappNumber = '';
  /// Always required. May be auto-filled by place search or typed manually.
  String address = '';
  /// Optional — enrollment never hard-blocks on this field being blank.
  String? placeId;
  String? googleReviewLink;

  // ── WhatsApp monitoring contact (Change 5) ─────────────────────────────────
  /// Who monitors the WhatsApp number for incoming 1-3 star feedback messages.
  /// Required in both single and multi-branch modes.
  /// e.g. "Owner", "Manager Ravi", "Front Desk".
  /// Preserved across staff changes — update via owner dashboard (doc 02, deferred).
  String whatsappMonitoredBy = '';

  // ── Place auto-search transient state ─────────────────────────────────────
  bool isSearching = false;
  List<PlaceCandidate> candidates = [];
  bool placePrefilled = false; // true when auto-fill was used (shown as chip)
  String? searchError;

  // ── Star routing ───────────────────────────────────────────────────────────
  // null = not set; blocks submit until all 5 have a value.
  Map<String, String?> starRouting = {
    '1': null, '2': null, '3': null, '4': null, '5': null,
  };

  static final RegExp _validIndianPhone = RegExp(r'^\+91[6-9]\d{9}$');

  // ── Computed ───────────────────────────────────────────────────────────────
  bool get starRoutingComplete =>
      starRouting.values.every((v) => v != null && v.isNotEmpty);

  /// Returns true when this branch has all required fields filled.
  /// [requireBranchName] = true in multi-branch mode.
  bool isComplete({required bool requireBranchName}) =>
      (!requireBranchName || name.trim().isNotEmpty) &&
      _validIndianPhone.hasMatch(whatsappNumber.trim()) &&
      whatsappMonitoredBy.trim().isNotEmpty &&   // Change 5: required field
      address.trim().isNotEmpty &&
      (placeId != null && placeId!.trim().isNotEmpty) &&
      starRoutingComplete;

  // ── Mutations ─────────────────────────────────────────────────────────────

  void setStarRoute(String star, String route) {
    starRouting[star] = route;
  }

  /// Called when user confirms a candidate from Place auto-search.
  /// Pre-fills address and placeId; both remain editable by the user.
  void confirmCandidate(PlaceCandidate candidate) {
    placeId          = candidate.placeId.isEmpty ? null : StringUtils.sanitizePlaceId(candidate.placeId);
    address          = candidate.address;
    googleReviewLink = candidate.placeId.isNotEmpty
        ? 'https://search.google.com/local/writereview?placeid=${StringUtils.sanitizePlaceId(candidate.placeId)}'
        : null;
    placePrefilled = true;
    candidates     = [];
    searchError    = null;
  }

  /// Sets a Place ID.
  /// Strips leading, trailing, and internal whitespace and newlines.
  /// Does NOT substitute or re-encode characters — stores byte-for-byte as entered after trimming/stripping.
  void setPlaceId(String value) {
    final cleaned = StringUtils.sanitizePlaceId(value);
    if (cleaned.isEmpty) {
      placeId = null;
      googleReviewLink = null;
      return;
    }

    placeId = cleaned;
    googleReviewLink =
        'https://search.google.com/local/writereview?placeid=$placeId';
  }

  /// Clears search results without switching to any locked "mode".
  /// The form always shows address + Place ID fields — no locked state.
  void clearSearch() {
    candidates     = [];
    searchError    = null;
    isSearching    = false;
    placePrefilled = false;
  }

  // ── Firestore serialization ────────────────────────────────────────────────

  /// Snapshot of star routing with all values confirmed non-null.
  /// Call only after [starRoutingComplete] is true.
  Map<String, String> get starRoutingAsMap =>
      starRouting.map((k, v) => MapEntry(k, v!));

  /// Firestore-ready map for `businesses/{id}/branches/{id}`.
  /// All fields per 00-architecture-and-schema.md are written at draft time.
  /// qr_code_id / nfc_tag_id / nfc_url left null — generated on payment activation (RULE 4).
  /// standee_status / standee_status_updated_at set on activation (Change 2).
  /// plain_qr_storage_path set on activation (Change 1).
  Map<String, dynamic> toFirestore() => {
    'branch_name':          name.trim(),
    'address':              address.trim(),
    'whatsapp_number':      whatsappNumber.trim(),
    // Change 5: who watches the WhatsApp channel for incoming 1-3 star messages.
    'whatsapp_monitored_by': whatsappMonitoredBy.trim(),
    'place_id':             placeId,            // null ok — optional
    // Derived from place_id; null when no place_id provided.
    // Written even when null so the field is always present on the branch doc.
    'google_review_link':   googleReviewLink,
    'star_routing_config':  starRoutingAsMap,
    'category_override_id': null,
    // STUB: generated on activation by the payment webhook (RULE 4 — doc 09).
    'qr_code_id':           null,
    'nfc_tag_id':           null,
    // nfc_url: set by the payment webhook once the branch ID is known & QR generated.
    'nfc_url':              null,
    // Change 1: plain printable QR path — set by activation webhook.
    'plain_qr_storage_path': null,
    // Lifecycle and payment status at draft time: strictly pending_payment
    'subscription_status':  'pending_payment',
    'payment_mode':         'pending',
    // Change 2: standee fulfillment state — set to not_ordered at draft time.
    'standee_status':       'not_ordered',
    // stats_summary: initialized to zeros at draft time (complete per 00 schema).
    'stats_summary': {
      'total_scans':             0,
      'total_reviews_redirected': 0,
      // star_counts: one key per star (1–5), init to 0
      'star_counts': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
      'last_updated':            null,
    },
  };
}
