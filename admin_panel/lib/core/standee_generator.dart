// lib/core/standee_generator.dart
//
// Generates the official 4×6 inch (1200 × 1800 px @ 300 DPI) AppNexa Smart Standee
// matching the 3D acrylic mockup on appnexa.co.in:
//   - Top Navy Gradient Header Pill with Brand Logo & Business Name
//   - "Google Reviews ★★★★★" with official Google multi-colored typography
//   - NFC Contactless Zone with glowing radar halo and "TAP PHONE HERE"
//   - High-contrast QR Code with rounded finder patterns in deep navy (#0B1B3A)
//   - Bottom "OR SCAN CAMERA TO REVIEW" caption
//
// Exports high-resolution print-ready PNG via HTML5 Canvas.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:async';
import 'dart:math';
import 'package:qr/qr.dart';

class StandeeGenerator {
  static const int canvasWidth = 1200;
  static const int canvasHeight = 1800;

  /// Helper to draw a rounded rectangle on CanvasRenderingContext2D
  static void _drawRoundedRect(
    html.CanvasRenderingContext2D ctx,
    double x,
    double y,
    double w,
    double h,
    double r,
  ) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  /// Generates the complete 4×6 Standee as a base64 PNG data URL.
  static Future<String> generateStandeeDataUrl({
    required String businessName,
    String? branchName,
    required String reviewUrl,
    String? logoUrl,
  }) async {
    final canvas = html.CanvasElement(width: canvasWidth, height: canvasHeight);
    final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;

    // ── 1. Background & Outer Card Frame ──────────────────────────────────────
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, canvasWidth, canvasHeight);

    // Outer subtle acrylic card border (inset 36px, radius 54px)
    _drawRoundedRect(ctx, 36, 36, canvasWidth - 72, canvasHeight - 72, 54);
    ctx.strokeStyle = '#E2E8F0';
    ctx.lineWidth = 4;
    ctx.stroke();

    // ── 2. Top Navy Brand Header Bar ──────────────────────────────────────────
    const double headerX = 90;
    const double headerY = 90;
    const double headerW = canvasWidth - (headerX * 2); // 1020
    const double headerH = 170;
    const double headerR = 36;

    final headerGrad = ctx.createLinearGradient(headerX, headerY, headerX + headerW, headerY + headerH);
    headerGrad.addColorStop(0, '#1B3A8C');
    headerGrad.addColorStop(1, '#2957C8');

    // Subtle drop shadow for header
    ctx.save();
    ctx.shadowColor = 'rgba(27, 58, 140, 0.18)';
    ctx.shadowBlur = 24;
    ctx.shadowOffsetY = 10;
    _drawRoundedRect(ctx, headerX, headerY, headerW, headerH, headerR);
    ctx.fillStyle = headerGrad;
    ctx.fill();
    ctx.restore();

    // Business Name Typography (Centered, bold, no logo, no branch name)
    ctx.fillStyle = '#FFFFFF';
    final cleanBizName = businessName.trim().isEmpty ? 'Your Business' : businessName.trim();
    
    // Scale font size dynamically based on length, maintaining 1:1 parity between
    // Business Name and the Google Reviews / Stars row.
    double fontSize = 48;
    if (cleanBizName.length > 30) {
      fontSize = 38;
    } else if (cleanBizName.length > 22) {
      fontSize = 42;
    }
    ctx.font = '800 ${fontSize.toInt()}px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    const double headerCenterX = headerX + (headerW / 2); // 600
    const double headerCenterY = headerY + (headerH / 2); // 175
    final double maxTextWidth = headerW - 80; // 940 px

    ctx.fillText(cleanBizName, headerCenterX, headerCenterY, maxTextWidth);

    // ── 3. Equidistant Spacing & Google Reviews Row ───────────────────────────
    // Header Bottom = 260.
    // Equal gap = 80-100px.
    // Google Reviews Y = 340.
    // NFC Halo Top = 440.
    const double gRowY = 340;
    _drawGoogleReviewsRow(ctx, canvasWidth / 2, gRowY, fontSize: fontSize);

    // ── 4. NFC Contactless Zone (Raised & Separated from QR Code) ─────────────
    // Halo radius 65 -> center Y = 440 + 65 = 505
    const double nfcCenterY = 505;
    _drawNfcZone(ctx, canvasWidth / 2, nfcCenterY);

    // ── 5. High-Resolution QR Frame & Matrix (Separated by 145px) ─────────────
    const double qrFrameW = 740;
    const double qrFrameH = 740;
    const double qrFrameX = (canvasWidth - qrFrameW) / 2; // 230
    const double qrFrameY = 770;

    // White rounded card frame with navy accent border
    ctx.save();
    ctx.shadowColor = 'rgba(27, 58, 140, 0.09)';
    ctx.shadowBlur = 32;
    ctx.shadowOffsetY = 12;
    _drawRoundedRect(ctx, qrFrameX, qrFrameY, qrFrameW, qrFrameH, 44);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
    ctx.restore();

    ctx.strokeStyle = '#1B3A8C';
    ctx.lineWidth = 10;
    _drawRoundedRect(ctx, qrFrameX, qrFrameY, qrFrameW, qrFrameH, 44);
    ctx.stroke();

    // Generate & draw QR matrix with 75px quiet zone margin (guaranteeing > 4 modules)
    const double qrMargin = 75;
    _drawQrCode(ctx, reviewUrl, qrFrameX + qrMargin, qrFrameY + qrMargin, qrFrameW - (qrMargin * 2));

    // ── 6. Bottom Prompt: "OR SCAN CAMERA TO REVIEW" ──────────────────────────
    ctx.fillStyle = '#64748B';
    ctx.font = '800 30px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('OR SCAN CAMERA TO REVIEW', canvasWidth / 2, 1600);

    // ── 7. Subtle Footer Branding (No TM) ─────────────────────────────────────
    ctx.fillStyle = '#94A3B8';
    ctx.font = '600 22px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.fillText('AppNexa Smart Standee  •  appnexa.co.in', canvasWidth / 2, 1700);

    return canvas.toDataUrl('image/png');
  }

  /// Draws the Google multi-color letters and gold stars with zero overlap
  static void _drawGoogleReviewsRow(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double y, {
    double fontSize = 48,
  }) {
    ctx.save();
    ctx.font = '800 ${fontSize.toInt()}px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';

    final letters = ['G', 'o', 'o', 'g', 'l', 'e'];
    final colors = [
      '#4285F4', // G - Blue
      '#EA4335', // o - Red
      '#FBBC05', // o - Yellow
      '#4285F4', // g - Blue
      '#34A853', // l - Green
      '#EA4335', // e - Red
    ];

    // Measure each individual letter dynamically at the matching fontSize
    final List<double> letterWidths = [];
    double googleTotalW = 0;
    for (final char in letters) {
      final w = (ctx.measureText(char).width ?? (28 * fontSize / 48)).toDouble();
      letterWidths.add(w);
      googleTotalW += w;
    }

    final double space1W = (ctx.measureText(' ').width ?? (14 * fontSize / 48)).toDouble();
    final double reviewsW = (ctx.measureText('Reviews').width ?? (180 * fontSize / 48)).toDouble();
    final double space2W = (ctx.measureText('   ').width ?? (28 * fontSize / 48)).toDouble();
    final double starsW = (ctx.measureText('★★★★★').width ?? (190 * fontSize / 48)).toDouble();

    final double totalW = googleTotalW + space1W + reviewsW + space2W + starsW;
    double curX = centerX - (totalW / 2);

    // 1. Draw "Google" colored letters
    for (int i = 0; i < letters.length; i++) {
      ctx.fillStyle = colors[i];
      ctx.fillText(letters[i], curX, y);
      curX += letterWidths[i];
    }

    // 2. Space between "Google" and "Reviews"
    curX += space1W;

    // 3. Draw "Reviews"
    ctx.fillStyle = '#0F172A';
    ctx.fillText('Reviews', curX, y);
    curX += reviewsW + space2W;

    // 4. Draw Gold Stars "★★★★★"
    ctx.fillStyle = '#FBBC05';
    ctx.fillText('★★★★★', curX, y);

    ctx.restore();
  }

  /// Draws the authentic Contactless Wave NFC button with radial halo and labels
  static void _drawNfcZone(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
  ) {
    ctx.save();

    // 1. Outer soft blue radiating halo ring (radius 65)
    ctx.beginPath();
    ctx.arc(centerX, centerY, 65, 0, pi * 2);
    ctx.fillStyle = '#EEF4FF';
    ctx.fill();
    ctx.strokeStyle = '#DBEAFE';
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.closePath();

    // 2. Inner vibrant royal blue button (radius 48)
    final nfcGrad = ctx.createLinearGradient(
      centerX - 48,
      centerY - 48,
      centerX + 48,
      centerY + 48,
    );
    nfcGrad.addColorStop(0, '#1E40AF');
    nfcGrad.addColorStop(1, '#2563EB');

    ctx.beginPath();
    ctx.arc(centerX, centerY, 48, 0, pi * 2);
    ctx.fillStyle = nfcGrad;
    ctx.fill();
    ctx.closePath();

    // 3. Official ISO / EMV Contactless NFC Radiating Waves (4 curved concentric arcs)
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 5.0;
    ctx.lineCap = 'round';

    final double arcOriginX = centerX - 16;
    final double arcOriginY = centerY;

    // Smallest inner arc
    ctx.beginPath();
    ctx.arc(arcOriginX, arcOriginY, 10, -0.75, 0.75);
    ctx.stroke();

    // 2nd arc
    ctx.beginPath();
    ctx.arc(arcOriginX, arcOriginY, 19, -0.75, 0.75);
    ctx.stroke();

    // 3rd arc
    ctx.beginPath();
    ctx.arc(arcOriginX, arcOriginY, 28, -0.75, 0.75);
    ctx.stroke();

    // 4th outer arc
    ctx.beginPath();
    ctx.arc(arcOriginX, arcOriginY, 37, -0.75, 0.75);
    ctx.stroke();

    // 4. "TAP PHONE HERE" text
    ctx.fillStyle = '#0F172A';
    ctx.font = '800 30px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('TAP PHONE HERE', centerX, centerY + 86);

    // 5. "Instant NFC Contactless"
    ctx.fillStyle = '#64748B';
    ctx.font = '600 22px "Plus Jakarta Sans", "Inter", sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('Instant NFC Contactless', centerX, centerY + 120);

    ctx.restore();
  }

  /// Draws ISO/IEC 18004 compliant QR Code matrix with standard sharp square finder patterns
  /// and high error correction (Level H - 30%) in deep midnight navy (#08142A) for instant
  /// recognition by smartphone cameras at any scanning angle.
  static void _drawQrCode(
    html.CanvasRenderingContext2D ctx,
    String data,
    double startX,
    double startY,
    double size,
  ) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final qrImage = QrImage(qrCode);
    final int modules = qrImage.moduleCount;
    final double moduleSize = size / modules;
    const String darkColor = '#08142A'; // High-contrast midnight navy

    ctx.save();

    // Helper: checks if a module is inside one of the three 7x7 corner finder patterns
    bool isInsideFinderEye(int r, int c) {
      if (r < 7 && c < 7) return true; // Top-Left
      if (r < 7 && c >= modules - 7) return true; // Top-Right
      if (r >= modules - 7 && c < 7) return true; // Bottom-Left
      return false;
    }

    // 1. Draw solid data modules (excluding finder pattern areas)
    ctx.fillStyle = darkColor;
    for (int r = 0; r < modules; r++) {
      for (int c = 0; c < modules; c++) {
        if (isInsideFinderEye(r, c)) continue;
        if (qrImage.isDark(r, c)) {
          final x = startX + (c * moduleSize);
          final y = startY + (r * moduleSize);
          // +0.3px slight expansion prevents canvas subpixel rendering seams
          ctx.fillRect(x, y, moduleSize + 0.3, moduleSize + 0.3);
        }
      }
    }

    // 2. Draw standard ISO 18004 7×7 square finder eyes at 3 corners
    // (Solid 7x7 outer square, 5x5 white cutout, 3x3 solid core = strict 1:1:3:1:1 ratio)
    void drawStandardFinderEye(double eyeX, double eyeY) {
      final double eyeSize = moduleSize * 7;

      // Outer 7×7 module solid square
      ctx.fillStyle = darkColor;
      ctx.fillRect(eyeX, eyeY, eyeSize, eyeSize);

      // Inner 5×5 module clean white cutout (1 module inset on all 4 sides)
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(
        eyeX + moduleSize,
        eyeY + moduleSize,
        moduleSize * 5,
        moduleSize * 5,
      );

      // Core 3×3 module solid dark square (2 modules inset on all 4 sides)
      ctx.fillStyle = darkColor;
      ctx.fillRect(
        eyeX + (moduleSize * 2),
        eyeY + (moduleSize * 2),
        moduleSize * 3,
        moduleSize * 3,
      );
    }

    // Clear 1-module white separator areas around the 3 finder eyes to guarantee
    // clean quiet boundaries between the finder patterns and surrounding data.
    ctx.fillStyle = '#FFFFFF';
    // Top-Left 8×8 clear
    ctx.fillRect(startX, startY, moduleSize * 8, moduleSize * 8);
    // Top-Right 8×8 clear
    ctx.fillRect(startX + ((modules - 8) * moduleSize), startY, moduleSize * 8, moduleSize * 8);
    // Bottom-Left 8×8 clear
    ctx.fillRect(startX, startY + ((modules - 8) * moduleSize), moduleSize * 8, moduleSize * 8);

    // Render the 3 standard square finder eyes
    final double rightEyeX = startX + ((modules - 7) * moduleSize);
    final double bottomEyeY = startY + ((modules - 7) * moduleSize);

    // Top-Left Eye
    drawStandardFinderEye(startX, startY);
    // Top-Right Eye
    drawStandardFinderEye(rightEyeX, startY);
    // Bottom-Left Eye
    drawStandardFinderEye(startX, bottomEyeY);

    ctx.restore();
  }

  /// Triggers a direct download of the 4×6 standee PNG in the browser.
  static Future<void> downloadStandeePng({
    required String businessName,
    String? branchName,
    required String reviewUrl,
    String? logoUrl,
  }) async {
    final dataUrl = await generateStandeeDataUrl(
      businessName: businessName,
      branchName: branchName,
      reviewUrl: reviewUrl,
      logoUrl: logoUrl,
    );

    final cleanBiz = businessName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final cleanBranch = (branchName ?? '').replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final fileName = '$cleanBiz${cleanBranch.isNotEmpty ? "_$cleanBranch" : ""}_Standee_4x6.png';

    final anchor = html.AnchorElement(href: dataUrl)
      ..download = fileName
      ..target = '_blank';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  /// Triggers a direct download of a clean 600×600 plain QR code PNG.
  static void downloadPlainQrPng({
    required String businessName,
    String? branchName,
    required String reviewUrl,
  }) {
    final canvas = html.CanvasElement(width: 800, height: 800);
    final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 800, 800);

    // Generous 80px quiet zone margin (> 4 modules)
    _drawQrCode(ctx, reviewUrl, 80, 80, 640);

    final cleanBiz = businessName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final cleanBranch = (branchName ?? '').replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final fileName = '$cleanBiz${cleanBranch.isNotEmpty ? "_$cleanBranch" : ""}_QR_Plain.png';

    final anchor = html.AnchorElement(href: canvas.toDataUrl('image/png'))
      ..download = fileName
      ..target = '_blank';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
}
