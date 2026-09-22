// lib/core/image_utils.dart
// Client-side image resizing and compression utilities for business logos.

import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageUtils {
  /// Resizes image bytes so that neither width nor height exceeds [maxDimension] (default: 512px).
  /// Preserves exact aspect ratio and re-encodes as optimized PNG bytes.
  /// If the image is already within bounds, it returns clean compressed PNG bytes.
  static Future<Uint8List> resizeAndCompressLogo(
    Uint8List originalBytes, {
    int maxDimension = 512,
  }) async {
    try {
      // 1. Initial decode to measure original dimensions
      final codec = await ui.instantiateImageCodec(originalBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final int origW = img.width;
      final int origH = img.height;
      img.dispose();
      codec.dispose();

      // If dimensions are within maxDimension, re-encode to optimize
      if (origW <= maxDimension && origH <= maxDimension) {
        final directCodec = await ui.instantiateImageCodec(originalBytes);
        final directFrame = await directCodec.getNextFrame();
        final directImg = directFrame.image;
        final byteData = await directImg.toByteData(format: ui.ImageByteFormat.png);
        directImg.dispose();
        directCodec.dispose();
        if (byteData != null) {
          return byteData.buffer.asUint8List();
        }
        return originalBytes;
      }

      // 2. Compute proportional target dimensions
      int targetW;
      int targetH;
      if (origW >= origH) {
        targetW = maxDimension;
        targetH = ((origH * maxDimension) / origW).round();
      } else {
        targetH = maxDimension;
        targetW = ((origW * maxDimension) / origH).round();
      }

      if (targetW <= 0) targetW = 1;
      if (targetH <= 0) targetH = 1;

      // 3. Rescale using hardware-accelerated decode
      final scaledCodec = await ui.instantiateImageCodec(
        originalBytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final scaledFrame = await scaledCodec.getNextFrame();
      final scaledImg = scaledFrame.image;
      final byteData = await scaledImg.toByteData(format: ui.ImageByteFormat.png);
      scaledImg.dispose();
      scaledCodec.dispose();

      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
      return originalBytes;
    } catch (e) {
      // Fallback to original bytes if decoding/scaling encounters unexpected format
      return originalBytes;
    }
  }
}
