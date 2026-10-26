import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'api_config.dart';
import 'canonical_song_dedup.dart';
import 'music_service.dart';
import 'preferences_service.dart';

/// Lightweight, keyless client for YouTube Music's InnerTube API (`WEB_REMIX`).
/// Provides studio release songs, clean album art, and Google's 50-track radio mixes.
class YouTubeMusicClient {
  static final YouTubeMusicClient _instance = YouTubeMusicClient._internal();
  factory YouTubeMusicClient() => _instance;
  YouTubeMusicClient._internal();

  static const String _baseUrl = 'https://music.youtube.com/youtubei/v1';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  static Map<String, String> _buildHeaders() {
    final headers = Map<String, String>.from(_headers);
    final token = PreferencesService().visitorDataToken;
    if (token.isNotEmpty) {
      headers['X-Goog-Visitor-Id'] = token;
    }
    return headers;
  }

  static Map<String, dynamic> _buildContext() {
    final ctx = {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240101.01.00',
        'hl': 'en',
        'gl': 'IN',
      },
    };
    final token = PreferencesService().visitorDataToken;
    if (token.isNotEmpty) {
      (ctx['client'] as Map<String, dynamic>)['visitorData'] = token;
    }
    return ctx;
  }

  /// Searches YouTube Music specifically for official studio songs (no video sketches or dialogue)
  Future<List<Video>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    // 1. On Flutter Web: Route through Cloudflare Edge Worker to bypass browser CORS
    if (kIsWeb) {
      try {
        final edgeUri = ApiConfig.ytmSearchUri(query, limit: limit);
        final resp = await http
            .get(edgeUri)
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final List<dynamic> list = json.decode(resp.body);
          final parsed = _parseJsonTracks(list);
          if (parsed.isNotEmpty) {
            debugPrint(
              '[YTM] Found ${parsed.length} clean studio tracks via Edge Worker for: "$query"',
            );
            return parsed;
          }
        }
      } catch (e) {
        debugPrint('[YTM] Edge search proxy failed: $e');
      }

      return [];
    }

    try {
      final uri = Uri.parse('$_baseUrl/search');
      final payload = {
        'context': _buildContext(),
        'query': query.trim(),
        // Song filter parameter to restrict to official studio releases (Song category)
        'params': 'EgWKAQIIAWoKEAkQChADEAQQBQ%3D%3D',
      };

      final response = await http
          .post(uri, headers: _buildHeaders(), body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[YTM] Search returned status: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);

      // Extract and persist Google Visitor ID for ongoing session learning
      final newVisitorToken =
          data['responseContext']?['visitorData'] as String?;
      if (newVisitorToken != null && newVisitorToken.isNotEmpty) {
        unawaited(PreferencesService().setVisitorDataToken(newVisitorToken));
      }

      final List<Video> songs = [];

      // Navigate through InnerTube sections to extract musicResponsiveListItemRenderer items
      final contents =
          data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] ??
          [];

      for (final section in contents) {
        final items =
            (section['musicShelfRenderer']?['contents'] ??
                    section['itemSectionRenderer']?['contents'])
                as List<dynamic>? ??
            [];
        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'];
          if (renderer == null) continue;

          final song = _parseListItemRenderer(renderer);
          if (song != null) {
            songs.add(song);
            if (songs.length >= limit) break;
          }
        }
        if (songs.length >= limit) break;
      }

      debugPrint(
        '[YTM] Found ${songs.length} clean studio tracks for: "$query"',
      );
      return songs;
    } catch (e) {
      debugPrint('[YTM] Search error: $e');
      return [];
    }
  }

  final Map<String, Future<List<Video>>> _inFlightRadio = {};

  /// Fetches Google's 50-track smart radio automix for a given [videoId]
  Future<List<Video>> fetchRadioTracks(String videoId, {int limit = 50}) {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return Future.value([]);
    if (_inFlightRadio.containsKey(cleanId)) {
      return _inFlightRadio[cleanId]!;
    }
    final future = _fetchRadioTracksImpl(cleanId, limit: limit);
    _inFlightRadio[cleanId] = future;
    return future.whenComplete(() => _inFlightRadio.remove(cleanId));
  }

  Future<List<Video>> _fetchRadioTracksImpl(
    String videoId, {
    int limit = 50,
  }) async {
    final visitorToken = PreferencesService().visitorDataToken;

    // 1. On Flutter Web: Route through Cloudflare Edge Worker to bypass browser CORS
    if (kIsWeb) {
      try {
        final proxyUri = ApiConfig.radioUri(
          videoId,
          limit: limit,
          visitorData: visitorToken.isNotEmpty ? visitorToken : null,
        );
        final resp = await http
            .get(proxyUri)
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final List<dynamic> list = json.decode(resp.body);
          if (list.isNotEmpty) {
            final serverTracks = _parseJsonTracks(list, excludeId: videoId);
            if (serverTracks.isNotEmpty) {
              debugPrint(
                '[YTM] Retrieved ${serverTracks.length} clean radio tracks via edge proxy',
              );
              return serverTracks;
            }
          }
        }
      } catch (e) {
        debugPrint('[YTM] Edge radio proxy: $e');
      }

      return [];
    }

    // 2. Direct client-side InnerTube for Mobile & Desktop (Native high performance + dynamic visitor session)
    try {
      final uri = Uri.parse('$_baseUrl/next');
      final payload = {
        'context': _buildContext(),
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'enablePersistentPlaylistPanel': true,
      };

      final response = await http
          .post(uri, headers: _buildHeaders(), body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[YTM] Radio returned status: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);

      // Extract and persist Google Visitor ID for ongoing session learning
      final newVisitorToken =
          data['responseContext']?['visitorData'] as String?;
      if (newVisitorToken != null && newVisitorToken.isNotEmpty) {
        unawaited(PreferencesService().setVisitorDataToken(newVisitorToken));
      }
      final tabs =
          data['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs'] ??
          [];

      if (tabs.isEmpty) return [];

      final upNextItems =
          tabs[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents'] ??
          [];

      final List<Video> radioTracks = [];
      for (final item in upNextItems) {
        final renderer = item['playlistPanelVideoRenderer'];
        if (renderer == null) continue;

        final vid = renderer['videoId'] as String?;
        if (vid == null || vid.isEmpty) continue;

        // Skip current seed song if returned as track 1
        if (vid == videoId && radioTracks.isNotEmpty) continue;

        final titleRuns = renderer['title']?['runs'] as List<dynamic>? ?? [];
        final rawTitle = titleRuns.isNotEmpty
            ? titleRuns[0]['text'] as String? ?? 'Unknown Title'
            : 'Unknown Title';

        final bylineRuns =
            renderer['longBylineText']?['runs'] as List<dynamic>? ?? [];
        final rawAuthor = bylineRuns.isNotEmpty
            ? bylineRuns[0]['text'] as String? ?? 'Unknown Artist'
            : 'Unknown Artist';

        final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
        final author = cleanA.isNotEmpty ? cleanA : rawAuthor;
        final title = CanonicalSongDedup.sanitizeDisplayTitle(
          rawTitle,
          artist: author,
        );

        final lengthText =
            renderer['lengthText']?['runs']?[0]?['text'] as String? ?? '';
        final duration = _parseDuration(lengthText);

        final track = Video(
          VideoId(vid),
          title,
          author,
          ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
          DateTime.now(),
          '',
          null,
          '',
          duration,
          ThumbnailSet(vid),
          null,
          Engagement(0, null, null),
          false,
        );

        if (CanonicalSongDedup.isGenuineSong(track)) {
          radioTracks.add(track);
        }

        if (radioTracks.length >= limit) break;
      }

      debugPrint(
        '[YTM] Extracted ${radioTracks.length} radio automix tracks for seed: $videoId',
      );
      return radioTracks;
    } catch (e) {
      debugPrint('[YTM] Radio fetch error: $e');
      return [];
    }
  }

  /// Fetches Top Songs and Trending Hits ranked by real-time play velocity
  /// directly from YouTube Music explore feeds (browseId: 'FEmusic_charts')
  /// without sending a text search query.
  Future<List<Video>> fetchCharts({String? language, int limit = 25}) async {
    try {
      final uri = Uri.parse('$_baseUrl/browse');
      final payload = {
        'context': _buildContext(),
        'browseId': 'FEmusic_charts',
      };

      final response = await http
          .post(uri, headers: _buildHeaders(), body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint(
          '[YTM] Charts explore returned status: ${response.statusCode}',
        );
        return [];
      }

      final data = json.decode(response.body);
      final tabs =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
              as List<dynamic>? ??
          [];
      if (tabs.isEmpty) return [];

      final sections =
          tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List<dynamic>? ??
          [];

      String? targetPlaylistBrowseId;
      final langLower = language?.toLowerCase().trim() ?? '';

      // Check Section 2 (Languages) if language is specified
      if (langLower.isNotEmpty && sections.length > 2) {
        final langShelf = sections[2]['musicCarouselShelfRenderer'];
        final langItems = langShelf?['contents'] as List<dynamic>? ?? [];
        for (final item in langItems) {
          final renderer = item['musicTwoRowItemRenderer'];
          final title =
              renderer?['title']?['runs']?[0]?['text'] as String? ?? '';
          if (title.toLowerCase().contains(langLower)) {
            targetPlaylistBrowseId =
                renderer?['navigationEndpoint']?['browseEndpoint']?['browseId']
                    as String?;
            if (targetPlaylistBrowseId != null) break;
          }
        }
      }

      // Fallback to Section 1 (Video charts: Trending 20 India or Top 100)
      if (targetPlaylistBrowseId == null && sections.length > 1) {
        final videoShelf = sections[1]['musicCarouselShelfRenderer'];
        final videoItems = videoShelf?['contents'] as List<dynamic>? ?? [];
        if (videoItems.isNotEmpty) {
          final renderer = videoItems[0]['musicTwoRowItemRenderer'];
          targetPlaylistBrowseId =
              renderer?['navigationEndpoint']?['browseEndpoint']?['browseId']
                  as String?;
        }
      }

      // Default to India Trending 20 if still null
      targetPlaylistBrowseId ??= 'VLOLAK5uy_lSTp1DIuzZBUyee3kDsXwPgP25WdfwB40';

      return await _fetchPlaylistBrowseTracks(
        targetPlaylistBrowseId,
        limit: limit,
      );
    } catch (e) {
      debugPrint('[YTM] Charts fetch error: $e');
      return [];
    }
  }

  /// Helper to fetch tracks from a YouTube Music playlist browse endpoint
  Future<List<Video>> _fetchPlaylistBrowseTracks(
    String playlistBrowseId, {
    int limit = 25,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/browse');
      final payload = {
        'context': _buildContext(),
        'browseId': playlistBrowseId,
      };

      final response = await http
          .post(uri, headers: _buildHeaders(), body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint(
          '[YTM] Playlist browse returned status: ${response.statusCode}',
        );
        return [];
      }

      final data = json.decode(response.body);
      final secContents =
          data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']
              as List<dynamic>? ??
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List<dynamic>? ??
          [];

      final List<Video> songs = [];
      for (final sec in secContents) {
        final shelfItems =
            (sec['musicPlaylistShelfRenderer']?['contents'] ??
                    sec['musicShelfRenderer']?['contents'])
                as List<dynamic>? ??
            [];

        for (final item in shelfItems) {
          final renderer = item['musicResponsiveListItemRenderer'];
          if (renderer == null) continue;

          final song = _parseListItemRenderer(renderer);
          if (song != null) {
            songs.add(song);
            if (songs.length >= limit) break;
          }
        }
        if (songs.length >= limit) break;
      }

      debugPrint(
        '[YTM] Extracted ${songs.length} real-time chart songs from $playlistBrowseId',
      );
      return songs;
    } catch (e) {
      debugPrint('[YTM] Playlist browse track fetch error: $e');
      return [];
    }
  }

  Video? _parseListItemRenderer(Map<String, dynamic> renderer) {
    try {
      final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? [];
      if (flexColumns.isEmpty) return null;

      // 1. Title
      final titleColumn =
          flexColumns[0]['musicResponsiveListItemFlexColumnRenderer'];
      final titleRuns = titleColumn?['text']?['runs'] as List<dynamic>? ?? [];
      if (titleRuns.isEmpty) return null;
      final rawTitle = titleRuns[0]['text'] as String? ?? 'Unknown Title';

      // 2. VideoId & Navigation
      String? videoId;
      final playNav =
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
      videoId = playNav?['watchEndpoint']?['videoId'] as String?;

      if (videoId == null) {
        final titleNav = titleRuns[0]['navigationEndpoint'];
        videoId = titleNav?['watchEndpoint']?['videoId'] as String?;
      }

      videoId ??= renderer['playlistItemData']?['videoId'] as String?;
      videoId ??=
          renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      if (videoId == null || videoId.isEmpty) return null;

      // 3. Artist & Duration
      String rawAuthor = 'Unknown Artist';
      Duration? duration;

      if (flexColumns.length > 1) {
        final subColumn =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer'];
        final subRuns = subColumn?['text']?['runs'] as List<dynamic>? ?? [];
        if (subRuns.isNotEmpty) {
          rawAuthor = subRuns[0]['text'] as String? ?? 'Unknown Artist';
        }

        // Duration is often the last text run
        if (subRuns.length > 2) {
          final lastText = subRuns.last['text'] as String? ?? '';
          duration = _parseDuration(lastText);
        }
      }

      final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
      final author = cleanA.isNotEmpty ? cleanA : rawAuthor;
      final title = CanonicalSongDedup.sanitizeDisplayTitle(
        rawTitle,
        artist: author,
      );

      // Square high-resolution studio album artwork from InnerTube
      final thumbRenderer =
          renderer['thumbnail']?['musicThumbnailRenderer'] ??
          renderer['thumbnailRenderer']?['musicThumbnailRenderer'];
      final thumbs =
          thumbRenderer?['thumbnail']?['thumbnails'] as List<dynamic>?;
      if (thumbs != null && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] != null) {
          var u = last['url'].toString();
          if (u.contains('=w') && u.contains('-h')) {
            u = u.replaceAll(RegExp(r'=w\d+-h\d+.*'), '=w544-h544-l90-rj');
          }
          MusicService.registerArtwork(videoId, u);
        }
      }

      return Video(
        VideoId(videoId),
        title,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        duration,
        ThumbnailSet(videoId),
        null,
        Engagement(0, null, null),
        false,
      );
    } catch (_) {
      return null;
    }
  }

  Duration? _parseDuration(String text) {
    if (text.isEmpty) return null;
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return null;
  }

  List<Video> _parseJsonTracks(List<dynamic> list, {String? excludeId}) {
    final List<Video> result = [];
    for (final item in list) {
      if (item is! Map) continue;
      final vid = item['id'] as String?;
      if (vid == null || vid.isEmpty || vid == excludeId) continue;
      final rawTitle = item['title'] as String? ?? 'Unknown Title';
      final rawAuthor = item['author'] as String? ?? 'Unknown Artist';
      final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
      final author = cleanA.isNotEmpty ? cleanA : rawAuthor;
      final t = CanonicalSongDedup.sanitizeDisplayTitle(
        rawTitle,
        artist: author,
      );
      final durSec = item['duration'] != null
          ? int.tryParse(item['duration'].toString())
          : null;
      final thumb = (item['thumbnail'] ?? item['artwork']) as String?;
      if (thumb != null && thumb.isNotEmpty) {
        MusicService.registerArtwork(vid, thumb);
      }
      final track = Video(
        VideoId(vid),
        t,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        durSec != null ? Duration(seconds: durSec) : null,
        ThumbnailSet(vid),
        null,
        Engagement(0, null, null),
        false,
      );
      if (CanonicalSongDedup.isGenuineSong(track)) {
        result.add(track);
      }
    }
    return result;
  }
}
