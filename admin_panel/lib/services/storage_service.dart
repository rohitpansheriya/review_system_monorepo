// lib/services/storage_service.dart
// Handles logo upload to Firebase Storage.

import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage;
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Uploads logo bytes to Storage and returns the download URL.
  /// Path: logos/{uuid}.{ext}
  Future<String> uploadLogo(Uint8List bytes, String mimeType) async {
    final ext = mimeType.contains('png') ? 'png' : 'jpg';
    final path = 'logos/${const Uuid().v4()}.$ext';
    final ref  = _storage.ref(path);
    final meta = SettableMetadata(contentType: mimeType);
    await ref.putData(bytes, meta);
    return await ref.getDownloadURL();
  }
}
