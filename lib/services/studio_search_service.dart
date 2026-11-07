import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'api_config.dart';
import 'canonical_song_dedup.dart';
import 'dynamic_artist_service.dart';
import 'music_service.dart';
import 'youtube_music_client.dart';
import 'trending_catalog_service.dart';

/// Next-Generation Studio Search Service.
///
/// Implements the user-validated canonical search mechanism:
/// 1. Query YouTube Music (`WEB_REMIX`) first to obtain Google's canonical identification
///    of the exact track title and original artist (eliminating remix/cover confusion).
/// 2. Use the canonical `<Title> <Artist>` entity to query JioSaavn directly for
///    authentic, uncompressed 320kbps studio audio.
/// 3. If JioSaavn has no direct match for the canonical query, instantly fallback to
///    raw query search on JioSaavn.
/// 4. Extract remaining genuine variations, live performances, and similar songs from
///    YouTube Music, deduplicate them against the studio pool, and append them below
///    the original tracks.
class StudioSearchService {
  static final StudioSearchService _instance = StudioSearchService._internal();
  factory StudioSearchService() => _instance;
  StudioSearchService._internal();

  /// Primary search entrypoint for user search queries.
  Future<List<Video>> searchSongs(
    String rawQuery, {
    int page = 1,
    int limit = 50,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return [];

    // Transparently handle artist discography if query matches a verified artist
    if (DynamicArtistService().isKnownArtist(query)) {
      final discography = await MusicService().fetchArtistDiscography(
        query,
        page: page,
      );
      if (discography.isNotEmpty) return discography;
    }

    try {
      final int jioLimit = limit.clamp(10, 60);

      // STEP 1: Query YouTube Music (Google Canonical Entity Identification)
      final ytmFuture = YouTubeMusicClient().searchSongs(query, limit: 15);

      // For page > 1, execute direct paginated JioSaavn search
      if (page > 1) {
        final paginatedResp = await http
            .get(
              ApiConfig.jioSearchUri(
                '$query hits',
                limit: jioLimit,
                page: page,
              ),
            )
            .timeout(const Duration(seconds: 8))
            .catchError((_) => http.Response('[]', 500));

        if (paginatedResp.statusCode == 200) {
          final results = _parseJioResults(paginatedResp.body, query: query);
          final cleanPage = results
              .where(
                (v) =>
                    CanonicalSongDedup.isGenuineSong(v) &&
                    !isUnnecessaryOrAmateurResult(v, query),
              )
              .toList();
          return CanonicalSongDedup.deduplicateList(cleanPage);
        }
        return [];
      }

      // STEP 2: Await YTM search results
      final rawYtm = await ytmFuture.catchError((_) => <Video>[]);
      final ytmResults = rawYtm
          .where(
            (v) =>
                CanonicalSongDedup.isGenuineSong(v) &&
                !isUnnecessaryOrAmateurResult(v, query),
          )
          .toList();

      final Video? ytmAnchor = ytmResults.isNotEmpty ? ytmResults.first : null;
      List<Video> jioResults = [];

      // STEP 3: Query JioSaavn with Canonical Anchor if available
      if (ytmAnchor != null) {
        final cleanAnchorT = CanonicalSongDedup.cleanTitle(ytmAnchor.title);
        final cleanAnchorA = CanonicalSongDedup.cleanArtist(ytmAnchor.author);
        final anchorQuery = cleanAnchorA.isNotEmpty
            ? '$cleanAnchorT $cleanAnchorA'
            : cleanAnchorT;

        try {
          final anchorJioResp = await http
              .get(
                ApiConfig.jioSearchUri(anchorQuery, limit: jioLimit, page: 1),
              )
              .timeout(const Duration(seconds: 6))
              .catchError((_) => http.Response('[]', 500));

          if (anchorJioResp.statusCode == 200) {
            final parsedAnchor = _parseJioResults(
              anchorJioResp.body,
              query: query,
            );
            // Verify if JioSaavn returned tracks matching our anchor title
            final hasMatch = parsedAnchor.any((s) {
              final sTitle = CanonicalSongDedup.cleanTitle(s.title);
              return sTitle == cleanAnchorT ||
                  sTitle.contains(cleanAnchorT) ||
                  cleanAnchorT.contains(sTitle) ||
                  CanonicalSongDedup.stringSimilarity(sTitle, cleanAnchorT) >=
                      0.65;
            });

            if (hasMatch && parsedAnchor.isNotEmpty) {
              jioResults = parsedAnchor;
            }
          }
        } catch (_) {}
      }

      // STEP 4: Fallback to Raw Query on JioSaavn if anchor query returned no matches
      if (jioResults.isEmpty) {
        try {
          final rawJioResp = await http
              .get(ApiConfig.jioSearchUri(query, limit: jioLimit, page: 1))
              .timeout(const Duration(seconds: 6))
              .catchError((_) => http.Response('[]', 500));

          if (rawJioResp.statusCode == 200) {
            jioResults = _parseJioResults(rawJioResp.body, query: query);
          }
        } catch (_) {}
      }

      // Filter genuine studio songs and deduplicate JioSaavn pool
      final genuineJio = CanonicalSongDedup.deduplicateList(
        jioResults.where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
      );

      // STEP 5: Extract genuine similar songs, live versions, and variations from YTM
      // Deduplicate YTM tracks (excluding the anchor which is already represented by Jio 320k)
      final List<Video> remainingYtm = ytmResults.length > 1
          ? ytmResults.sublist(1)
          : [];
      final cleanRemainingYtm = remainingYtm
          .where((v) => !isUnnecessaryOrAmateurResult(v, query))
          .toList();
      final dedupedYtm = CanonicalSongDedup.deduplicateList(
        genuineJio,
        cleanRemainingYtm,
      );

      // STEP 6: Combine Studio 320k Audio + Similar Songs from YTM
      final combined = <Video>[...genuineJio, ...dedupedYtm];

      // If JioSaavn returned nothing at all, return all YTM tracks directly
      if (genuineJio.isEmpty && ytmResults.isNotEmpty) {
        final ranked = _rankSearchResults(
          ytmResults,
          query,
          anchorVideo: ytmAnchor,
        );
        unawaited(MusicService().enrichArtworkForSongs(ranked));
        return ranked;
      }

      final ranked = _rankSearchResults(
        combined,
        query,
        anchorVideo: ytmAnchor,
      );

      debugPrint(
        '[StudioSearchService] Resolved "$query": ${genuineJio.length} Jio studio 320k + ${dedupedYtm.length} YTM similar songs',
      );

      // Background artwork enrichment for any incomplete thumbnails
      unawaited(MusicService().enrichArtworkForSongs(ranked));
      return ranked;
    } catch (e) {
      debugPrint('[StudioSearchService] Error searching: $e');
      // Graceful fallback to MusicService.searchSongs
      return MusicService().searchSongs(rawQuery, page: page, limit: limit);
    }
  }

  /// Parses JioSaavn JSON search response and registers artwork, stream URLs, and album metadata.
  List<Video> _parseJioResults(String body, {String? query}) {
    final List<Video> list = [];
    try {
      final List<dynamic> jsonList = json.decode(body);
      for (var item in jsonList) {
        if (item is! Map) continue;
        final songId = item['id'] as String? ?? '';
        if (songId.isEmpty) continue;

        final rawTitle = item['title'] as String? ?? 'Unknown Title';
        final rawAuthor = item['author'] as String? ?? 'DilSe Music';
        final cleanA = CanonicalSongDedup.cleanArtist(rawAuthor);
        final author = cleanA.isNotEmpty ? cleanA : rawAuthor;
        final title = CanonicalSongDedup.sanitizeDisplayTitle(
          rawTitle,
          artist: author,
        );

        final album = item['album'] as String? ?? '';
        final durationSec = item['duration'] != null
            ? int.tryParse(item['duration'].toString())
            : null;
        final duration = durationSec != null
            ? Duration(seconds: durationSec)
            : null;
        final artwork = item['thumbnail'] as String? ?? '';
        final streamUrl = item['streamUrl'] as String? ?? '';

        final vidString = songId.length >= 11
            ? songId.substring(0, 11)
            : songId.padRight(11, '0');

        if (artwork.isNotEmpty) {
          MusicService.registerArtwork(songId, artwork);
          MusicService.registerArtwork(vidString, artwork);
        }
        if (streamUrl.isNotEmpty) {
          MusicService.cacheWebStreamUrl(songId, streamUrl);
          MusicService.cacheWebStreamUrl(vidString, streamUrl);
        }
        final lang = item['language'] as String? ?? '';
        if (lang.isNotEmpty) {
          CanonicalSongDedup.registerSongLanguage(songId, lang);
          CanonicalSongDedup.registerSongLanguage(vidString, lang);
        }
        final albumId =
            item['album_id']?.toString() ?? item['albumId']?.toString() ?? '';
        if (album.isNotEmpty || albumId.isNotEmpty) {
          MusicService.registerSongAlbum(
            songId,
            albumTitle: album,
            albumId: albumId,
          );
          MusicService.registerSongAlbum(
            vidString,
            albumTitle: album,
            albumId: albumId,
          );
        }

        final video = Video(
          VideoId(vidString),
          title,
          author,
          ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
          DateTime.now(),
          '',
          null,
          '',
          duration,
          ThumbnailSet(vidString),
          null,
          Engagement(0, null, null),
          false,
        );

        if (CanonicalSongDedup.isGenuineSong(video)) {
          list.add(video);
        }
      }
    } catch (_) {}
    return list;
  }

  /// Evaluates whether a track represents an unnecessary derivative,
  /// amateur bedroom cover, instrumental rendition, or altered cut when the user
  /// did not explicitly search for those keywords.
  static bool isUnnecessaryOrAmateurResult(Video video, String query) {
    final title = video.title.toLowerCase();
    final author = video.author.toLowerCase();
    final cleanQ = query.toLowerCase().trim();

    // If the user explicitly searched for instrumental/cover/slowed terms, allow them
    final userWantsCover = cleanQ.contains('cover');
    final userWantsInstrumental =
        cleanQ.contains('instrumental') ||
        cleanQ.contains('piano') ||
        cleanQ.contains('guitar') ||
        cleanQ.contains('violin') ||
        cleanQ.contains('flute') ||
        cleanQ.contains('oud') ||
        cleanQ.contains('karaoke');
    final userWantsSlowed =
        cleanQ.contains('slowed') ||
        cleanQ.contains('reverb') ||
        cleanQ.contains('sped') ||
        cleanQ.contains('speed') ||
        cleanQ.contains('nightcore');
    final userWantsAmbient =
        cleanQ.contains('ambient') ||
        cleanQ.contains('lofi') ||
        cleanQ.contains('lo-fi') ||
        cleanQ.contains('chill');

    // 1. Instrumental & Amateur Covers in Title
    if (!userWantsInstrumental && !userWantsCover) {
      if (RegExp(
        r'\b(piano\s+(version|cover|rendition|tutorial|solo)|arabic\s+oud|oud\s+(version|cover|rendition)|guitar\s+(cover|version|rendition|solo)|acoustic\s+(cover|version|rendition)|violin\s+(cover|version|rendition|solo)|flute\s+(cover|version|rendition|solo)|harp\s+(cover|version)|cello\s+(cover|version)|saxophone?\s+(cover|version)|instrumental(\s+(cover|version|rendition))?|karaoke(\s+version)?|backing\s+track|minus\s+one|tribute\s+(to|band)|rendition|tutorial)\b',
        caseSensitive: false,
      ).hasMatch(title)) {
        return true;
      }
      if (RegExp(
        r'(\(|\[)(piano|guitar|violin|flute|oud|acoustic|instrumental|karaoke)(\)|\])',
        caseSensitive: false,
      ).hasMatch(title)) {
        return true;
      }
    }

    // 2. Slowed, Sped Up, Nightcore, Ambient, Social Media Alterations in Title
    if (!userWantsSlowed) {
      if (RegExp(
        r'\b(slowed(\s+to\s+perfection|\s*\+\s*reverb|\s+and\s+reverb|\s+down)?|(speed|sped)(\s*up)?|nightcore|daycore|pitch(\s+shifted)?)\b',
        caseSensitive: false,
      ).hasMatch(title)) {
        return true;
      }
    }

    if (!userWantsAmbient) {
      if (RegExp(
        r'\b(ambient(\s+(version|mix|edit))?|lofi(\s+(version|mix|remix|beats?))?|lo-fi(\s+(version|mix|remix|beats?))?|8d\s+audio|bass\s+boosted|tiktok(\s+(version|remix|edit))?|reels?(\s+(version|cut|edit))?|1\s*min(\s*(version|cut|mix))?|shorts?|status\s+video|ringtone)\b',
        caseSensitive: false,
      ).hasMatch(title)) {
        return true;
      }
    }

    // 3. Amateur/UGC cover artist channels (e.g. "pianaura", "oud awwad", channels containing cover, karaoke, etc.)
    if (!userWantsCover && !userWantsInstrumental) {
      if (author.contains('piano') ||
          author.contains('oud') ||
          author.contains('cover') ||
          author.contains('karaoke') ||
          author.contains('instrumental') ||
          author.contains('tribute')) {
        if (!DynamicArtistService().isKnownArtist(video.author)) {
          return true;
        }
      }
    }

    if (!userWantsSlowed) {
      if (author.contains('slowed') ||
          author.contains('reverb') ||
          author.contains('nightcore') ||
          author.contains('sped up')) {
        return true;
      }
    }

    if (!userWantsAmbient) {
      if (author.contains('ambient') ||
          author.contains('lofi') ||
          author.contains('lo-fi')) {
        return true;
      }
    }

    // 4. TrendingCatalogService general spam/junk regex (compilations, reels, 1-min mixes, etc.)
    if ((!userWantsSlowed &&
            TrendingCatalogService.isSpamOrJunk(video.title)) ||
        TrendingCatalogService.isSpamOrJunk(video.author)) {
      return true;
    }

    return false;
  }

  /// Calculates a popularity and relevance score for ranking authentic studio hits first.
  int _computePopularityScore(
    Video video,
    String rawQuery, {
    Video? anchorVideo,
  }) {
    int score = 0;
    final titleLower = video.title.toLowerCase().trim();
    final cleanT = CanonicalSongDedup.cleanTitle(video.title);
    final cleanQ = CanonicalSongDedup.cleanTitle(rawQuery);
    final cleanAuthor = CanonicalSongDedup.cleanArtist(
      video.author,
    ).toLowerCase();
    final authorLower = video.author.toLowerCase().trim();

    // 1. Title Alignment with Query
    if (titleLower == rawQuery.toLowerCase().trim()) {
      score += 600;
    } else if (cleanT == cleanQ) {
      score += 500;
    } else if (cleanT.startsWith(cleanQ) || cleanQ.startsWith(cleanT)) {
      score += 250;
    } else if (cleanT.contains(cleanQ)) {
      score += 150;
    }

    // 2. Canonical Anchor Match (The primary hit entity identified for this search)
    if (anchorVideo != null) {
      final anchorArtist = CanonicalSongDedup.cleanArtist(
        anchorVideo.author,
      ).toLowerCase();
      final anchorTitle = CanonicalSongDedup.cleanTitle(anchorVideo.title);

      // Exact canonical hit match: Title AND Artist align with Google anchor
      if (cleanT == anchorTitle &&
          (cleanAuthor == anchorArtist || authorLower.contains(anchorArtist))) {
        score += 1000;
      } else if (anchorArtist.isNotEmpty &&
          (cleanAuthor == anchorArtist || authorLower.contains(anchorArtist))) {
        // Same artist as the canonical hit (e.g. other official songs from the same artist/album)
        score += 350;
      }
    }

    // 3. Studio 320k Catalog Audio Bonus (Official distributor commercial release)
    final isJioStudio =
        video.id.value.startsWith('jio_') ||
        video.id.value.length < 11 ||
        MusicService.getCachedWebStreamUrl(video.id.value) != null;
    if (isJioStudio) {
      score += 250;
    }

    // 4. Known Verified Artist Bonus
    if (DynamicArtistService().isKnownArtist(video.author) ||
        DynamicArtistService().isKnownArtist(cleanAuthor)) {
      score += 200;
    }

    // 5. Query matching artist name directly
    if (authorLower.contains(cleanQ) || cleanAuthor.contains(cleanQ)) {
      score += 400;
    }

    return score;
  }

  /// High-accuracy ranking ensuring authentic, popular studio releases appear strictly at the top.
  List<Video> _rankSearchResults(
    List<Video> songs,
    String rawQuery, {
    Video? anchorVideo,
  }) {
    if (songs.isEmpty || rawQuery.trim().isEmpty) return songs;

    final cleanPool = songs
        .where(
          (s) =>
              CanonicalSongDedup.isGenuineSong(s) &&
              !isUnnecessaryOrAmateurResult(s, rawQuery),
        )
        .toList();
    final dedupedSongs = CanonicalSongDedup.deduplicateList(cleanPool);

    final pool = List<Video>.from(dedupedSongs);
    pool.sort((a, b) {
      final scoreA = _computePopularityScore(
        a,
        rawQuery,
        anchorVideo: anchorVideo,
      );
      final scoreB = _computePopularityScore(
        b,
        rawQuery,
        anchorVideo: anchorVideo,
      );
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Highest popularity score first
      }
      return 0;
    });

    return pool;
  }
}
