// lib/services/storage_service.dart
// Handles file uploads to Firebase Storage.

import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/image_utils.dart';

class StorageService {
  final FirebaseStorage _storage;
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Resizes and compresses logo bytes client-side to max 512px, then uploads to Storage.
  /// Path: logos/{uuid}.png
  Future<String> uploadLogo(Uint8List bytes, String mimeType) async {
    final optimizedBytes = await ImageUtils.resizeAndCompressLogo(bytes, maxDimension: 512);
    const path = 'logos';
    final filePath = '$path/${const Uuid().v4()}.png';
    final ref  = _storage.ref(filePath);
    final meta = SettableMetadata(contentType: 'image/png');
    await ref.putData(optimizedBytes, meta);
    return await ref.getDownloadURL();
  }

  /// Uploads a KYC / ID document for an employee.
  /// Path: employee_docs/{uid}/{uuid}.{ext}
  /// Returns the Storage path (NOT the download URL — path is stored in Firestore
  /// and resolved to a download URL on demand via getDownloadURL()).
  Future<String> uploadDocument(
    String  employeeUid,
    Uint8List bytes,
    String  mimeType,
  ) async {
    final ext  = _extFor(mimeType);
    final path = 'employee_docs/$employeeUid/${const Uuid().v4()}.$ext';
    final ref  = _storage.ref(path);
    final meta = SettableMetadata(contentType: mimeType);
    await ref.putData(bytes, meta);
    return path; // caller stores the path in Firestore, not the URL
  }

  /// Returns a download URL for an arbitrary Storage path.
  /// Used to fetch KYC document links on demand.
  Future<String> getDownloadUrl(String storagePath) async {
    return _storage.ref(storagePath).getDownloadURL();
  }

  static String _extFor(String mimeType) {
    if (mimeType.contains('png'))  return 'png';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    if (mimeType.contains('pdf'))  return 'pdf';
    return 'bin';
  }
}
