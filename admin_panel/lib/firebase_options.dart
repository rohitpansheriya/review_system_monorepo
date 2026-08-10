// lib/firebase_options.dart
// Generated from project config (review-system-prod-49b7a).
// Values sourced from .env at the monorepo root.
// Replace with `flutterfire configure` output once CLI login is available.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'DefaultFirebaseOptions are only configured for Web. '
      'Run flutterfire configure for other platforms.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCzP1jhiOrhBJ8A2y5fxs2ducbxT9UqT90',
    authDomain: 'review-system-prod-49b7a.firebaseapp.com',
    projectId: 'review-system-prod-49b7a',
    storageBucket: 'review-system-prod-49b7a.firebasestorage.app',
    messagingSenderId: '1091002138393',
    appId: '1:1091002138393:web:841d4de99d22f6817f0f88',
    measurementId: 'G-HY60V126M4',
  );
}
