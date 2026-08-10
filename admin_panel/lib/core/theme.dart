// lib/core/theme.dart
//
// Material 3 theme for the Review System employee/admin panel.
//
// Design intent: credible B2B tool used on-site with business owners.
//   - Professional slate-indigo primary (not playful).
//   - Clear semantic colors for subscription states.
//   - Inter font for headings, system-sans for body.
//   - Consistent component polish via ThemeData only — no ad-hoc Color() on screens.
//
// Semantic color map (subscription states → UI):
//   active         → success green  #22C55E
//   grace_period   → error red      #EF4444
//   pending_payment→ amber          #F59E0B
//   deleted        → neutral grey   #6B7280
//   due_soon       → orange         #F97316

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Brand colors ────────────────────────────────────────────────────
  static const Color _seed = Color(0xFF3B4DB8); // slate-indigo

  // ── Light theme ──────────────────────────────────────────────────────────────
  static ThemeData get light {
    final cs = ColorScheme.fromSeed(
      seedColor:  _seed,
      brightness: Brightness.light,
    );

    final base = ThemeData(
      useMaterial3:   true,
      colorScheme:    cs,
      // Google Fonts Inter for headings; system-sans body via textTheme copy below
      textTheme: GoogleFonts.interTextTheme().copyWith(
        // Headlines: Inter semibold
        headlineLarge:  GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: cs.onSurface),
        headlineMedium: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
        headlineSmall:  GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleLarge:     GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleMedium:    GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleSmall:     GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
        // Body: Inter regular
        bodyLarge:   GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: cs.onSurface),
        bodyMedium:  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: cs.onSurface),
        bodySmall:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant),
        labelLarge:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
        labelSmall:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
      ),
    );

    return base.copyWith(
      // ── AppBar ────────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────────
      cardTheme: CardTheme(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Input fields ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
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
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Filled button (secondary CTA) ────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // ── Snackbar ─────────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: const Color(0xFF1E293B), // slate-900
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        actionTextColor: cs.primaryContainer,
      ),

      // ── Chips (status badges) ────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Segmented button (filter bar) ────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // ── List tile ────────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────────
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }

  // ── Status badge colors ─────────────────────────────────────────────────────
  // Returns the background fill color for a subscription status badge.
  static Color statusColor(String status) {
    switch (status) {
      case 'active':          return const Color(0xFFDCFCE7); // green-100
      case 'due_soon':        return const Color(0xFFFEF3C7); // amber-100
      case 'grace_period':    return const Color(0xFFFEE2E2); // red-100
      case 'deleted':         return const Color(0xFFF1F5F9); // slate-100
      case 'pending_payment': return const Color(0xFFEDE9FE); // violet-100
      default:                return const Color(0xFFF1F5F9);
    }
  }

  // Returns the foreground (text/icon) color for a subscription status badge.
  static Color statusForeground(String status) {
    switch (status) {
      case 'active':          return const Color(0xFF16A34A); // green-600
      case 'due_soon':        return const Color(0xFFD97706); // amber-600
      case 'grace_period':    return const Color(0xFFDC2626); // red-600
      case 'deleted':         return const Color(0xFF64748B); // slate-500
      case 'pending_payment': return const Color(0xFF7C3AED); // violet-700
      default:                return const Color(0xFF64748B);
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'active':          return 'Active';
      case 'due_soon':        return 'Renewal due soon';
      case 'grace_period':    return 'Grace period';
      case 'deleted':         return 'Deleted';
      case 'pending_payment': return 'Awaiting payment';
      default:                return status;
    }
  }

  static Color commissionStatusColor(String status) {
    switch (status) {
      case 'pending':  return const Color(0xFFFEF3C7);
      case 'verified': return const Color(0xFFDBEAFE);
      case 'paid':     return const Color(0xFFDCFCE7);
      default:         return const Color(0xFFF1F5F9);
    }
  }

  static Color commissionStatusForeground(String status) {
    switch (status) {
      case 'pending':  return const Color(0xFFD97706);
      case 'verified': return const Color(0xFF2563EB);
      case 'paid':     return const Color(0xFF16A34A);
      default:         return const Color(0xFF64748B);
    }
  }
}
