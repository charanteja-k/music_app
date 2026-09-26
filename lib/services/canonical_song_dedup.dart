import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Industrial-grade Canonical Song Normalizer & Deduplicator.
///
/// Handles noisy YouTube titles with movie names, actors, skits, and 4K tags,
/// matching them accurately against clean JioSaavn and YouTube Music studio tracks.
class CanonicalSongDedup {
  CanonicalSongDedup._();

  // Noise regex for titles
  static final RegExp _bracketNoise = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static final RegExp _featNoise = RegExp(r'\b(feat\.?|ft\.?)\b.*$', caseSensitive: false);
  static final RegExp _videoNoiseWords = RegExp(
    r'\b(official\s+video|official\s+music\s+video|official\s+lyric\s+video|lyric\s+video|'
    r'full\s+video\s+song|video\s+song|full\s+song|full\s+audio|audio\s+song|lyrics|'
    r'lyrical|4k\s+video|hd\s+video|4k|8k|hd|1080p|remix|mashup|status\s+video|status|'
    r'ringtone|dialogue|extended\s+version|original\s+soundtrack|ost)\b',
    caseSensitive: false,
  );

  // Non-music video noise patterns (speeches, interviews, launch events, cricket, sketches)
  static final RegExp _nonMusicTitleNoise = RegExp(
    r'\b(speech|speech\s*@|press\s+meet|success\s+meet|launch\s+event|song\s+launch|audio\s+launch|'
    r'pre\s+release|trailer|teaser|glimpse|promo|first\s+look|motion\s+poster|title\s+reveal|'
    r'interview|talk\s+show|podcast|episode|review|reaction|behind\s+the\s+scenes|making\s+of|bts|'
    r'dances?\s+to|dance\s+performance|dance\s+cover|dance\s+video|stage\s+performance|'
    r'status\s+video|whatsapp\s+status|cricket|ipl|match\s+highlights|trophy|shreyas\s+iyer|'
    r'full\s+movie|movie\s+scene|comedy\s+scene|action\s+scene|climax\s+scene|scenes|'
    r'ringtone|bgm\s+only|shorts|#shorts)\b',
    caseSensitive: false,
  );

  static final RegExp _nonMusicAuthorNoise = RegExp(
    r'\b(media|news|tv|filmnagar|events|buzz|sports|daily|cinema\s+news|vlogs?|cricket)\b',
    caseSensitive: false,
  );

  static final RegExp _punctuation = RegExp(r'[^a-zA-Z0-9\s]');
  static final RegExp _whitespace = RegExp(r'\s+');

  // Record label, media company and noise words in artist names
  static const Set<String> _labelNoise = {
    't-series', 'tseries', 'aditya music', 'sony music', 'zee music',
    'lahari music', 'speed audio', 'tips official', 'tips', 'saregama',
    'yrf', 'think music', 'vevo', 'records', 'entertainment', 'music',
    'official', 'channel', 'audio', 'soundtracks', 'company',
    'shreyas media', 'shreyas', 'nik studios', 'abhishek pictures',
    'gr lyrics', 'lyrics', 'lyrical', 'filmnagar', 'media', 'news', 'tv'
  };

  /// Common stopwords ignored during token set comparison
  static const Set<String> _stopwords = {
    'the', 'a', 'an', 'and', 'from', 'in', 'on', 'at', 'to', 'for', 'of',
    'with', 'by', 'song', 'track', 'movie', 'album'
  };

  /// Normalizes a song title to its canonical core name
  static String cleanTitle(String raw) {
    if (raw.trim().isEmpty) return '';

    // 1. Remove feat. / ft. suffixes
    var s = raw.replaceAll(_featNoise, ' ');

    // 2. Remove bracketed text: (Official Video), [4K HDR], (From "Movie")
    s = s.replaceAll(_bracketNoise, ' ');

    // 3. Take primary section before common delimiters: | : – — / or " - "
    final parts = s.split(RegExp(r'\s*[|:–—/]\s*|\s+-\s+'));
    if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
      s = parts.first;
    }

    // 4. Remove common video noise words
    s = s.replaceAll(_videoNoiseWords, ' ');

    // 5. Remove punctuation and collapse spaces
    s = s.replaceAll(_punctuation, ' ').replaceAll(_whitespace, ' ').trim();

    return s.toLowerCase();
  }

  /// Normalizes artist name, stripping YouTube "- Topic" and record labels/media channels
  static String cleanArtist(String raw) {
    if (raw.trim().isEmpty) return '';

    var s = raw.replaceAll(' - Topic', '').replaceAll('- Topic', '').trim();
    final lower = s.toLowerCase();

    // Check if artist is just a record label, media house, or channel
    for (final label in _labelNoise) {
      if (lower == label ||
          (lower.contains(label) && lower.length < label.length + 8) ||
          lower.startsWith('$label ') ||
          lower.endsWith(' $label')) {
        return '';
      }
    }

    // Reject channels ending with channel suffixes
    if (lower.endsWith(' media') ||
        lower.endsWith(' news') ||
        lower.endsWith(' tv') ||
        lower.endsWith(' lyrics') ||
        lower.endsWith(' studios') ||
        lower.endsWith(' pictures') ||
        lower.endsWith(' events') ||
        lower.endsWith(' channel')) {
      return '';
    }

    // Extract primary artist if comma, ampersand, or semicolon separated
    final primaryParts = s.split(RegExp(r'[,;&]'));
    if (primaryParts.isNotEmpty) {
      s = primaryParts.first;
    }

    s = s.replaceAll(_punctuation, ' ').replaceAll(_whitespace, ' ').trim();
    return s.toLowerCase();
  }

  /// Extracts primary core song title, secondary context keywords (e.g. movie/album name, composer),
  /// and resolved artist from YouTube video metadata.
  static Map<String, dynamic> extractSongContext(String rawTitle, String rawAuthor) {
    final cleanT = cleanTitle(rawTitle);
    String cleanA = cleanArtist(rawAuthor);

    final keywords = <String>[];
    // Split raw title by common delimiters: | : - – — /
    final parts = rawTitle.split(RegExp(r'\s*[|:–—/]\s*|\s+-\s+'));
    for (int i = 1; i < parts.length; i++) {
      var segment = parts[i].trim();
      segment = segment.replaceAll(_bracketNoise, ' ');
      segment = segment.replaceAll(_videoNoiseWords, ' ');
      segment = segment.replaceAll(_punctuation, ' ').replaceAll(_whitespace, ' ').trim();
      if (segment.length > 2 && !segment.toLowerCase().contains('official')) {
        keywords.add(segment);
      }
    }

    // If channel author was empty/record label, check if any keyword looks like a known artist
    if (cleanA.isEmpty && keywords.isNotEmpty) {
      for (final kw in keywords) {
        final kwLower = kw.toLowerCase();
        if (kwLower.contains('anirudh') ||
            kwLower.contains('rahman') ||
            kwLower.contains('pritam') ||
            kwLower.contains('arijit') ||
            kwLower.contains('sriram') ||
            kwLower.contains('dsp') ||
            kwLower.contains('thaman') ||
            kwLower.contains('shreya') ||
            kwLower.contains('badshah') ||
            kwLower.contains('arman') ||
            kwLower.contains('vishal')) {
          cleanA = kw;
          break;
        }
      }
    }

    return {
      'title': cleanT,
      'artist': cleanA,
      'contextKeywords': keywords,
    };
  }

  /// Strict audio validator.
  /// Rejects YouTube videos that are speeches, press meets, trailers, dance performances,
  /// cricket highlights, teasers, or non-song media content.
  static bool isGenuineSong(Video video) {
    final title = video.title;
    final author = video.author;

    // 1. Blacklist non-music keywords in title
    if (_nonMusicTitleNoise.hasMatch(title)) {
      return false;
    }

    // 2. Blacklist non-music channels unless the title explicitly states it's an official song
    if (_nonMusicAuthorNoise.hasMatch(author)) {
      final titleLower = title.toLowerCase();
      final hasSongIndicator = titleLower.contains('full video song') ||
          titleLower.contains('official music video') ||
          titleLower.contains('official song') ||
          titleLower.contains('lyrical video') ||
          titleLower.contains('lyric video');
      if (!hasSongIndicator) {
        return false;
      }
    }

    // 3. Duration boundaries (authentic music tracks are 75s to 660s)
    final duration = video.duration;
    if (duration != null) {
      final sec = duration.inSeconds;
      if (sec > 0 && (sec < 75 || sec > 660)) {
        return false;
      }
    }

    return true;
  }

  static final Map<String, String> _songLanguageCache = {};

  /// Caches the confirmed language for a song (e.g. from JioSaavn or Spotify metadata)
  static void registerSongLanguage(String songId, String language) {
    if (songId.isEmpty || language.isEmpty) return;
    _songLanguageCache[songId] = language.toLowerCase().trim();
  }

  /// Retrieves cached song language
  static String? getSongLanguage(String songId) {
    if (songId.isEmpty) return null;
    return _songLanguageCache[songId];
  }

  static const Map<String, List<int>> _unicodeScripts = {
    'telugu': [0x0C00, 0x0C7F],
    'tamil': [0x0B80, 0x0BFF],
    'hindi': [0x0900, 0x097F],
    'kannada': [0x0C80, 0x0CFF],
    'malayalam': [0x0D00, 0x0D7F],
    'punjabi': [0x0A00, 0x0A7F],
    'bengali': [0x0980, 0x09FF],
    'gujarati': [0x0A80, 0x0AFF],
  };

  /// Detects native Unicode script in text
  static String? detectScript(String text, {int minCount = 4}) {
    if (text.isEmpty) return null;
    final counts = <String, int>{};
    for (final k in _unicodeScripts.keys) {
      counts[k] = 0;
    }
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      for (final entry in _unicodeScripts.entries) {
        if (cp >= entry.value[0] && cp <= entry.value[1]) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
    }
    String? bestLang;
    int maxCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        bestLang = entry.key;
      }
    }
    return maxCount >= minCount ? bestLang : null;
  }

  /// Detects language from title or metadata tags (e.g. Telugu, Hindi, Tamil)
  static String? detectLanguage(String text) {
    if (text.isEmpty) return null;

    // 1. Check native Unicode script first
    final script = detectScript(text, minCount: 3);
    if (script != null) return script;

    final lower = text.toLowerCase();
    if (RegExp(r'\b(telugu)\b').hasMatch(lower)) return 'telugu';
    if (RegExp(r'\b(tamil)\b').hasMatch(lower)) return 'tamil';
    if (RegExp(r'\b(hindi)\b').hasMatch(lower)) return 'hindi';
    if (RegExp(r'\b(punjabi)\b').hasMatch(lower)) return 'punjabi';
    if (RegExp(r'\b(kannada)\b').hasMatch(lower)) return 'kannada';
    if (RegExp(r'\b(malayalam)\b').hasMatch(lower)) return 'malayalam';
    if (RegExp(r'\b(bengali)\b').hasMatch(lower)) return 'bengali';
    if (RegExp(r'\b(marathi)\b').hasMatch(lower)) return 'marathi';
    if (RegExp(r'\b(gujarati)\b').hasMatch(lower)) return 'gujarati';
    if (RegExp(r'\b(bhojpuri)\b').hasMatch(lower)) return 'bhojpuri';
    if (RegExp(r'\b(english)\b').hasMatch(lower)) return 'english';

    // Channel / Record Label language associations
    if (lower.contains('aditya music') || lower.contains('madhura audio')) return 'telugu';
    if (lower.contains('think music')) return 'tamil';

    return null;
  }

  /// Evaluates whether lyrics candidate matches the expected language, artist, duration, and context
  static int scoreLyricsCandidate({
    required String? targetLang,
    required String targetTitle,
    required String targetArtist,
    int? targetDuration,
    required Map<String, dynamic> candidate,
    List<String>? contextKeywords,
  }) {
    final synced = candidate['syncedLyrics'] as String?;
    final plain = candidate['plainLyrics'] as String?;
    final lyrics = (synced?.isNotEmpty == true ? synced! : (plain ?? '')).trim();
    if (lyrics.isEmpty) return -9999;

    // Hard reject instrumental or empty placeholders
    final lowerLyrics = lyrics.toLowerCase();
    if (lowerLyrics.contains('[instrumental]') ||
        lowerLyrics == 'instrumental' ||
        lowerLyrics.contains('lyrics not available') ||
        lowerLyrics.contains('no lyrics available')) {
      return -9999;
    }

    // Strip timestamps for script analysis
    final cleanLyrics = lyrics.replaceAll(RegExp(r'\[\d+:\d+\.?\d*\]'), '').trim();
    if (cleanLyrics.length < 4) return -9999;

    final script = detectScript(cleanLyrics, minCount: 8);

    final trackName = (candidate['trackName'] as String? ?? '').toLowerCase();
    final albumName = (candidate['albumName'] as String? ?? '').toLowerCase();
    final cArtist = candidate['artistName'] as String? ?? '';
    final metaLang = detectLanguage('$albumName $trackName');

    final tLang = targetLang?.toLowerCase().trim();
    int score = 0;

    // 1. Strict script compatibility
    if (tLang != null && tLang.isNotEmpty) {
      if (script != null) {
        if (script != tLang) {
          // Hard reject conflicting script (e.g. Malayalam or Tamil lyrics for Telugu song)
          return -9999;
        } else {
          score += 500;
        }
      } else if (tLang == 'english' && script != null) {
        return -9999;
      }
    }

    // 2. Strict metadata language compatibility
    if (tLang != null && tLang.isNotEmpty && metaLang != null) {
      if (metaLang != tLang) {
        // Hard reject conflicting dubbed album tags
        return -9999;
      } else {
        score += 300;
      }
    }

    // 3. Title match
    final cTitle = cleanTitle(trackName);
    final tTitle = cleanTitle(targetTitle);
    if (cTitle == tTitle) {
      score += 250;
    } else if (cTitle.contains(tTitle) || tTitle.contains(cTitle)) {
      score += 150;
    } else {
      score -= 100;
    }

    // 4. Strict Artist match (penalize confirmed mismatch to prevent false positives)
    if (targetArtist.isNotEmpty && cArtist.isNotEmpty) {
      final tTokens = tokenize(cleanArtist(targetArtist));
      final cTokens = tokenize(cleanArtist(cArtist));
      if (tTokens.intersection(cTokens).isNotEmpty) {
        score += 180;
      } else if (tTokens.isNotEmpty) {
        score -= 350; // Heavy penalty: prevents songs by different artists passing on generic titles
      }
    }

    // 5. Context Keywords (Movie / Album / Secondary Artists from video title)
    if (contextKeywords != null && contextKeywords.isNotEmpty) {
      final candMeta = '$trackName $albumName $cArtist'.toLowerCase();
      for (final kw in contextKeywords) {
        final cleanKw = kw.toLowerCase().trim();
        if (cleanKw.length > 2 && candMeta.contains(cleanKw)) {
          score += 150;
          break;
        }
      }
    }

    // 6. Duration match with strict boundaries
    final cDur = (candidate['duration'] as num?)?.toDouble() ?? 0.0;
    if (targetDuration != null && targetDuration > 0 && cDur > 0) {
      final diff = (cDur - targetDuration).abs();
      final ratio = diff / targetDuration;
      if (diff <= 4) {
        score += 120;
      } else if (diff <= 10) {
        score += 60;
      } else if (diff > 25 || ratio > 0.15) {
        score -= 300; // Large discrepancy
      } else if (diff > 45 || ratio > 0.25) {
        score -= 600; // Completely different song length
      }
    }

    // 7. Synced lyrics preference
    if (synced != null && synced.trim().isNotEmpty) {
      score += 50;
    }

    return score;
  }

  /// Verifies that candidate does not violate the seed track's language affinity
  static bool isLanguageCompatible(String? seedLang, String candidateTitle) {
    if (seedLang == null || seedLang.isEmpty) return true;
    final candLang = detectLanguage(candidateTitle);
    if (candLang == null) return true; // neutral / unlabelled
    return candLang == seedLang;
  }

  /// Extracts meaningful token set from normalized text
  static Set<String> tokenize(String text) {
    return text
        .toLowerCase()
        .split(_whitespace)
        .where((w) => w.length > 1 && !_stopwords.contains(w))
        .toSet();
  }

  /// Calculates Jaccard similarity between two token sets (0.0 to 1.0)
  static double jaccardSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  /// Calculates Levenshtein-based similarity (0.0 to 1.0)
  static double stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final len1 = s1.length;
    final len2 = s2.length;
    final maxLen = max(len1, len2);
    if (maxLen == 0) return 1.0;

    // Fast-path length discrepancy
    if ((len1 - len2).abs() > (maxLen * 0.6)) return 0.0;

    final dist = _levenshteinDistance(s1, s2);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < t.length + 1; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[t.length];
  }

  /// Determines if two song items represent the exact same track.
  static bool areDuplicateSongs({
    required String titleA,
    required String artistA,
    required String titleB,
    required String artistB,
    double threshold = 0.75,
  }) {
    final cleanTA = cleanTitle(titleA);
    final cleanTB = cleanTitle(titleB);

    if (cleanTA.isEmpty || cleanTB.isEmpty) return false;

    // Exact clean title match
    if (cleanTA == cleanTB) {
      final cleanAA = cleanArtist(artistA);
      final cleanAB = cleanArtist(artistB);
      if (cleanAA.isNotEmpty && cleanAB.isNotEmpty) {
        if (cleanAA == cleanAB || cleanAA.contains(cleanAB) || cleanAB.contains(cleanAA)) {
          return true;
        }
        return false;
      }
      return true;
    }

    // Token-set Jaccard overlap
    final tokensA = tokenize(cleanTA);
    final tokensB = tokenize(cleanTB);

    if (tokensA.isNotEmpty && tokensB.isNotEmpty) {
      final jaccard = jaccardSimilarity(tokensA, tokensB);
      if (jaccard >= 0.70) return true;

      // Check if one token set is a complete subset of the other (e.g. "Kesariya" in "Kesariya Dance")
      final intersection = tokensA.intersection(tokensB).length;
      final smallerLen = min(tokensA.length, tokensB.length);
      if (smallerLen > 0 && intersection == smallerLen && smallerLen >= 2) {
        return true;
      }
    }

    // Levenshtein string similarity on clean title
    final titleSim = stringSimilarity(cleanTA, cleanTB);
    if (titleSim >= threshold) return true;

    // Check artist consistency if title similarity is moderately high (>= 0.60)
    if (titleSim >= 0.60) {
      final cleanAA = cleanArtist(artistA);
      final cleanAB = cleanArtist(artistB);
      if (cleanAA.isNotEmpty && cleanAB.isNotEmpty) {
        if (cleanAA == cleanAB || cleanAA.contains(cleanAB) || cleanAB.contains(cleanAA)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Deduplicates [incoming] songs against [primary] existing songs.
  /// If [incoming] is omitted, deduplicates [primary] against itself.
  /// Any song in [incoming] that duplicates a song in [primary] (or earlier in [incoming]) is dropped.
  static List<Video> deduplicateList(List<Video> primary, [List<Video>? incoming]) {
    if (incoming == null) {
      final result = <Video>[];
      for (final song in primary) {
        bool isDup = false;
        for (final existing in result) {
          if (existing.id.value == song.id.value ||
              areDuplicateSongs(
                titleA: existing.title,
                artistA: existing.author,
                titleB: song.title,
                artistB: song.author,
              )) {
            isDup = true;
            break;
          }
        }
        if (!isDup) {
          result.add(song);
        }
      }
      return result;
    }

    final result = <Video>[];
    final allKnown = <Video>[...primary];

    for (final song in incoming) {
      bool isDup = false;
      for (final existing in allKnown) {
        if (existing.id.value == song.id.value ||
            areDuplicateSongs(
              titleA: existing.title,
              artistA: existing.author,
              titleB: song.title,
              artistB: song.author,
            )) {
          isDup = true;
          break;
        }
      }

      if (!isDup) {
        result.add(song);
        allKnown.add(song);
      }
    }

    return result;
  }

  /// Spaces a queue of songs so that no two consecutive songs are by the exact same
  /// artist, while preserving the recommendation ranking order (preventing oddball tracks
  /// from being arbitrarily promoted to the top of the queue).
  static List<Video> balanceArtistDistribution(List<Video> songs) {
    if (songs.length <= 2) return songs;

    final result = <Video>[];
    final remaining = List<Video>.from(songs);

    while (remaining.isNotEmpty) {
      final lastArtist = result.isEmpty ? null : cleanArtist(result.last.author);

      // Select the highest-ranked song in remaining that does not duplicate the last song's artist
      int targetIdx = 0;
      if (lastArtist != null && lastArtist.isNotEmpty) {
        final altIdx = remaining.indexWhere((s) {
          final a = cleanArtist(s.author);
          return a.isEmpty || a != lastArtist;
        });
        if (altIdx != -1) {
          targetIdx = altIdx;
        }
      }

      result.add(remaining.removeAt(targetIdx));
    }

    return result;
  }
}
