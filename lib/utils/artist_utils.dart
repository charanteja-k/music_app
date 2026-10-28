/// Utility for intelligent artist name capitalization and UI presentation.
class ArtistUtils {
  ArtistUtils._();

  /// Known acronyms and casing overrides in Indian and global music.
  static const Map<String, String> _knownOverrides = {
    'mc': 'MC',
    'dj': 'DJ',
    'spb': 'SPB',
    'gds': 'GDS',
    'arjn': 'ARJN',
    'bgm': 'BGM',
    'ost': 'OST',
    'kjy': 'KJY',
  };

  /// Formats an artist string for polished UI display:
  /// - Strips YouTube "- Topic" artifacts and unwanted channel noise
  /// - Automatically title-cases all-lowercase names ('vathshan' -> 'Vathshan', 'sai abhyankkar' -> 'Sai Abhyankkar')
  /// - Intelligently preserves and elevates acronyms ('mc sai' -> 'MC Sai', 'gds' -> 'GDS', 'dj snake' -> 'DJ Snake')
  /// - Normalizes initials and dotted abbreviations ('a.r. rahman' -> 'A.R. Rahman')
  static String formatArtistName(String raw) {
    if (raw.trim().isEmpty) return 'Unknown Artist';

    var s = raw.replaceAll(' - Topic', '').replaceAll('- Topic', '').trim();
    if (s.isEmpty) return 'Unknown Artist';

    final isAllLower = s == s.toLowerCase();
    final isAllUpper = s == s.toUpperCase() && s.length > 4;

    // If already natural mixed-case, just fix any lowercase acronyms (like 'mc', 'dj')
    if (!isAllLower && !isAllUpper) {
      return _cleanAndFixKnownAcronyms(s);
    }

    // Capitalize words
    return _capitalizeWords(s);
  }

  static String _cleanAndFixKnownAcronyms(String text) {
    final words = text.split(' ');
    final result = <String>[];
    for (final w in words) {
      final lower = w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_knownOverrides.containsKey(lower)) {
        result.add(
          w.replaceAll(
            RegExp(r'\b' + lower + r'\b', caseSensitive: false),
            _knownOverrides[lower]!,
          ),
        );
      } else {
        result.add(w);
      }
    }
    return result.join(' ');
  }

  static String _capitalizeWords(String text) {
    final words = text.split(' ');
    final result = <String>[];

    for (final w in words) {
      if (w.isEmpty) continue;

      final lowerWord = w.toLowerCase();
      // Check for dotted initials, e.g. "a.r." or "a.r.rahman"
      if (lowerWord.contains('.')) {
        final dotParts = lowerWord.split('.');
        final formattedDot = dotParts
            .map((p) {
              if (p.isEmpty) return '';
              return _capitalizeSingleToken(p);
            })
            .join('.');
        result.add(formattedDot);
        continue;
      }

      result.add(_capitalizeSingleToken(lowerWord));
    }

    return result.join(' ');
  }

  static String _capitalizeSingleToken(String token) {
    if (token.isEmpty) return '';
    final lower = token.toLowerCase();

    // Check explicit overrides (mc -> MC, dj -> DJ, spb -> SPB, gds -> GDS, arjn -> ARJN)
    if (_knownOverrides.containsKey(lower)) {
      return _knownOverrides[lower]!;
    }

    // If <= 3 letters and contains no vowels (e.g. "gds", "spb", "dj", "mc"), treat as acronym
    if (token.length <= 3 && !token.contains(RegExp(r'[aeiou]'))) {
      return token.toUpperCase();
    }

    // Normal capitalization: First letter uppercase, rest lowercase
    return '${token[0].toUpperCase()}${token.substring(1)}';
  }
}
