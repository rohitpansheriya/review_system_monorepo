// lib/core/constants.dart
// Central config: collection names, emulator hosts, app-wide constants.

class AppConstants {
  // ── Firestore collection names ──────────────────────────────────────────────
  static const String colBusinesses    = 'businesses';
  static const String colBranches      = 'branches';
  static const String colEmployees     = 'employees';
  static const String colCommission    = 'commission_records';
  static const String colTemplates     = 'category_templates';
  static const String colNotifications = 'notifications';

  // ── Firebase Auth custom claim key ─────────────────────────────────────────
  static const String claimRole = 'role';

  // ── Role values ─────────────────────────────────────────────────────────────
  static const String roleAdmin    = 'admin';
  static const String roleEmployee = 'employee';
  static const String roleOwner    = 'owner';

  // ── Emulator hosts (used in main.dart when kDebugMode) ──────────────────────
  static const String emulatorHost          = 'localhost';
  static const int    emulatorAuthPort      = 9099;
  static const int    emulatorFirestorePort = 8080;
  static const int    emulatorFunctionsPort = 5001;
  static const int    emulatorStoragePort   = 9199;

  // ── Cloud Function names ────────────────────────────────────────────────────
  static const String fnSearchPlaces      = 'searchPlaces';
  static const String fnGenerateBranchQr  = 'generateBranchQr';
  /// Creates a fresh Razorpay Payment Link for a pending_payment draft,
  /// emails it to the owner, and returns short_url for WhatsApp sharing.
  /// (Change 3 — resend payment link)
  static const String fnResendPaymentLink = 'resendPaymentLink';

  // ── Star routing option values ──────────────────────────────────────────────
  static const String routingThankyou = 'thankyou';
  static const String routingWhatsapp = 'whatsapp';
  static const String routingGoogle   = 'google';

  // ── Subscription statuses ───────────────────────────────────────────────────
  /// Draft — enrolled but not yet paid. Invisible to all production lifecycle
  /// jobs (renewal, counters, notifications). Visible in the employee list only.
  static const String statusPendingPayment = 'pending_payment';
  static const String statusActive         = 'active';
  static const String statusGracePeriod    = 'grace_period';
  static const String statusDeleted        = 'deleted';

  // ── Standee fulfillment statuses (Change 2) ─────────────────────────────────
  /// Four-state lifecycle for the physical acrylic standee.
  /// Stored on branches/{id}.standee_status; updated by the employee on-site.
  /// Set to [standeeNotOrdered] when the branch is first activated.
  static const String standeeNotOrdered = 'not_ordered';
  static const String standeePrinted    = 'printed';
  static const String standeeShipped    = 'shipped';
  static const String standeeDelivered  = 'delivered';

  /// Ordered progression used by the standee status picker UI.
  static const List<String> standeeStatuses = [
    standeeNotOrdered,
    standeePrinted,
    standeeShipped,
    standeeDelivered,
  ];

  /// Human-readable labels for each standee status value.
  static const Map<String, String> standeeStatusLabels = {
    standeeNotOrdered: 'Not ordered',
    standeePrinted:    'Printed',
    standeeShipped:    'Shipped',
    standeeDelivered:  'Delivered',
  };

  // ── Logo upload quality gate (Change 4) ─────────────────────────────────────
  /// Minimum dimension (width AND height) in pixels required for a logo upload.
  /// Logos are printed on the acrylic standee — anything below this size
  /// will render blurry at 300 dpi. Rejection is client-side; never silently
  /// downscale and accept.
  static const int minLogoPx = 500;

  // ── Commission statuses ─────────────────────────────────────────────────────
  static const String commPending  = 'pending';
  static const String commVerified = 'verified';
  static const String commPaid     = 'paid';

  // ── Renewal period ──────────────────────────────────────────────────────────
  static const int renewalDays = 365;
}
