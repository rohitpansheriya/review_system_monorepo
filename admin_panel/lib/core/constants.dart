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
  static const String fnSearchPlaces                 = 'searchPlaces';
  static const String fnGenerateBranchQr             = 'generateBranchQr';
  static const String fnResendPaymentLink            = 'resendPaymentLink';
  static const String fnSendCashPaymentVerification  = 'sendCashPaymentVerification';
  static const String fnConfirmCashPaymentOwner      = 'confirmCashPaymentOwner';
  static const String fnConfirmCashPaymentAdmin      = 'confirmCashPaymentAdmin';
  static const String fnMarkCommissionPaidAdmin      = 'markCommissionPaidAdmin';

  // ── Star routing option values ──────────────────────────────────────────────
  static const String routingThankyou = 'thankyou';
  static const String routingWhatsapp = 'whatsapp';
  static const String routingGoogle   = 'google';

  // ── Subscription statuses ───────────────────────────────────────────────────
  static const String statusPendingPayment = 'pending_payment';
  static const String statusActive         = 'active';
  static const String statusGracePeriod    = 'grace_period';
  static const String statusDeleted        = 'deleted';

  // ── Standee fulfillment statuses ────────────────────────────────────────────
  static const String standeeNotOrdered = 'not_ordered';
  static const String standeePrinted    = 'printed';
  static const String standeeShipped    = 'shipped';
  static const String standeeDelivered  = 'delivered';

  static const List<String> standeeStatuses = [
    standeeNotOrdered,
    standeePrinted,
    standeeShipped,
    standeeDelivered,
  ];

  static const Map<String, String> standeeStatusLabels = {
    standeeNotOrdered: 'Not ordered',
    standeePrinted:    'Printed',
    standeeShipped:    'Shipped',
    standeeDelivered:  'Delivered',
  };

  // ── Logo upload quality gate ────────────────────────────────────────────────
  static const int minLogoPx = 500;

  // ── Commission statuses (Doc 06) ────────────────────────────────────────────
  static const String commPending  = 'pending';
  static const String commVerified = 'verified';
  static const String commPaid     = 'paid';
  static const String commDisputed = 'disputed';

  // ── Renewal period ──────────────────────────────────────────────────────────
  static const int renewalDays = 365;
}
