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

  // ── [Lazy Load] Get template headers (metadata & category names only) ──
  Future<List<Map<String, dynamic>>> getTemplateHeaders() async {
    try {
      final snap = await _db.collection('category_templates').get();
      return snap.docs.map((d) {
        final data = d.data();
        final rawCats = data['categories'] as List? ?? [];
        final categoryNames = rawCats
            .map((c) => (c is Map) ? (c['name'] as String? ?? '') : '')
            .where((n) => n.isNotEmpty)
            .toList();

        return {
          'id': d.id,
          'business_type': data['business_type'] as String? ?? d.id,
          'category_names': categoryNames,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── [Lazy Load] Get phrases for a specific category on demand ─────────────
  Future<List<String>> getCategoryPhrases({
    required String templateId,
    required String categoryName,
    String version = 'v1',
    String language = 'en',
  }) async {
    try {
      final snap = await _db.collection('category_templates').doc(templateId).get();
      if (!snap.exists) return [];
      final data = snap.data() ?? {};
      final categories = data['categories'] as List? ?? [];
      for (final cat in categories) {
        if (cat is Map && cat['name'] == categoryName) {
          if (language == 'en') {
            final versions = cat['phrase_pool_versions'] as Map<String, dynamic>? ?? {};
            if (versions.containsKey(version)) {
              return List<String>.from(versions[version] as List? ?? []);
            }
            return List<String>.from(cat['phrase_pool'] as List? ?? []);
          } else {
            final translations = cat['translations'] as Map<String, dynamic>? ?? {};
            final langData = translations[language] as Map<String, dynamic>? ?? {};
            final versions = langData['phrase_pool_versions'] as Map<String, dynamic>? ?? {};
            if (versions.containsKey(version)) {
              return List<String>.from(versions[version] as List? ?? []);
            }
            return List<String>.from(langData['phrase_pool'] as List? ?? []);
          }
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── Get template by ID ───────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getTemplate(String templateId) async {
    final snap = await _db.collection('category_templates').doc(templateId).get();
    return snap.data();
  }

  // ── Create new Category Template ─────────────────────────────────────────
  Future<void> createTemplate({
    required String templateId,
    required String businessType,
    required String categoryName,
    required List<String> phrases,
  }) async {
    final cleanList = phrases.map((p) => p.trim()).where((p) => p.isNotEmpty).toSet().toList();
    await _db.collection('category_templates').doc(templateId).set({
      'business_type': businessType,
      'categories': [
        {
          'name': categoryName,
          'phrase_pool': cleanList,
          'phrase_pool_versions': {
            'v1': cleanList,
          },
        }
      ],
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Add New Category with Phrases to Existing Template ─────────────────────
  Future<void> addCategory({
    required String templateId,
    required String categoryName,
    required List<String> phrases,
  }) async {
    final ref = _db.collection('category_templates').doc(templateId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);
      final cleanList = phrases.map((p) => p.trim()).where((p) => p.isNotEmpty).toSet().toList();

      final existingIndex = categories.indexWhere((c) => c['name'] == categoryName);
      if (existingIndex >= 0) {
        final existingCat = categories[existingIndex];
        final versions = Map<String, dynamic>.from(existingCat['phrase_pool_versions'] ?? {});
        final list = List<String>.from(versions['v1'] ?? []);
        for (final p in cleanList) {
          if (!list.contains(p)) list.add(p);
        }
        versions['v1'] = list;
        existingCat['phrase_pool_versions'] = versions;
        existingCat['phrase_pool'] = list;
      } else {
        categories.add({
          'name': categoryName,
          'phrase_pool': cleanList,
          'phrase_pool_versions': {
            'v1': cleanList,
          },
        });
      }

      tx.update(ref, {'categories': categories});
    });
  }

  // ── Delete Category from Template ──────────────────────────────────────────
  Future<void> deleteCategory({
    required String templateId,
    required String categoryName,
  }) async {
    final ref = _db.collection('category_templates').doc(templateId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);
      categories.removeWhere((c) => c['name'] == categoryName);

      tx.update(ref, {'categories': categories});
    });
  }

  // ── Add Bulk Phrase Variants to a Category Pool ────────────────────────────
  Future<void> addPhrasesBulk({
    required String templateId,
    required String categoryName,
    required List<String> phrases,
    String poolVersion = 'v1',
    String language = 'en',
  }) async {
    final ref = _db.collection('category_templates').doc(templateId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);
      final cleanList = phrases.map((p) => p.trim()).where((p) => p.isNotEmpty).toSet().toList();

      for (final cat in categories) {
        if (cat['name'] == categoryName) {
          if (language == 'en') {
            final versions = Map<String, dynamic>.from(cat['phrase_pool_versions'] ?? {});
            final list = List<String>.from(versions[poolVersion] ?? []);
            for (final p in cleanList) {
              if (!list.contains(p)) list.add(p);
            }
            versions[poolVersion] = list;
            cat['phrase_pool_versions'] = versions;
            cat['phrase_pool'] = list;
          } else {
            final translations = Map<String, dynamic>.from(cat['translations'] ?? {});
            final langData = Map<String, dynamic>.from(translations[language] ?? {});
            final versions = Map<String, dynamic>.from(langData['phrase_pool_versions'] ?? {});
            final list = List<String>.from(versions[poolVersion] ?? []);
            for (final p in cleanList) {
              if (!list.contains(p)) list.add(p);
            }
            versions[poolVersion] = list;
            langData['phrase_pool_versions'] = versions;
            langData['phrase_pool'] = list;
            translations[language] = langData;
            cat['translations'] = translations;
          }
          break;
        }
      }

      tx.update(ref, {'categories': categories});
    });
  }

  // ── [STUB: Doc 04] Add phrase variant to a pool version ───────────────────
  Future<void> addPhraseVariant({
    required String templateId,
    required String categoryName,
    required String poolVersion, // e.g. "v1", "v2", "v3"
    required String language,    // "en", "hi", "gu"
    required String phrase,
  }) async {
    return addPhrasesBulk(
      templateId: templateId,
      categoryName: categoryName,
      phrases: [phrase],
      poolVersion: poolVersion,
      language: language,
    );
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
