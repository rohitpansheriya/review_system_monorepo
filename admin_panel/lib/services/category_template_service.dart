// lib/services/category_template_service.dart
//
// Admin Category Template Service (Phrase Pool Management).
//
// STUB NOTICE:
// Per 07-review-template-system.md & Doc 04 (Admin Panel), the admin-side UI
// for editing phrase pools, adding translations, and managing pool versions is
// deferred to Doc 04 (Admin Panel).
//
// This service defines the data model & service interface for pure Firestore
// phrase editing without code deploys.

import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryTemplateService {
  final FirebaseFirestore _db;

  CategoryTemplateService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // ── [STUB: Doc 04] Get template by ID ─────────────────────────────────────
  Future<Map<String, dynamic>?> getTemplate(String templateId) async {
    final snap = await _db.collection('category_templates').doc(templateId).get();
    return snap.data();
  }

  // ── [STUB: Doc 04] Save / Upsert category template ────────────────────────
  Future<void> saveTemplate(
    String templateId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('category_templates')
        .doc(templateId)
        .set(data, SetOptions(merge: true));
  }

  // ── [STUB: Doc 04] Add phrase variant to a pool version ───────────────────
  Future<void> addPhraseVariant({
    required String templateId,
    required String categoryName,
    required String poolVersion, // e.g. "v1", "v2", "v3"
    required String language,    // "en", "hi", "gu"
    required String phrase,
  }) async {
    // STUB: Admin UI will call this to append a phrase to a category pool.
    // Pure data update in Firestore — no code deployment needed.
    final ref = _db.collection('category_templates').doc(templateId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data       = snap.data() ?? {};
      final categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);

      for (final cat in categories) {
        if (cat['name'] == categoryName) {
          if (language == 'en') {
            final versions = Map<String, dynamic>.from(cat['phrase_pool_versions'] ?? {});
            final list     = List<String>.from(versions[poolVersion] ?? []);
            list.add(phrase);
            versions[poolVersion] = list;
            cat['phrase_pool_versions'] = versions;
            cat['phrase_pool']          = list;
          } else {
            final translations = Map<String, dynamic>.from(cat['translations'] ?? {});
            final langData     = Map<String, dynamic>.from(translations[language] ?? {});
            final versions     = Map<String, dynamic>.from(langData['phrase_pool_versions'] ?? {});
            final list         = List<String>.from(versions[poolVersion] ?? []);
            list.add(phrase);
            versions[poolVersion] = list;
            langData['phrase_pool_versions'] = versions;
            langData['phrase_pool']          = list;
            translations[language]         = langData;
            cat['translations']             = translations;
          }
          break;
        }
      }

      tx.update(ref, {'categories': categories});
    });
  }

  // ── [STUB: Doc 04] Retire / Remove phrase variant ─────────────────────────
  Future<void> retirePhraseVariant({
    required String templateId,
    required String categoryName,
    required String poolVersion,
    required String language,
    required int index,
  }) async {
    // STUB: Admin UI calls this to retire an outdated phrase variant.
    final ref = _db.collection('category_templates').doc(templateId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data       = snap.data() ?? {};
      final categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);

      for (final cat in categories) {
        if (cat['name'] == categoryName) {
          if (language == 'en') {
            final versions = Map<String, dynamic>.from(cat['phrase_pool_versions'] ?? {});
            final list     = List<String>.from(versions[poolVersion] ?? []);
            if (index >= 0 && index < list.length) {
              list.removeAt(index);
              versions[poolVersion] = list;
              cat['phrase_pool_versions'] = versions;
              cat['phrase_pool']          = list;
            }
          }
          break;
        }
      }

      tx.update(ref, {'categories': categories});
    });
  }

  // ── [STUB: Doc 04] Assign Pool Version to Business / Branch ─────────────
  Future<void> assignPoolVersion({
    required String businessId,
    String? branchId,
    required String poolVersion, // "v1", "v2", "v3"
  }) async {
    // STUB: Assigns a pool version to a business or branch to mitigate duplicate content.
    if (branchId != null) {
      await _db
          .collection('businesses')
          .doc(businessId)
          .collection('branches')
          .doc(branchId)
          .update({'pool_version': poolVersion});
    } else {
      await _db
          .collection('businesses')
          .doc(businessId)
          .update({'pool_version': poolVersion});
    }
  }
}
