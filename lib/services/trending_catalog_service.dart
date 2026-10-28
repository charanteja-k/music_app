import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/jio_album.dart';
import 'api_config.dart';
import 'canonical_song_dedup.dart';
import 'music_service.dart';
import 'preferences_service.dart';
import 'youtube_music_client.dart';
import '../utils/artist_utils.dart';

/// Catalog discovery and trending ranking engine.
/// Replaces naive keyword text searches with authentic chart velocity modules
/// and enforces strict client-side spam/compilation filtering.
class TrendingCatalogService {
  static final TrendingCatalogService _instance =
      TrendingCatalogService._internal();
  factory TrendingCatalogService() => _instance;
  TrendingCatalogService._internal();

  /// Negative regex filter to drop SEO marketing spam, 1-min reel cuts,
  /// sped-up/slowed tracks, and obsolete retro compilation dumps.
  static final RegExp spamAndJunkFilter = RegExp(
    r'(\b(trending(\s+version)?|1\s*min(\s*mix)?|reels?(\s*version)?|viral(\s*version)?|(speed|sped)(\s*up)?|slowed(\s*\+\s*reverb)?|classic.*soundtrack|vol(ume)?\.?\s*\d+|greatest\s+hits|best\s+of|party\s+mix|jukebox|compilation|golden\s+era|archive)\b)',
    caseSensitive: false,
  );

  /// Evaluates whether text matches the SEO spam or compilation junk regex.
  static bool isSpamOrJunk(String text) {
    if (text.trim().isEmpty) return false;
    return spamAndJunkFilter.hasMatch(text);
  }

  /// Validates whether an album is a modern genuine movie soundtrack or studio release.
  /// Drops spam cuts, compilation dumps, and legacy albums before 2018 (unless [allowArchive] is true).
  static bool isGenuineModernAlbum(
    JioAlbum album, {
    bool allowArchive = false,
  }) {
    if (isSpamOrJunk(album.title)) return false;
    if (isSpamOrJunk(album.artist)) return false;
    if (!allowArchive && album.year.isNotEmpty) {
      final y = int.tryParse(album.year);
      if (y != null && y < 2018) return false;
    }
    return true;
  }

  /// In-memory cache for trending songs keyed by language.
  final Map<String, List<Video>> _trendingCache = {};

  /// In-memory cache for top albums keyed by language.
  final Map<String, List<JioAlbum>> _albumCache = {};

  /// Returns cached albums synchronously if available.
  List<JioAlbum>? getCachedAlbums(String language) {
    final key = language.toLowerCase().trim();
    return _albumCache[key];
  }

  /// Returns cached trending songs synchronously if available.
  List<Video>? getCachedTrending(String language) {
    final key = language.toLowerCase().trim();
    return _trendingCache[key];
  }

  /// Clears in-memory catalog caches.
  void clearCache() {
    _trendingCache.clear();
    _albumCache.clear();
  }

  /// Sets cached albums for testing or manual cache seeding.
  @visibleForTesting
  void setCachedAlbums(String language, List<JioAlbum> albums) {
    _albumCache[language.toLowerCase().trim()] = albums;
  }

  /// Fetches authentic trending songs for [language] from Cloudflare Edge / JioSaavn
  /// native trending modules and YouTube Music InnerTube charts.
  Future<List<Video>> fetchTrendingSongs({
    String? language,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    final lang =
        (language ??
                PreferencesService().preferredLanguages.firstOrNull ??
                'Hindi')
            .toLowerCase()
            .trim();

    if (!forceRefresh &&
        _trendingCache.containsKey(lang) &&
        _trendingCache[lang]!.isNotEmpty) {
      return _trendingCache[lang]!;
    }

    final List<Video> combined = [];
    final seenIds = <String>{};

    // 1. Fetch from JioSaavn native trending via Cloudflare Edge Worker
    try {
      final workerUrl = ApiConfig.cloudflareWorkerUrl;
      final uri = Uri.parse(
        '$workerUrl/jio/trending?lang=${Uri.encodeComponent(lang)}&limit=$limit',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final List<dynamic> list = json.decode(resp.body);
        for (final item in list) {
          if (item is! Map) continue;
          final vid = item['id']?.toString() ?? '';
          if (vid.isEmpty || seenIds.contains(vid)) continue;

          final rawTitle = item['title']?.toString() ?? 'Unknown Title';
          final rawAuthor = item['author']?.toString() ?? 'Unknown Artist';
          final durationSec =
              int.tryParse(item['duration']?.toString() ?? '0') ?? 0;
          final artwork = item['thumbnail']?.toString() ?? '';

          if (isSpamOrJunk(rawTitle) || isSpamOrJunk(rawAuthor)) continue;

          final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
          final author = cleanA.isNotEmpty
              ? ArtistUtils.formatArtistName(rawAuthor)
              : rawAuthor;
          final title = CanonicalSongDedup.sanitizeDisplayTitle(
            rawTitle,
            artist: author,
          );

          if (artwork.isNotEmpty) {
            MusicService.registerArtwork(vid, artwork);
          }

          final video = Video(
            VideoId(vid.length == 11 ? vid : 'jio_$vid'),
            title,
            author,
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            durationSec > 0 ? Duration(seconds: durationSec) : null,
            ThumbnailSet(vid),
            null,
            Engagement(0, null, null),
            false,
          );

          seenIds.add(vid);
          combined.add(video);
        }
      }
    } catch (e) {
      debugPrint('[TrendingCatalog] Edge trending fetch: $e');
    }

    // 2. Fetch from YouTube Music InnerTube Charts ('FEmusic_charts')
    if (combined.length < limit) {
      try {
        final ytmTracks = await YouTubeMusicClient()
            .fetchCharts(language: lang, limit: limit)
            .timeout(const Duration(seconds: 8), onTimeout: () => <Video>[]);

        for (final track in ytmTracks) {
          final id = track.id.value;
          if (seenIds.contains(id)) continue;
          if (isSpamOrJunk(track.title) || isSpamOrJunk(track.author)) continue;
          seenIds.add(id);
          combined.add(track);
        }
      } catch (e) {
        debugPrint('[TrendingCatalog] YTM charts fetch: $e');
      }
    }

    // Deduplicate and filter canonical songs asynchronously
    final deduplicated = CanonicalSongDedup.deduplicateList(combined);
    final cleanTracks = deduplicated
        .where((t) => !isSpamOrJunk(t.title) && !isSpamOrJunk(t.author))
        .take(limit)
        .toList();

    if (cleanTracks.isNotEmpty) {
      _trendingCache[lang] = cleanTracks;
      MusicService().enrichArtworkForSongs(cleanTracks);
    }

    return cleanTracks;
  }

  /// Fetches authentic Top & Featured modern film albums for [language].
  Future<List<JioAlbum>> fetchTopAlbums({
    String? language,
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    final lang =
        (language ??
                PreferencesService().preferredLanguages.firstOrNull ??
                'Hindi')
            .toLowerCase()
            .trim();

    if (!forceRefresh &&
        _albumCache.containsKey(lang) &&
        _albumCache[lang]!.isNotEmpty) {
      return _albumCache[lang]!;
    }

    final List<JioAlbum> albums = [];
    final seenIds = <String>{};

    // 1. Fetch from Cloudflare Edge Worker /jio/featured_albums
    try {
      final workerUrl = ApiConfig.cloudflareWorkerUrl;
      final uri = Uri.parse(
        '$workerUrl/jio/featured_albums?lang=${Uri.encodeComponent(lang)}&limit=$limit',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final List<dynamic> list = json.decode(resp.body);
        for (final item in list) {
          if (item is! Map) continue;
          final album = JioAlbum.fromJson(Map<String, dynamic>.from(item));
          if (seenIds.contains(album.id)) continue;
          if (!isGenuineModernAlbum(album)) continue;
          seenIds.add(album.id);
          albums.add(album);
        }
      }
    } catch (e) {
      debugPrint('[TrendingCatalog] Edge featured albums fetch: $e');
    }

    // 2. Direct fallback to JioSaavn content.getBrowseModules
    if (albums.isEmpty) {
      try {
        final directUri = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=content.getBrowseModules&api_version=4&_format=json&ctx=web6dot0',
        );
        final resp = await http
            .get(
              directUri,
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
                'Cookie': 'L=$lang; DL=$lang; country=IN',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          var body = resp.body.trim();
          if (body.startsWith('\uFEFF')) body = body.substring(1);
          final data = json.decode(body);
          final candidates = [
            if (data['new_albums'] is List) ...data['new_albums'],
            if (data['new_trending'] is List) ...data['new_trending'],
          ];

          for (final item in candidates) {
            if (item is! Map || item['type'] != 'album') continue;
            final album = JioAlbum.fromJson(Map<String, dynamic>.from(item));
            if (seenIds.contains(album.id)) continue;
            if (!isGenuineModernAlbum(album)) continue;
            seenIds.add(album.id);
            albums.add(album);
          }
        }
      } catch (e) {
        debugPrint('[TrendingCatalog] Direct albums fetch: $e');
      }
    }

    if (albums.isNotEmpty) {
      _albumCache[lang] = albums;
    }

    return albums;
  }

  /// Formats album card subtitle cleanly as: Primary Artist / Composer • Release Year
  static String formatAlbumSubtitle(JioAlbum album) {
    var artist = album.artist.trim();
    if (artist.isEmpty || artist.toLowerCase() == 'unknown artist') {
      artist = 'Soundtrack';
    } else {
      // Clean comma/ampersand separation to pick primary composer/artist
      final parts = artist.split(RegExp(r'[,;&]'));
      if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        artist = parts.first.trim();
      }
    }

    final year = album.year.trim();
    if (year.isNotEmpty && year != '0') {
      final yMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(year);
      final y = yMatch?.group(1) ?? year;
      return '$artist • $y';
    }

    return artist;
  }
}
