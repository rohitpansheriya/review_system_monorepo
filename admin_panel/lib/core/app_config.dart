// lib/core/app_config.dart
// Centralized runtime config resolution for Flutter Web.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

class AppConfig {
  /// Pulls the Razorpay Key ID from:
  /// 1. `window.__APP_CONFIG__.razorpayKeyId`
  /// 2. `window.__FIREBASE_CONFIG__.razorpayKeyId`
  /// 3. `--dart-define=RAZORPAY_KEY_ID=...` compilation flag
  /// 4. Fallback placeholder (safe empty or placeholder)
  static String get razorpayKeyId {
    // 1. Check --dart-define compilation flag
    const fromEnv = String.fromEnvironment('RAZORPAY_KEY_ID');
    if (fromEnv.isNotEmpty && !fromEnv.contains('PLACEHOLDER')) {
      return fromEnv;
    }

    // 2. Check window.__APP_CONFIG__ injected at runtime
    if (js.context.hasProperty('__APP_CONFIG__')) {
      final appCfg = js.context['__APP_CONFIG__'];
      if (appCfg != null && appCfg['razorpayKeyId'] != null) {
        final key = appCfg['razorpayKeyId'].toString().trim();
        if (key.isNotEmpty && !key.contains('PLACEHOLDER')) return key;
      }
    }

    // 3. Check window.__FIREBASE_CONFIG__ injected at runtime
    if (js.context.hasProperty('__FIREBASE_CONFIG__')) {
      final fbCfg = js.context['__FIREBASE_CONFIG__'];
      if (fbCfg != null && fbCfg['razorpayKeyId'] != null) {
        final key = fbCfg['razorpayKeyId'].toString().trim();
        if (key.isNotEmpty && !key.contains('PLACEHOLDER')) return key;
      }
    }

    return '';
  }
}
