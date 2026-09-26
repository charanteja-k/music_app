/// High-speed Indic-to-English (Latin) Romanization and Transliteration Engine.
///
/// Converts native regional Indian scripts (Telugu, Hindi/Devanagari, Tamil,
/// Kannada, Malayalam, Bengali, Gujarati, Punjabi) into natural, phonetically
/// readable English pronunciation (e.g. "Tenglish", "Hinglish", "Tanglish").
///
/// Preserves all synchronized LRC timestamps (e.g. `[01:23.45]`) and formatting.
class LyricsTransliterationService {
  LyricsTransliterationService._();

  static const Map<int, String> _vowelOffsets = {
    0x05: 'a',
    0x06: 'aa',
    0x07: 'i',
    0x08: 'ee',
    0x09: 'u',
    0x0A: 'oo',
    0x0B: 'ru',
    0x0E: 'e',
    0x0F: 'e',
    0x10: 'ai',
    0x12: 'o',
    0x13: 'o',
    0x14: 'au',
  };

  static const Map<int, String> _consonantOffsets = {
    0x15: 'k',
    0x16: 'kh',
    0x17: 'g',
    0x18: 'gh',
    0x19: 'ng',
    0x1A: 'ch',
    0x1B: 'chh',
    0x1C: 'j',
    0x1D: 'jh',
    0x1E: 'ny',
    0x1F: 't',
    0x20: 'th',
    0x21: 'd',
    0x22: 'dh',
    0x23: 'n',
    0x24: 't',
    0x25: 'th',
    0x26: 'd',
    0x27: 'dh',
    0x28: 'n',
    0x2A: 'p',
    0x2B: 'ph',
    0x2C: 'b',
    0x2D: 'bh',
    0x2E: 'm',
    0x2F: 'y',
    0x30: 'r',
    0x31: 'r',
    0x32: 'l',
    0x33: 'l',
    0x34: 'zh',
    0x35: 'v',
    0x36: 'sh',
    0x37: 'sh',
    0x38: 's',
    0x39: 'h',
  };

  static const Map<int, String> _matraOffsets = {
    0x3E: 'aa',
    0x3F: 'i',
    0x40: 'ee',
    0x41: 'u',
    0x42: 'oo',
    0x43: 'ru',
    0x46: 'e',
    0x47: 'e',
    0x48: 'ai',
    0x4A: 'o',
    0x4B: 'o',
    0x4C: 'au',
  };

  /// Checks whether text contains non-Latin Indic script characters
  static bool hasIndicScript(String text) {
    if (text.isEmpty) return false;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0900 && code <= 0x0D7F) {
        return true;
      }
    }
    return false;
  }

  /// Transliterates an entire synchronized LRC lyrics string, preserving all timestamp tags
  static String transliterateLrc(String lrcText) {
    if (lrcText.isEmpty) return '';
    final lines = lrcText.split('\n');
    final tagRegex = RegExp(r'^(\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\])(.*)$');

    final result = <String>[];
    for (final line in lines) {
      final match = tagRegex.firstMatch(line);
      if (match != null) {
        final timestamp = match.group(1)!;
        final rawLyric = match.group(2) ?? '';
        final romanized = transliterateText(rawLyric);
        result.add('$timestamp $romanized'.trimRight());
      } else {
        result.add(transliterateText(line));
      }
    }
    return result.join('\n');
  }

  /// Transliterates a single line of text from Indic script into natural English pronunciation
  static String transliterateText(String input) {
    if (input.trim().isEmpty) return input;
    if (!hasIndicScript(input)) return input;

    final sb = StringBuffer();
    final len = input.length;
    int i = 0;

    while (i < len) {
      final cp = input.codeUnitAt(i);

      // Check if code point is in Indic Brahmic Unicode block (0x0900 - 0x0D7F)
      if (cp >= 0x0900 && cp <= 0x0D7F) {
        final scriptBase = (cp ~/ 0x80) * 0x80;
        final offset = cp - scriptBase;

        // 1. Independent Vowel
        if (_vowelOffsets.containsKey(offset)) {
          sb.write(_vowelOffsets[offset]);
          i++;
          continue;
        }

        // 2. Consonant
        if (_consonantOffsets.containsKey(offset)) {
          String consonant = _consonantOffsets[offset]!;
          i++;

          // Look ahead for nukta, virama, matra, anusvara, visarga
          if (i < len) {
            final nextCp = input.codeUnitAt(i);
            if (nextCp >= scriptBase && nextCp <= scriptBase + 0x7F) {
              final nextOffset = nextCp - scriptBase;

              // Nukta (0x3C): e.g. j -> z, ph -> f, k -> q
              if (nextOffset == 0x3C) {
                if (consonant == 'j') consonant = 'z';
                if (consonant == 'ph' || consonant == 'p') consonant = 'f';
                if (consonant == 'k') consonant = 'q';
                i++; // consume nukta
              }
            }
          }

          if (i < len) {
            final nextCp = input.codeUnitAt(i);
            if (nextCp >= scriptBase && nextCp <= scriptBase + 0x7F) {
              final nextOffset = nextCp - scriptBase;

              // Virama / Halant (0x4D): suppresses inherent 'a'
              if (nextOffset == 0x4D) {
                sb.write(consonant);
                i++; // consume virama
                continue;
              }

              // Matra (dependent vowel sign)
              if (_matraOffsets.containsKey(nextOffset)) {
                sb.write(consonant);
                sb.write(_matraOffsets[nextOffset]);
                i++; // consume matra
                continue;
              }

              // Anusvara (0x02) directly after consonant: "am"
              if (nextOffset == 0x02) {
                sb.write('${consonant}am');
                i++; // consume anusvara
                continue;
              }

              // Visarga (0x03) directly after consonant: "aha"
              if (nextOffset == 0x03) {
                sb.write('${consonant}aha');
                i++; // consume visarga
                continue;
              }
            }
          }

          // Inherent 'a' vowel if no virama or matra followed
          // Hindi (0x0900) word-end consonant schwa is usually dropped (e.g. Ishq, Dil, Pyar)
          final isDevanagari = scriptBase == 0x0900;
          final atWordEnd = (i >= len || _isWordBoundary(input.codeUnitAt(i)));

          if (isDevanagari && atWordEnd) {
            sb.write(consonant);
          } else {
            sb.write('${consonant}a');
          }
          continue;
        }

        // 3. Standalone Anusvara (0x02)
        if (offset == 0x02) {
          sb.write('m');
          i++;
          continue;
        }

        // 4. Standalone Visarga (0x03)
        if (offset == 0x03) {
          sb.write('h');
          i++;
          continue;
        }

        // 5. Standalone Matra
        if (_matraOffsets.containsKey(offset)) {
          sb.write(_matraOffsets[offset]);
          i++;
          continue;
        }

        // 6. Virama without consonant
        if (offset == 0x4D) {
          i++;
          continue;
        }

        // 7. Nukta without consonant
        if (offset == 0x3C) {
          i++;
          continue;
        }
      }

      // Non-Indic character (Latin alphabet, punctuation, emoji, numbers, spaces)
      sb.writeCharCode(cp);
      i++;
    }

    return _postProcessRomanization(sb.toString());
  }

  static bool _isWordBoundary(int codePoint) {
    return codePoint == 0x20 || // space
        codePoint == 0x0A || // \n
        codePoint == 0x0D || // \r
        codePoint == 0x2C || // ,
        codePoint == 0x2E || // .
        codePoint == 0x3F || // ?
        codePoint == 0x21 || // !
        codePoint == 0x2D || // -
        codePoint == 0x22 || // "
        codePoint == 0x27 || // '
        codePoint == 0x28 || // (
        codePoint == 0x29; // )
  }

  static String _postProcessRomanization(String text) {
    var s = text;
    s = s.replaceAll('aaa', 'aa');
    s = s.replaceAll('eee', 'ee');
    s = s.replaceAll('ooo', 'oo');
    s = s.replaceAll('aee', 'ae');
    s = s.replaceAll('a़', ''); // clean residual nukta

    // Capitalize words for clean presentation
    final words = s.split(' ');
    final cleanWords = words.map((w) {
      if (w.isEmpty) return w;
      if (w.startsWith('[') && w.contains(']')) return w;
      return w.substring(0, 1).toUpperCase() + w.substring(1);
    });

    return cleanWords.join(' ');
  }
}
