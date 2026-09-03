// lib/core/string_utils.dart

/// Utility functions for text transformations, normalization, and live sanitization.
class StringUtils {
  /// Trims leading/trailing whitespace and collapses internal consecutive whitespace to a single space.
  static String collapseWhitespace(String? input) {
    if (input == null) return '';
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Sanitizes a Place ID by stripping all leading, trailing, and internal whitespace and newlines.
  /// Does NOT alter or substitute any other characters.
  static String sanitizePlaceId(String? input) {
    if (input == null) return '';
    return input.trim().replaceAll(RegExp(r'\s+'), '');
  }

  /// Validates if a Place ID format is URL-safe (letters, digits, - and _).
  /// Google Place IDs contain only [a-zA-Z0-9_-].
  static bool isValidPlaceIdFormat(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    final clean = sanitizePlaceId(input);
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(clean);
  }

  /// Sanitizes an email address (trimmed and lowercased).
  static String sanitizeEmail(String? input) {
    if (input == null) return '';
    return input.trim().toLowerCase();
  }

  /// Converts an input string to Title Case / Capitalized Words.
  /// Automatically capitalizes the first letter of every word while lowercasing the rest.
  /// Example:
  ///   "shree ram sweets" -> "Shree Ram Sweets"
  ///   "RAJESH PATEL"     -> "Rajesh Patel"
  ///   "adajan branch"    -> "Adajan Branch"
  static String toTitleCase(String? input) {
    if (input == null || input.trim().isEmpty) return '';
    return input.trim().split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return '';
      if (word.length == 1) return word.toUpperCase();
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Parses and divides raw bulk pasted text into individual clean review phrases.
  /// Handles:
  /// - Newline-separated lists (`\n`, `\r\n`)
  /// - Semicolon-separated lists (`;`)
  /// - Numbered list prefixes (`1.`, `2)`, `[3]`, etc.)
  /// - Bullet point prefixes (`-`, `*`, `•`, `–`, `—`, `>`)
  /// - Enclosing quotes (`"`, `'`)
  /// - Strips excess whitespace and deduplicates case-insensitively.
  static List<String> parseBulkPhrases(String? rawText) {
    if (rawText == null || rawText.trim().isEmpty) return [];

    final lines = rawText.split(RegExp(r'[\r\n]+'));
    final rawChunks = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.contains(';')) {
        rawChunks.addAll(trimmed.split(';'));
      } else {
        rawChunks.add(trimmed);
      }
    }

    final results = <String>[];
    final seen = <String>{};

    for (final chunk in rawChunks) {
      var p = chunk.trim();
      if (p.isEmpty) continue;

      // Strip leading list numbers: "1. ", "1) ", "(1) ", "1 - "
      p = p.replaceAll(RegExp(r'^\s*\(?\d+[\.\)\-\:]\s*'), '');

      // Strip leading bullet symbols: "- ", "* ", "• ", "– ", "— ", "> "
      p = p.replaceAll(RegExp(r'^\s*[\-\*\•\–\—\>\#\+]\s*'), '');

      // Strip enclosing quotes: "Hello" -> Hello
      if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
        if (p.length >= 2) {
          p = p.substring(1, p.length - 1).trim();
        }
      }

      p = collapseWhitespace(p);
      if (p.isNotEmpty && !seen.contains(p.toLowerCase())) {
        seen.add(p.toLowerCase());
        results.add(p);
      }
    }

    return results;
  }
}

