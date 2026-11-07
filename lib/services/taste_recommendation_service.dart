import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/jio_album.dart';
import 'canonical_song_dedup.dart';
import 'music_service.dart';
import 'playlist_artist_filter.dart';
import 'preferences_service.dart';
import 'studio_search_service.dart';
import 'trending_catalog_service.dart';
import '../utils/artist_utils.dart';

/// Intelligent recommendation engine that personalizes the Home Screen
/// around the user's most listened artists and listening taste.
///
/// Features:
/// 1. Dynamic telemetry aggregation across plays, skips, history, likes, and playlists.
/// 2. Fetches popular songs and authentic albums for the user's top listened artists.
/// 3. Instant local caching with background revalidation to guarantee steady presence
///    and adaptive updates as music tastes evolve over time.
class TasteRecommendationService {
  static final TasteRecommendationService _instance =
      TasteRecommendationService._internal();
  factory TasteRecommendationService() => _instance;
  TasteRecommendationService._internal();

  /// In-memory cache for fast, instant UI retrieval
  List<Video> _cachedSongs = [];
  List<JioAlbum> _cachedAlbums = [];
  List<String> _cachedTopArtists = [];
  DateTime? _lastFetchTime;
  String _lastArtistFingerprint = '';

  /// Minimum duration between background network revalidations (25 minutes)
  static const Duration cacheStaleDuration = Duration(minutes: 25);

  /// Synchronously returns cached songs if available
  List<Video> get cachedSongs => List.unmodifiable(_cachedSongs);

  /// Synchronously returns cached albums if available
  List<JioAlbum> get cachedAlbums => List.unmodifiable(_cachedAlbums);

  /// Synchronously returns cached top artists
  List<String> get cachedTopArtists => List.unmodifiable(_cachedTopArtists);

  /// Checks whether user's top artists have shifted compared to [currentList]
  bool hasTopArtistsChanged(List<String> currentList) {
    final fresh = getMostListenedArtists(limit: currentList.length.clamp(1, 5));
    if (fresh.length != currentList.length) return true;
    for (var i = 0; i < fresh.length; i++) {
      if (fresh[i].toLowerCase() != currentList[i].toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  /// Returns user's most listened artists, ranked by multi-signal playback telemetry:
  /// - Real playback completion counts (_realPlaybackCounts)
  /// - Play count affinities (_artistPlayCounts)
  /// - Most played songs frequency (mostPlayedSongs)
  /// - Recent listening history recency (listeningHistory)
  /// - Liked songs explicit affinity (likedSongs)
  /// - Custom playlist collections (customPlaylists)
  /// - Currently playing active session (currentSong)
  List<String> getMostListenedArtists({int limit = 5}) {
    final prefs = PreferencesService();
    final musicService = MusicService();

    final Map<String, double> scores = {};

    const blacklistedTokens = [
      'aditya',
      't-series',
      'tseries',
      'sony music',
      'zee music',
      'speed records',
      'speed audio',
      'tips official',
      'saregama',
      'lahari music',
      'yrf',
      'various artists',
      'unknown artist',
      'jukebox',
      'soundtrack',
    ];

    void addScore(String rawName, double points) {
      if (rawName.trim().isEmpty) return;
      final clean = CanonicalSongDedup.cleanArtist(rawName);
      final candidate = clean.isNotEmpty ? clean : rawName.trim();
      final norm = PlaylistArtistFilter.normalize(candidate);
      if (norm.isEmpty || norm.length < 2) return;
      for (final token in blacklistedTokens) {
        if (norm.contains(token)) return;
      }
      final formatted = ArtistUtils.formatArtistName(candidate);
      scores[formatted] = (scores[formatted] ?? 0.0) + points;
    }

    void extractAndScore(String? author, String? title, double multiplier) {
      if (author == null || author.trim().isEmpty) return;
      final extracted = PlaylistArtistFilter.extractArtistsFromSong({
        'author': author,
        'title': title ?? '',
      });
      if (extracted.isNotEmpty) {
        for (final a in extracted) {
          addScore(a, multiplier);
        }
      } else {
        addScore(author, multiplier);
      }
    }

    // 1. Most played artist direct signal (highest single priority)
    if (prefs.mostPlayedArtist.isNotEmpty) {
      addScore(prefs.mostPlayedArtist, 30.0);
    }

    // 2. Real on-device playback counts & affinities
    final topList = prefs.getTopPlayedArtists(limit: 20);
    for (final entry in topList) {
      extractAndScore(entry.key, '', entry.value * 6.0);
    }

    // 3. Most played songs (frequency weighted)
    for (final song in prefs.mostPlayedSongs.take(25)) {
      final author = song['author'] as String? ?? '';
      final title = song['title'] as String? ?? '';
      final count = (song['count'] as num?)?.toDouble() ?? 1.0;
      extractAndScore(author, title, count * 3.5);
    }

    // 4. Listening history (recency weighted: newest plays receive larger weight)
    final history = prefs.listeningHistory;
    for (var i = 0; i < history.length && i < 30; i++) {
      final song = history[i];
      final recencyWeight = (30 - i) * 0.9;
      extractAndScore(song['author'], song['title'], recencyWeight);
    }

    // 5. Liked songs (explicit user affinity)
    for (final song in musicService.likedSongs.take(35)) {
      final author = song['author'] ?? '';
      final title = song['title'] ?? '';
      extractAndScore(author, title, 5.0);
    }

    // 6. Custom playlists (songs organized by user)
    for (final pl in musicService.customPlaylists) {
      final songs = pl['songs'] as List? ?? [];
      for (final song in songs.take(25)) {
        if (song is Map) {
          final author = song['author'] as String? ?? '';
          final title = song['title'] as String? ?? '';
          extractAndScore(author, title, 3.0);
        }
      }
    }

    // 7. Active now-playing track
    final current = musicService.currentSong;
    if (current != null) {
      extractAndScore(current.author, current.title, 8.0);
    }

    // Sort descending by calculated score
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final results = sorted.map((e) => e.key).take(limit).toList();

    // Fallback to top artists from general preferences if no playback signals exist yet
    if (results.isEmpty) {
      return prefs.getTopArtists(limit: limit);
    }

    return results;
  }

  /// Fetches popular and iconic songs for user's [targetArtists].
  /// Results are interleaved across artists for balanced variety and deduplicated.
  Future<List<Video>> fetchPopularSongsForTopArtists({
    List<String>? targetArtists,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    final artists = targetArtists ?? getMostListenedArtists(limit: 3);
    if (artists.isEmpty) return [];

    final fingerprint = artists.join('|');
    if (!forceRefresh &&
        _cachedSongs.isNotEmpty &&
        _lastArtistFingerprint == fingerprint &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheStaleDuration) {
      return _cachedSongs;
    }

    final List<List<Video>> artistBatches = [];
    final musicService = MusicService();

    for (final artist in artists.take(3)) {
      try {
        var songs = await musicService
            .fetchArtistDiscography(artist, page: 1)
            .timeout(const Duration(seconds: 8), onTimeout: () => <Video>[]);

        if (songs.isEmpty) {
          songs = await StudioSearchService()
              .searchSongs('$artist Top Hits', limit: 15)
              .timeout(const Duration(seconds: 8), onTimeout: () => <Video>[]);
        }

        if (songs.isNotEmpty) {
          artistBatches.add(songs);
        }
      } catch (e) {
        debugPrint(
          '[TasteRecommendation] Error fetching songs for $artist: $e',
        );
      }
    }

    // Interleave songs in round-robin fashion so the mix is diverse
    final List<Video> interleaved = [];
    int maxLen = 0;
    for (final b in artistBatches) {
      if (b.length > maxLen) maxLen = b.length;
    }

    for (var i = 0; i < maxLen; i++) {
      for (final batch in artistBatches) {
        if (i < batch.length) {
          interleaved.add(batch[i]);
        }
      }
      if (interleaved.length >= limit * 2) {
        break;
      }
    }

    final deduplicated = CanonicalSongDedup.deduplicateList(interleaved)
        .where((s) => !TrendingCatalogService.isSpamOrJunk(s.title))
        .take(limit)
        .toList();

    if (deduplicated.isNotEmpty) {
      _cachedSongs = deduplicated;
      _cachedTopArtists = List.from(artists);
      _lastArtistFingerprint = fingerprint;
      _lastFetchTime = DateTime.now();
      musicService.enrichArtworkForSongs(deduplicated);
    }

    return deduplicated;
  }

  /// Fetches popular soundtracks and studio albums for [targetArtists].
  /// Drops spam, deduplicates albums, and supplements with authentic trending albums if needed.
  Future<List<JioAlbum>> fetchPopularAlbumsForTopArtists({
    List<String>? targetArtists,
    int limit = 15,
    bool forceRefresh = false,
  }) async {
    final artists = targetArtists ?? getMostListenedArtists(limit: 4);
    if (artists.isEmpty) return [];

    final List<JioAlbum> combined = [];
    final Set<String> seenIds = {};
    final Set<String> seenTitles = {};
    final musicService = MusicService();

    for (final artist in artists.take(4)) {
      try {
        final albums = await musicService
            .searchAlbums(artist, limit: 6)
            .timeout(const Duration(seconds: 8), onTimeout: () => <JioAlbum>[]);

        for (final a in albums) {
          final normTitle = a.title.toLowerCase().trim();
          if (seenIds.contains(a.id) || seenTitles.contains(normTitle)) {
            continue;
          }
          if (TrendingCatalogService.isSpamOrJunk(a.title)) {
            continue;
          }
          seenIds.add(a.id);
          seenTitles.add(normTitle);
          combined.add(a);
        }
      } catch (e) {
        debugPrint(
          '[TasteRecommendation] Error fetching albums for $artist: $e',
        );
      }
    }

    // If fewer than requested limit, supplement with authentic top albums from catalog
    if (combined.length < limit) {
      try {
        final catalogAlbums = await TrendingCatalogService()
            .fetchTopAlbums(limit: limit)
            .timeout(const Duration(seconds: 6), onTimeout: () => <JioAlbum>[]);

        for (final a in catalogAlbums) {
          final normTitle = a.title.toLowerCase().trim();
          if (seenIds.contains(a.id) || seenTitles.contains(normTitle)) {
            continue;
          }
          seenIds.add(a.id);
          seenTitles.add(normTitle);
          combined.add(a);
          if (combined.length >= limit) {
            break;
          }
        }
      } catch (_) {}
    }

    if (combined.isNotEmpty) {
      _cachedAlbums = combined;
    }

    return combined;
  }

  /// Dynamic human-readable subtitle for Recommended Songs shelf
  String getRecommendedSongsSubtitle(List<String> topArtists) {
    if (topArtists.isEmpty) {
      return 'Popular hits and trending tracks curated for your taste';
    }
    if (topArtists.length == 1) {
      return 'Popular hits from ${topArtists.first} and similar artists';
    }
    if (topArtists.length == 2) {
      return 'Popular tracks from ${topArtists[0]} & ${topArtists[1]}';
    }
    return 'Popular tracks based on ${topArtists[0]}, ${topArtists[1]} & ${topArtists[2]}';
  }

  /// Dynamic human-readable subtitle for Popular Albums shelf
  String getRecommendedAlbumsSubtitle(List<String> topArtists) {
    if (topArtists.isEmpty) {
      return 'Soundtracks and studio albums curated for your taste';
    }
    if (topArtists.length == 1) {
      return 'Popular albums and soundtracks from ${topArtists.first}';
    }
    return 'Popular albums from ${topArtists.take(2).join(' & ')}';
  }

  /// Serializes video recommendations for persistent SharedPreferences storage
  static String serializeVideos(List<Video> videos) {
    final list = videos
        .map(
          (v) => {
            'id': v.id.value,
            'title': v.title,
            'author': v.author,
            'durationMs': v.duration?.inMilliseconds ?? 0,
            'streamUrl': MusicService.getCachedWebStreamUrl(v.id.value) ?? '',
            'thumbnail': MusicService.getHdThumbnail(v.id.value),
          },
        )
        .toList();
    return json.encode(list);
  }

  /// Deserializes cached videos from SharedPreferences
  static List<Video> deserializeVideos(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = json.decode(jsonStr);
      return list.map((m) {
        final id = m['id'] as String;
        final streamUrl = m['streamUrl'] as String?;
        if (streamUrl != null && streamUrl.isNotEmpty) {
          MusicService.cacheWebStreamUrl(id, streamUrl);
        }
        final thumb = (m['thumbnail'] as String?) ?? '';
        if (thumb.isNotEmpty) {
          MusicService.registerArtwork(id, thumb);
        }
        final rawDuration = m['durationMs'] as int? ?? 0;
        final duration = rawDuration > 0
            ? Duration(milliseconds: rawDuration)
            : null;

        return Video(
          VideoId(
            id.length == 11 ? id : (id.padRight(11, '0').substring(0, 11)),
          ),
          m['title'] as String? ?? 'Unknown Title',
          m['author'] as String? ?? 'Unknown Artist',
          ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
          DateTime.now(),
          '',
          null,
          '',
          duration,
          ThumbnailSet(id),
          null,
          Engagement(0, null, null),
          false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Serializes albums for persistent SharedPreferences storage
  static String serializeAlbums(List<JioAlbum> albums) {
    return json.encode(albums.map((a) => a.toJson()).toList());
  }

  /// Deserializes albums from SharedPreferences
  static List<JioAlbum> deserializeAlbums(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = json.decode(jsonStr) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(JioAlbum.fromJson)
          .where((a) => a.id.isNotEmpty && a.title.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Clears in-memory caches (e.g. on user reset / logout)
  void clearMemoryCache() {
    _cachedSongs.clear();
    _cachedAlbums.clear();
    _cachedTopArtists.clear();
    _lastFetchTime = null;
    _lastArtistFingerprint = '';
  }
}
