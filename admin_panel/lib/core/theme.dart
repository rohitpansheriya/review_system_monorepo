// lib/core/theme.dart
//
// Material 3 theme for the Review System employee/admin panel.
//
// Design intent: credible B2B tool used on-site with business owners.
//   - Brand tokens sourced from the customer review page for product coherence.
//   - Explicit ColorScheme (not fromSeed) to precisely match brand palette.
//   - Clear semantic colors for subscription + standee states.
//   - Inter font throughout — matches review page typography.
//   - Consistent component polish via ThemeData only — no ad-hoc Color() on screens.
//
// Brand palette (from review page index.html):
//   primary         #00458b   — navy blue
//   secondary       #2575fc   — bright blue / accent
//   surface         #ffffff
//   background      #f0f4f8   — soft blue-grey
//   text            #1a2340   — near-black navy
//   muted text      #6b7a99   — slate
//   border          #dce6f5   — pale blue
//   star/highlight  #ffc107   — amber
//
// Semantic color map (subscription_status → UI):
//   active          → green   #16A34A  bg #DCFCE7
//   pending_payment → amber   #F59E0B  bg #FEF3C7
//   grace_period    → orange  #EA580C  bg #FFEDD5
//   deleted         → grey    #6B7280  bg #F1F5F9
//   due_soon        → orange  #EA580C  bg #FFF7ED
//
// Semantic color map (standee_status → UI):
//   not_ordered     → grey    #6B7280
//   printed         → blue    #2575fc
//   shipped         → amber   #F59E0B
//   delivered       → green   #16A34A

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm  = 6;
  static const double md  = 10;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double full = 999; // pill shape
}

/// Named semantic color constants — use these in screens instead of raw Colors.*
class AppColors {
  AppColors._();

  // ── Brand ───────────────────────────────────────────────────────────────────
  static const Color primary   = Color(0xFF00458B); // navy
  static const Color secondary = Color(0xFF2575FC); // bright blue
  static const Color star      = Color(0xFFFFC107); // amber star
  static const Color warning   = Color(0xFFD97706); // amber/warning

  // ── Subscription status backgrounds ─────────────────────────────────────────
  static const Color activeBg         = Color(0xFFDCFCE7); // green-100
  static const Color pendingBg        = Color(0xFFFEF3C7); // amber-100
  static const Color graceBg          = Color(0xFFFFEDD5); // orange-100
  static const Color deletedBg        = Color(0xFFF1F5F9); // slate-100
  static const Color dueSoonBg        = Color(0xFFFFF7ED); // orange-50

  // ── Subscription status foregrounds ─────────────────────────────────────────
  static const Color activeFg         = Color(0xFF16A34A); // green-600
  static const Color pendingFg        = Color(0xFFF59E0B); // amber-500
  static const Color graceFg          = Color(0xFFEA580C); // orange-600
  static const Color deletedFg        = Color(0xFF6B7280); // grey-500
  static const Color dueSoonFg        = Color(0xFFEA580C); // orange-600

  // ── Commission status backgrounds ────────────────────────────────────────────
  static const Color commPendingBg    = Color(0xFFFEF3C7); // amber-100
  static const Color commVerifiedBg   = Color(0xFFDBEAFE); // blue-100
  static const Color commPaidBg       = Color(0xFFDCFCE7); // green-100
  static const Color commDisputedBg   = Color(0xFFFEE2E2); // red-100

  // ── Commission status foregrounds ────────────────────────────────────────────
  static const Color commPendingFg    = Color(0xFFD97706); // amber-600
  static const Color commVerifiedFg   = Color(0xFF2563EB); // blue-600
  static const Color commPaidFg       = Color(0xFF16A34A); // green-600
  static const Color commDisputedFg   = Color(0xFFDC2626); // red-600
}

// ── Theme ─────────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  // ── Explicit brand ColorScheme ───────────────────────────────────────────────
  static ColorScheme get _cs => const ColorScheme(
    brightness:            Brightness.light,

    // Core brand
    primary:               Color(0xFF00458B), // navy
    onPrimary:             Color(0xFFFFFFFF),
    primaryContainer:      Color(0xFFD3E5FF), // light navy tint
    onPrimaryContainer:    Color(0xFF001D40),

    // Secondary / accent
    secondary:             Color(0xFF2575FC), // bright blue
    onSecondary:           Color(0xFFFFFFFF),
    secondaryContainer:    Color(0xFFD9E6FF),
    onSecondaryContainer:  Color(0xFF001551),

    // Tertiary (star/highlight)
    tertiary:              Color(0xFFF59E0B), // amber
    onTertiary:            Color(0xFFFFFFFF),
    tertiaryContainer:     Color(0xFFFEF3C7),
    onTertiaryContainer:   Color(0xFF3D2500),

    // Surface
    surface:               Color(0xFFFFFFFF),
    onSurface:             Color(0xFF1A2340),  // near-black navy
    surfaceContainerLowest: Color(0xFFF0F4F8), // background
    surfaceContainerLow:    Color(0xFFE8EFF7),
    surfaceContainer:       Color(0xFFDCE8F4),
    surfaceContainerHigh:   Color(0xFFD0DCEE),
    surfaceContainerHighest: Color(0xFFC4D0E8),
    onSurfaceVariant:      Color(0xFF6B7A99), // muted text

    // Outline
    outline:               Color(0xFF8899BB),
    outlineVariant:        Color(0xFFDCE6F5), // brand border

    // Error
    error:                 Color(0xFFDC2626), // red-600
    onError:               Color(0xFFFFFFFF),
    errorContainer:        Color(0xFFFEE2E2), // red-100
    onErrorContainer:      Color(0xFF7F1D1D), // red-900

    // Inverse
    inverseSurface:        Color(0xFF1A2340),
    onInverseSurface:      Color(0xFFEEF2FF),
    inversePrimary:        Color(0xFF9EC7FF),

    // Scrim / shadow
    scrim:                 Color(0xFF000000),
    shadow:                Color(0xFF000000),
  );

  // ── Light theme ──────────────────────────────────────────────────────────────
  static ThemeData get light {
    final cs = _cs;

    final base = ThemeData(
      useMaterial3:   true,
      colorScheme:    cs,
      scaffoldBackgroundColor: cs.surfaceContainerLowest,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        // Display
        displayLarge:   GoogleFonts.inter(fontSize: 57, fontWeight: FontWeight.w400, color: cs.onSurface),
        displayMedium:  GoogleFonts.inter(fontSize: 45, fontWeight: FontWeight.w400, color: cs.onSurface),
        displaySmall:   GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w400, color: cs.onSurface),
        // Headlines: Inter semibold
        headlineLarge:  GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: cs.onSurface),
        headlineMedium: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
        headlineSmall:  GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
        // Titles
        titleLarge:     GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleMedium:    GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleSmall:     GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
        // Body
        bodyLarge:   GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: cs.onSurface),
        bodyMedium:  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: cs.onSurface),
        bodySmall:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant),
        // Labels
        labelLarge:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
        labelSmall:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
      ),
    );

    return base.copyWith(
      // ── AppBar — primary brand color (navy) ───────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle:            false,
        elevation:              0,
        scrolledUnderElevation: 0,
        backgroundColor:        cs.primary,
        foregroundColor:        cs.onPrimary,
        surfaceTintColor:       Colors.transparent,
        iconTheme:              const IconThemeData(color: Colors.white),
        actionsIconTheme:       const IconThemeData(color: Colors.white),
        titleTextStyle: GoogleFonts.inter(
          fontSize:   17,
          fontWeight: FontWeight.w600,
          color:      cs.onPrimary,
        ),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────────
      cardTheme: CardTheme(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: cs.outlineVariant),
        ),
        margin: EdgeInsets.zero,
        shadowColor: const Color(0xFF00458B).withValues(alpha: 0.08),
      ),

      // ── Input fields ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:      true,
        fillColor:   cs.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        hintStyle:  GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        helperStyle: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        errorStyle:  GoogleFonts.inter(fontSize: 11, color: cs.error),
        isDense: false,
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.error)) {
            return GoogleFonts.inter(fontSize: 13, color: cs.error);
          }
          if (states.contains(WidgetState.focused)) {
            return GoogleFonts.inter(fontSize: 13, color: cs.primary);
          }
          return GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant);
        }),
      ),

      // ── Elevated button (primary CTA) ────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:         cs.primary,
          foregroundColor:         cs.onPrimary,
          disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
          elevation:               0,
          shadowColor:             Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Filled button ────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(88, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),

      // ── Floating action button ───────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.secondary,
        foregroundColor: cs.onSecondary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),

      // ── Snackbar ─────────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
        backgroundColor: const Color(0xFF1A2340), // brand near-black
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        actionTextColor: cs.primaryContainer,
      ),

      // ── Chips (status badges) ────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Segmented button (filter bar) ────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
          selectedBackgroundColor: const Color(0xFF00458B),
          selectedForegroundColor: Colors.white,
        ),
      ),

      // ── List tile ────────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: AppSpacing.sm,
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────────
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }

  // ── Subscription status semantic colors ─────────────────────────────────────
  // Background fill color for a subscription status badge.
  static Color statusColor(String status) {
    switch (status) {
      case 'active':          return AppColors.activeBg;
      case 'due_soon':        return AppColors.dueSoonBg;
      case 'grace_period':    return AppColors.graceBg;
      case 'suspended':       return const Color(0xFFFEE2E2);
      case 'deleted':         return AppColors.deletedBg;
      case 'pending_payment': return AppColors.pendingBg;
      default:                return AppColors.deletedBg;
    }
  }

  // Foreground (text/icon) color for a subscription status badge.
  static Color statusForeground(String status) {
    switch (status) {
      case 'active':          return AppColors.activeFg;
      case 'due_soon':        return AppColors.dueSoonFg;
      case 'grace_period':    return AppColors.graceFg;
      case 'suspended':       return const Color(0xFFDC2626);
      case 'deleted':         return AppColors.deletedFg;
      case 'pending_payment': return AppColors.pendingFg;
      default:                return AppColors.deletedFg;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'active':          return 'Active';
      case 'due_soon':        return 'Renewal due soon';
      case 'grace_period':    return 'Grace period';
      case 'suspended':       return 'Suspended';
      case 'deleted':         return 'Deleted';
      case 'pending_payment': return 'Awaiting payment';
      default:                return status;
    }
  }

  // ── Standee status semantic colors ─────────────────────────────────────────
  // Background fill color for a standee status badge.
  static Color standeeStatusColor(String status) {
    switch (status) {
      case 'not_ordered': return const Color(0xFFF1F5F9); // grey-100
      case 'ordered':     return const Color(0xFFEDE9FE); // purple-100
      case 'printed':     return const Color(0xFFDBEAFE); // blue-100
      case 'shipped':     return AppColors.pendingBg;     // amber-100
      case 'delivered':   return AppColors.activeBg;      // green-100
      default:            return const Color(0xFFF1F5F9);
    }
  }

  // Foreground (text/icon) color for a standee status badge.
  static Color standeeStatusForeground(String status) {
    switch (status) {
      case 'not_ordered': return AppColors.deletedFg;    // grey-500
      case 'ordered':     return const Color(0xFF7C3AED); // purple-600
      case 'printed':     return AppColors.secondary;    // blue
      case 'shipped':     return AppColors.pendingFg;    // amber
      case 'delivered':   return AppColors.activeFg;     // green
      default:            return AppColors.deletedFg;
    }
  }

  // ── Commission status semantic colors ───────────────────────────────────────
  static Color commissionStatusColor(String status) {
    switch (status) {
      case 'pending':  return AppColors.commPendingBg;
      case 'verified': return AppColors.commVerifiedBg;
      case 'paid':     return AppColors.commPaidBg;
      case 'disputed': return AppColors.commDisputedBg;
      default:         return AppColors.deletedBg;
    }
  }

  static Color commissionStatusForeground(String status) {
    switch (status) {
      case 'pending':  return AppColors.commPendingFg;
      case 'verified': return AppColors.commVerifiedFg;
      case 'paid':     return AppColors.commPaidFg;
      case 'disputed': return AppColors.commDisputedFg;
      default:         return AppColors.deletedFg;
    }
  }
}
