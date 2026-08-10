// lib/services/places_service.dart
// Calls the existing searchPlaces Cloud Function (doc 09 / placeSearch.ts).
//
// ROOT CAUSE OF PREVIOUS BUG:
//   The Cloud Function signature is:
//     input:  { businessName: string, city: string }  — two separate fields
//   The previous client sent:
//     { query: "Business Name City" }  — one combined string
//   This caused an `invalid-argument` error on every call. Fixed below.
//
// API KEY NOTE:
//   PLACE_API_KEY is in Secret Manager (not .env files).
//   In the emulator it must be set in functions/.env.local as:
//     PLACE_API_KEY=your_key_here
//   Without a real key the function returns error → Flutter falls back to
//   empty list → user sees the manual entry fallback (correct behavior).

import 'package:cloud_functions/cloud_functions.dart';
import '../core/constants.dart';

class PlaceCandidate {
  final String placeId;
  final String name;
  final String address;
  final String? photoReference; // Opaque token — use getPlacePhoto function

  const PlaceCandidate({
    required this.placeId,
    required this.name,
    required this.address,
    this.photoReference,
  });

  factory PlaceCandidate.fromMap(Map map) => PlaceCandidate(
        placeId:        map['placeId']        as String? ?? '',
        name:           map['name']           as String? ?? '',
        address:        map['address']        as String? ?? '',
        photoReference: map['photoReference'] as String?,
      );
}

class PlacesService {
  final FirebaseFunctions _functions;

  PlacesService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Searches Google Places for [businessName] in [city].
  ///
  /// The Cloud Function expects TWO separate fields:
  ///   { businessName: string, city: string }
  ///
  /// Returns up to 3 candidates, or empty list on any error (graceful).
  /// The caller should always show the manual fallback when list is empty.
  Future<List<PlaceCandidate>> search(String businessName, String city) async {
    final name = businessName.trim();
    final loc  = city.trim();
    if (name.isEmpty || loc.isEmpty) return [];

    try {
      final result = await _functions
          .httpsCallable(AppConstants.fnSearchPlaces)
          .call({
            'businessName': name, // ← was 'query'; Cloud Function expects separate fields
            'city':         loc,
          });

      final data = result.data;
      if (data == null) return [];

      final candidates = data['candidates'] as List? ?? [];
      return candidates
          .map((c) => PlaceCandidate.fromMap(c as Map))
          .where((c) => c.placeId.isNotEmpty || c.name.isNotEmpty)
          .take(3)
          .toList();

    } on FirebaseFunctionsException catch (e) {
      // Gracefully return empty — UI shows manual fallback.
      // ignore: avoid_print
      print('PlacesService.search error: ${e.code} — ${e.message}');
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('PlacesService.search unexpected: $e');
      return [];
    }
  }
}
