import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'api_config.dart';
import 'canonical_song_dedup.dart';

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

  static const Map<String, dynamic> _context = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240101.01.00',
      'hl': 'en',
      'gl': 'IN',
    },
  };

  /// Searches YouTube Music specifically for official studio songs (no video sketches or dialogue)
  Future<List<Video>> searchSongs(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    // 1. On Flutter Web: Route through Cloudflare Edge Worker to bypass browser CORS
    if (kIsWeb) {
      try {
        final edgeUri = ApiConfig.ytmSearchUri(query, limit: limit);
        final resp = await http
            .get(edgeUri)
            .timeout(const Duration(seconds: 5));
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
      final payload = {'context': _context, 'query': query.trim()};

      final response = await http
          .post(uri, headers: _headers, body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[YTM] Search returned status: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);
      final List<Video> songs = [];

      // Navigate through InnerTube sections to extract music items
      final contents =
          data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']
              as List<dynamic>? ??
          [];

      // 1. Check Top Result Card if it is a studio song
      if (contents.isNotEmpty &&
          contents[0]['musicCardShelfRenderer'] != null) {
        final card =
            contents[0]['musicCardShelfRenderer'] as Map<String, dynamic>;
        final cardSong = _parseCardShelfRenderer(card);
        if (cardSong != null) {
          songs.add(cardSong);
        }
      }

      // 2. Scan sections for official studio songs
      for (final section in contents) {
        final items =
            section['itemSectionRenderer']?['contents'] as List<dynamic>? ??
            section['musicShelfRenderer']?['contents'] as List<dynamic>? ??
            [];
        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'];
          if (renderer == null) continue;

          final song = _parseListItemRenderer(renderer);
          if (song != null && !songs.any((s) => s.id.value == song.id.value)) {
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

  Video? _parseCardShelfRenderer(Map<String, dynamic> card) {
    try {
      final vid =
          card['onTap']?['watchEndpoint']?['videoId'] as String? ??
          card['buttons']?[0]?['buttonRenderer']?['command']?['watchEndpoint']?['videoId']
              as String?;
      if (vid == null || vid.length != 11) return null;

      final title = card['title']?['runs']?[0]?['text'] as String? ?? '';
      if (title.isEmpty) return null;

      final subRuns = card['subtitle']?['runs'] as List<dynamic>? ?? [];
      final artistRun = subRuns.firstWhere(
        (r) =>
            r['navigationEndpoint']?['browseEndpoint']?['browseId']
                ?.toString()
                .startsWith('UC') ==
            true,
        orElse: () => null,
      );
      final rawAuthor = artistRun != null
          ? (artistRun['text'] as String? ?? 'Various Artists')
          : (subRuns.length > 2
                ? (subRuns[2]['text'] as String? ?? 'Various Artists')
                : 'Various Artists');

      final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
      final author = cleanA.isNotEmpty ? cleanA : rawAuthor;
      final cleanTitle = CanonicalSongDedup.sanitizeDisplayTitle(
        title,
        artist: author,
      );

      final track = Video(
        VideoId(vid),
        cleanTitle,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        const Duration(seconds: 210),
        ThumbnailSet(vid),
        null,
        Engagement(0, null, null),
        false,
      );

      return CanonicalSongDedup.isGenuineSong(track) ? track : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches Google's 50-track smart radio automix for a given [videoId]
  Future<List<Video>> fetchRadioTracks(String videoId, {int limit = 50}) async {
    if (videoId.trim().isEmpty) return [];

    // 1. First try Cloudflare Edge Worker / Cloud Proxy (guarantees CORS bypass on Web & 0ms cold start)
    try {
      final proxyUri = ApiConfig.radioUri(videoId, limit: limit);
      final resp = await http.get(proxyUri).timeout(const Duration(seconds: 5));
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
      debugPrint('[YTM] Edge radio proxy failed, trying fallback: $e');
    }

    // 2. On Web: if Edge Worker returned empty, try Render backend radio
    if (kIsWeb) {
      try {
        final renderUri = ApiConfig.renderRadioUri(videoId, limit: limit);
        final resp = await http
            .get(renderUri)
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final List<dynamic> list = json.decode(resp.body);
          return _parseJsonTracks(list, excludeId: videoId);
        }
      } catch (_) {}
      return [];
    }

    // 3. Direct client-side InnerTube fallback (Mobile / Desktop)
    try {
      final uri = Uri.parse('$_baseUrl/next');
      final payload = {
        'context': _context,
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
      };

      final response = await http
          .post(uri, headers: _headers, body: json.encode(payload))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[YTM] Radio returned status: ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body);
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

      if (videoId == null) {
        final onT = renderer['onTap'];
        videoId = onT?['watchEndpoint']?['videoId'] as String?;
      }

      if (videoId == null || videoId.isEmpty) return null;

      // 3. Artist & Duration
      String rawAuthor = 'Unknown Artist';
      Duration? duration;

      if (flexColumns.length > 1) {
        final subColumn =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer'];
        final subRuns = subColumn?['text']?['runs'] as List<dynamic>? ?? [];
        if (subRuns.isNotEmpty) {
          final firstText = (subRuns[0]['text'] as String? ?? '').toLowerCase();
          if (firstText == 'song' && subRuns.length > 2) {
            rawAuthor = subRuns[2]['text'] as String? ?? 'Unknown Artist';
          } else {
            final artistRun = subRuns.firstWhere(
              (r) =>
                  r['navigationEndpoint']?['browseEndpoint']?['browseId']
                      ?.toString()
                      .startsWith('UC') ==
                  true,
              orElse: () => subRuns[0],
            );
            rawAuthor = artistRun['text'] as String? ?? 'Unknown Artist';
          }
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

      final track = Video(
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

      return CanonicalSongDedup.isGenuineSong(track) ? track : null;
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
