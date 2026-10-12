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

  /// Strips leading emojis and symbols from a chip label for seamless sentence inclusion.
  static String stripLeadingEmoji(String? input) {
    if (input == null || input.trim().isEmpty) return '';
    return input.trim().replaceFirst(RegExp(r'^[^\w\s]+'), '').trim();
  }

  /// Checks if a string already begins with an emoji or symbol character.
  static bool hasLeadingEmoji(String text) {
    if (text.trim().isEmpty) return false;
    final trimmed = text.trim();
    final first = trimmed.runes.first;
    // Common emoji and symbol rune ranges
    if (first >= 0x1F000 && first <= 0x1FAFF) return true; // Misc Symbols, Pictographs, Emoticons, Transport
    if (first >= 0x2600 && first <= 0x27BF) return true;   // Misc symbols, Dingbats
    if (first >= 0x2300 && first <= 0x23FF) return true;   // Misc technical
    if (first >= 0x2B50 && first <= 0x2B55) return true;   // Stars
    if (first == 0x2022 || first == 0x2023 || first == 0x25AA || first == 0x25CF) return true; // bullets
    if (RegExp(r'^[\p{Extended_Pictographic}\u200d\uFE0F•\-★✦✨]', unicode: true).hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// Automatically attaches a relevant emoji based on keywords, step number, and archetype.
  static String autoPrependEmoji(String input, {int step = 1, String? archetype}) {
    final clean = collapseWhitespace(input);
    if (clean.isEmpty) return '';
    if (hasLeadingEmoji(clean)) return clean;

    final lower = clean.toLowerCase();

    // 1. Food & Beverage Keywords
    if (lower.contains('pizza') || lower.contains('calzone')) return '🍕 $clean';
    if (lower.contains('coffee') || lower.contains('espresso') || lower.contains('latte') || lower.contains('cappuccino') || lower.contains('mocha') || lower.contains('brew') || lower.contains('chai') || lower.contains('tea')) return '☕ $clean';
    if (lower.contains('burger') || lower.contains('sandwich') || lower.contains('panini') || lower.contains('wrap')) return '🍔 $clean';
    if (lower.contains('pasta') || lower.contains('noodle') || lower.contains('ramen') || lower.contains('spaghetti')) return '🍝 $clean';
    if (lower.contains('cake') || lower.contains('pastry') || lower.contains('brownie') || lower.contains('dessert') || lower.contains('waffle') || lower.contains('croissant') || lower.contains('bakery') || lower.contains('bake')) return '🍰 $clean';
    if (lower.contains('ice cream') || lower.contains('gelato') || lower.contains('sundae') || lower.contains('kulfi')) return '🍨 $clean';
    if (lower.contains('taco') || lower.contains('burrito') || lower.contains('nacho') || lower.contains('quesadilla')) return '🌮 $clean';
    if (lower.contains('sushi') || lower.contains('momo') || lower.contains('dumpling')) return '🍣 $clean';
    if (lower.contains('juice') || lower.contains('smoothie') || lower.contains('shake') || lower.contains('mojito') || lower.contains('mocktail') || lower.contains('cocktail') || lower.contains('drink') || lower.contains('boba')) return '🍹 $clean';
    if (lower.contains('biryani') || lower.contains('curry') || lower.contains('paneer') || lower.contains('tikka') || lower.contains('thali') || lower.contains('tandoor') || lower.contains('dal') || lower.contains('roti') || lower.contains('naan') || lower.contains('rice') || lower.contains('kebab') || lower.contains('dosa') || lower.contains('idli')) return '🍲 $clean';
    if (lower.contains('salad') || lower.contains('soup') || lower.contains('veg') || lower.contains('healthy') || lower.contains('bowl')) return '🥗 $clean';
    if (lower.contains('steak') || lower.contains('grill') || lower.contains('bbq') || lower.contains('chicken') || lower.contains('mutton') || lower.contains('meat') || lower.contains('fish') || lower.contains('prawn')) return '🥩 $clean';
    if (lower.contains('beer') || lower.contains('wine') || lower.contains('alcohol')) return '🍺 $clean';

    // 2. Beauty & Wellness Keywords
    if (lower.contains('hair') || lower.contains('cut') || lower.contains('trim') || lower.contains('styling') || lower.contains('fade') || lower.contains('balayage') || lower.contains('keratin') || lower.contains('blowout') || lower.contains('beard') || lower.contains('shave') || lower.contains('barber')) return '💇 $clean';
    if (lower.contains('facial') || lower.contains('cleanup') || lower.contains('hydrafacial') || lower.contains('glow') || lower.contains('skin') || lower.contains('peel')) return '💆 $clean';
    if (lower.contains('massage') || lower.contains('spa') || lower.contains('therapy') || lower.contains('sauna') || lower.contains('steam')) return '🧖 $clean';
    if (lower.contains('nail') || lower.contains('manicure') || lower.contains('pedicure')) return '💅 $clean';
    if (lower.contains('makeup') || lower.contains('bridal') || lower.contains('cosmetic') || lower.contains('makeover')) return '💄 $clean';
    if (lower.contains('tattoo') || lower.contains('piercing')) return '🎨 $clean';

    // 3. Healthcare, Dental & Fitness Keywords
    if (lower.contains('dent') || lower.contains('tooth') || lower.contains('teeth') || lower.contains('root canal') || lower.contains('aligner') || lower.contains('brace') || lower.contains('scaling') || lower.contains('implant')) return '🦷 $clean';
    if (lower.contains('doctor') || lower.contains('clinic') || lower.contains('consult') || lower.contains('treatment') || lower.contains('surgery') || lower.contains('diagnosis') || lower.contains('medical') || lower.contains('medicine')) return '🩺 $clean';
    if (lower.contains('eye') || lower.contains('vision') || lower.contains('optic') || lower.contains('glasses') || lower.contains('lens') || lower.contains('spectacle')) return '👁️ $clean';
    if (lower.contains('physio') || lower.contains('ortho') || lower.contains('joint') || lower.contains('rehab') || lower.contains('bone')) return '🦴 $clean';
    if (lower.contains('gym') || lower.contains('workout') || lower.contains('fitness') || lower.contains('trainer') || lower.contains('yoga') || lower.contains('crossfit') || lower.contains('exercise')) return '🏋️ $clean';

    // 4. Automotive & Garage Keywords
    if (lower.contains('car') || lower.contains('vehicle') || lower.contains('engine') || lower.contains('brake') || lower.contains('oil') || lower.contains('mechanic') || lower.contains('garage') || lower.contains('clutch') || lower.contains('ac repair')) return '🚗 $clean';
    if (lower.contains('detail') || lower.contains('wash') || lower.contains('foam') || lower.contains('cleaning') || lower.contains('vacuum')) return '🧼 $clean';
    if (lower.contains('ceramic') || lower.contains('ppf') || lower.contains('coating') || lower.contains('polish') || lower.contains('shine') || lower.contains('rubbing')) return '✨ $clean';
    if (lower.contains('tire') || lower.contains('tyre') || lower.contains('wheel') || lower.contains('alignment') || lower.contains('balancing')) return '🛞 $clean';
    if (lower.contains('bike') || lower.contains('motorcycle') || lower.contains('scooter')) return '🏍️ $clean';

    // 5. Retail, Jewelry & Fashion Keywords
    if (lower.contains('jewel') || lower.contains('gold') || lower.contains('diamond') || lower.contains('ring') || lower.contains('necklace') || lower.contains('earring') || lower.contains('silver')) return '💎 $clean';
    if (lower.contains('dress') || lower.contains('shirt') || lower.contains('suit') || lower.contains('saree') || lower.contains('lehenga') || lower.contains('cloth') || lower.contains('outfit') || lower.contains('apparel') || lower.contains('fashion')) return '👗 $clean';
    if (lower.contains('shoe') || lower.contains('sneaker') || lower.contains('footwear') || lower.contains('sandal') || lower.contains('heel')) return '👟 $clean';
    if (lower.contains('bag') || lower.contains('purse') || lower.contains('wallet') || lower.contains('luggage')) return '👜 $clean';
    if (lower.contains('watch') || lower.contains('clock')) return '⌚ $clean';
    if (lower.contains('phone') || lower.contains('electronic') || lower.contains('gadget') || lower.contains('device')) return '📱 $clean';

    // 6. IT & Tech Services Keywords
    if (lower.contains('software') || lower.contains('app dev') || lower.contains('code') || lower.contains('frontend') || lower.contains('backend') || lower.contains('full stack') || lower.contains('ui/ux') || lower.contains('developer') || lower.contains('programming')) return '💻 $clean';
    if (lower.contains('cloud') || lower.contains('devops') || lower.contains('aws') || lower.contains('azure') || lower.contains('server') || lower.contains('kubernetes') || lower.contains('docker')) return '☁️ $clean';
    if (lower.contains('security') || lower.contains('cyber') || lower.contains('firewall') || lower.contains('antivirus') || lower.contains('penetration') || lower.contains('audit')) return '🔒 $clean';
    if (lower.contains('computer') || lower.contains('laptop') || lower.contains('pc repair') || lower.contains('hardware') || lower.contains('ssd') || lower.contains('ram') || lower.contains('motherboard')) return '🖥️ $clean';
    if (lower.contains('network') || lower.contains('wifi') || lower.contains('lan') || lower.contains('router') || lower.contains('cabling')) return '🌐 $clean';
    if (lower.contains('data recovery') || lower.contains('backup') || lower.contains('database') || lower.contains('sql') || lower.contains('migration')) return '💾 $clean';

    // 7. Highlight & Quality (Step 2) Keywords
    if (lower.contains('taste') || lower.contains('flavor') || lower.contains('delicious') || lower.contains('spicy') || lower.contains('crispy') || lower.contains('juicy') || lower.contains('fresh') || lower.contains('tender') || lower.contains('tasty') || lower.contains('yum')) return '😋 $clean';
    if (lower.contains('cheese') || lower.contains('cheesy')) return '🧀 $clean';
    if (lower.contains('quality') || lower.contains('finish') || lower.contains('premium') || lower.contains('luxury') || lower.contains('perfection') || lower.contains('precise') || lower.contains('accurate')) return '💎 $clean';
    if (lower.contains('fast') || lower.contains('quick') || lower.contains('speed') || lower.contains('prompt') || lower.contains('turnaround') || lower.contains('express') || lower.contains('instant')) return '⚡ $clean';
    if (lower.contains('clean') || lower.contains('hygiene') || lower.contains('sanitized') || lower.contains('sterile') || lower.contains('spotless') || lower.contains('neat')) return '🧼 $clean';
    if (lower.contains('price') || lower.contains('value') || lower.contains('affordable') || lower.contains('budget') || lower.contains('rate') || lower.contains('billing') || lower.contains('cost') || lower.contains('discount')) return '🏷️ $clean';
    if (lower.contains('shine') || lower.contains('gloss') || lower.contains('showroom') || lower.contains('glow') || lower.contains('flawless') || lower.contains('elegant')) return '✨ $clean';
    if (lower.contains('gentle') || lower.contains('painless') || lower.contains('comfort') || lower.contains('smooth') || lower.contains('relax')) return '🌸 $clean';

    // 8. Experience, Atmosphere & Staff (Step 3) Keywords
    if (lower.contains('staff') || lower.contains('team') || lower.contains('doctor') || lower.contains('stylist') || lower.contains('waiter') || lower.contains('chef') || lower.contains('mechanic') || lower.contains('people') || lower.contains('service') || lower.contains('hospitality') || lower.contains('polite') || lower.contains('courteous') || lower.contains('friendly') || lower.contains('welcoming') || lower.contains('helpful')) return '😊 $clean';
    if (lower.contains('vibe') || lower.contains('ambiance') || lower.contains('atmosphere') || lower.contains('music') || lower.contains('cozy') || lower.contains('interior') || lower.contains('decor') || lower.contains('seating') || lower.contains('lighting')) return '✨ $clean';
    if (lower.contains('professional') || lower.contains('expert') || lower.contains('skilled') || lower.contains('experienced') || lower.contains('knowledgeable')) return '🎯 $clean';
    if (lower.contains('honest') || lower.contains('transparent') || lower.contains('genuine') || lower.contains('trust') || lower.contains('reliable')) return '🤝 $clean';
    if (lower.contains('delivery') || lower.contains('pickup') || lower.contains('packaging') || lower.contains('packing') || lower.contains('box')) return '📦 $clean';
    if (lower.contains('support') || lower.contains('care') || lower.contains('guidance') || lower.contains('advice') || lower.contains('consultation')) return '💬 $clean';

    // 9. Fallbacks based on Step & Archetype
    if (step == 1) {
      if (archetype == 'food_dining') return '🍽️ $clean';
      if (archetype == 'beauty_wellness') return '💇 $clean';
      if (archetype == 'healthcare_clinic') return '🩺 $clean';
      if (archetype == 'auto_services') return '🚗 $clean';
      if (archetype == 'retail_shopping') return '🛍️ $clean';
      if (archetype == 'it_services') return '💻 $clean';
      return '🏷️ $clean';
    } else if (step == 2) {
      return '✨ $clean';
    } else {
      return '😊 $clean';
    }
  }

  /// Capitalizes / CamelCases every word and attaches matching symbol.
  /// Example: "wood fired pizza" -> "🍕 Wood Fired Pizza"
  ///          "☕ cold brew" -> "☕ Cold Brew"
  static String formatChipText(String input, {int step = 1, String? archetype}) {
    var raw = collapseWhitespace(input);
    if (raw.isEmpty) return '';

    final hasEmoji = hasLeadingEmoji(raw);
    String emojiPrefix = '';
    String textOnly = raw;

    if (hasEmoji) {
      final stripped = stripLeadingEmoji(raw);
      if (stripped.isNotEmpty) {
        emojiPrefix = raw.substring(0, raw.length - stripped.length).trim();
        textOnly = stripped;
      }
    }

    // Title-case every word
    final titleCased = toTitleCase(textOnly);

    if (emojiPrefix.isNotEmpty) {
      return '$emojiPrefix $titleCased'.trim();
    }

    return autoPrependEmoji(titleCased, step: step, archetype: archetype);
  }
}

