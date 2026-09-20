import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:palette_generator/palette_generator.dart';
import 'api_config.dart';
import 'preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_player_bridge.dart';

class StreamCandidate {
  final String url;
  final int tag;
  final String type;
  StreamCandidate(this.url, this.tag, this.type);
}

class MusicService extends ChangeNotifier {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;

  MusicService._internal() {
    _initAudioPlayer();
    loadDownloadedSongs();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  final YoutubeExplode _ytExplode = YoutubeExplode();

  Video? _currentSong;
  List<Video> _playlist = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  List<Map<String, String>> _likedSongs = [];
  List<Map<String, dynamic>> _customPlaylists = [];

  String? _cachedLyrics;
  String? _cachedLyricsSongId;
  bool _isFetchingLyrics = false;

  // Palette Extraction
  Color _dominantColor = const Color(0xFF1E1E2C);
  Color _vibrantColor = const Color(0xFFFA2D48);

  // Sleep Timer
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  Duration? _sleepRemaining;
  bool _stopAtEndOfTrack = false;

  Video? get currentSong => _currentSong;
  List<Video> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isShuffle => _isShuffle;
  LoopMode get loopMode => _loopMode;
  List<Map<String, String>> get likedSongs => _likedSongs;
  List<Map<String, dynamic>> get customPlaylists => _customPlaylists;
  AudioPlayer get audioPlayer => _audioPlayer;

  bool get isPlaying => kIsWeb ? WebPlayerBridge.isPlaying : _audioPlayer.playing;
  Duration get position => kIsWeb ? WebPlayerBridge.currentPosition : _audioPlayer.position;
  Duration? get duration => kIsWeb ? WebPlayerBridge.currentDuration : _audioPlayer.duration;
  Stream<Duration> get positionStream => kIsWeb ? WebPlayerBridge.positionStream : _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => kIsWeb ? WebPlayerBridge.durationStream : _audioPlayer.durationStream;

  String? get cachedLyrics => _cachedLyrics;
  bool get isFetchingLyrics => _isFetchingLyrics;

  Color get dominantColor => _dominantColor;
  Color get vibrantColor => _vibrantColor;

  bool get isSleepTimerActive => _sleepTimer != null || _stopAtEndOfTrack;
  Duration? get sleepRemaining => _sleepRemaining;
  bool get stopAtEndOfTrack => _stopAtEndOfTrack;

  String get sleepTimerLabel {
    if (_stopAtEndOfTrack) return 'End of Track';
    if (_sleepRemaining != null) {
      final mins = _sleepRemaining!.inMinutes;
      final secs = _sleepRemaining!.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$mins:$secs';
    }
    return 'Off';
  }

  static String _cleanSongTitle(String raw) {
    // 1. Remove text inside parentheses & brackets like (Official Video), [4K], (Telugu)
    var s = raw.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');

    // 2. Split on common delimiters and keep primary song name
    final parts = s.split(RegExp(r'\s*[|:–—/]\s*|\s+-\s+'));
    if (parts.isNotEmpty) {
      s = parts.first;
    }

    // 3. Remove common YouTube noise words (case-insensitive)
    s = s.replaceAll(RegExp(
      r'\b(full\s+video\s+song|video\s+song|lyric\s+video|official\s+video|official\s+music\s+video|official\s+song|full\s+song|full\s+audio|audio\s+song|lyrics|lyrical|hd|4k|8k|song|track|remix|mashup)\b',
      caseSensitive: false,
    ), ' ');

    // 4. Clean extra whitespace
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _cleanArtistName(String raw) {
    var s = raw.replaceAll(' - Topic', '').trim();
    final lower = s.toLowerCase();
    const labels = [
      't-series', 'aditya music', 'sony music', 'zee music', 'lahari music',
      'speed audio', 'tips official', 'saregama', 'yrf', 'think music',
      'tseries', 'vevo', 'records', 'entertainment', 'music'
    ];
    for (final label in labels) {
      if (lower.contains(label)) return '';
    }
    return s;
  }

  Future<void> fetchLyrics(Video song) async {
    if (_cachedLyricsSongId == song.id.value && _cachedLyrics != null) return;

    _isFetchingLyrics = true;
    _cachedLyrics = null;
    _cachedLyricsSongId = song.id.value;
    notifyListeners();

    try {
      final cleanTitle = _cleanSongTitle(song.title);
      final cleanArtist = _cleanArtistName(song.author);

      List<dynamic> results = [];
      // Tier 1: Clean Title + Clean Artist
      if (cleanTitle.isNotEmpty && cleanArtist.isNotEmpty) {
        try {
          final url1 = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}');
          final res1 = await http.get(url1, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
          // BUG-2 fix: discard result if song changed while we were fetching.
          if (_cachedLyricsSongId != song.id.value) return;
          if (res1.statusCode == 200) {
            results = json.decode(res1.body);
          }
        } catch (_) {}
      }

      // Tier 2: Clean Title via track_name parameter
      if (results.isEmpty && cleanTitle.isNotEmpty) {
        try {
          final url2 = Uri.parse('https://lrclib.net/api/search?track_name=${Uri.encodeComponent(cleanTitle)}');
          final res2 = await http.get(url2, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
          if (_cachedLyricsSongId != song.id.value) return;
          if (res2.statusCode == 200) {
            results = json.decode(res2.body);
          }
        } catch (_) {}
      }

      // Tier 3: General query with clean title
      if (results.isEmpty && cleanTitle.isNotEmpty) {
        try {
          final url3 = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(cleanTitle)}');
          final res3 = await http.get(url3, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
          if (_cachedLyricsSongId != song.id.value) return;
          if (res3.statusCode == 200) {
            results = json.decode(res3.body);
          }
        } catch (_) {}
      }

      if (_cachedLyricsSongId != song.id.value) return;

      if (results.isNotEmpty) {
        final first = results.first;
        _cachedLyrics = first['syncedLyrics'] ?? first['plainLyrics'] ?? 'No lyrics available.';
      } else {
        _cachedLyrics = 'No lyrics found for "$cleanTitle".';
      }
    } catch (e) {
      _cachedLyrics = 'Lyrics temporarily unavailable.';
    } finally {
      if (_cachedLyricsSongId == song.id.value) {
        _isFetchingLyrics = false;
        notifyListeners();
      }
    }
  }

  static final Map<String, String> _artworkMap = {};
  // NOTE: Stream URLs (YouTube CDN / JioSaavn) are time-limited (~6 hours).
  // We intentionally do NOT cache them across plays to prevent stale-URL buffering
  // in saved/imported playlists. A fresh URL is always resolved at play time.

  static String getHdThumbnail(String videoId) {
    if (_artworkMap.containsKey(videoId)) {
      return _artworkMap[videoId]!;
    }
    return 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
  }

  bool _isTransitioning = false;
  bool _isFetchingNextQueue = false;

  List<Video> _preloadedTopChartsIndia = [];
  List<Video> _preloadedTrending = [];
  bool _hasPreloadedHome = false;

  List<Video> get preloadedTopChartsIndia => _preloadedTopChartsIndia;
  List<Video> get preloadedTrending => _preloadedTrending;
  bool get hasPreloadedHome => _hasPreloadedHome;

  Future<void> preloadHomeData() async {
    if (_hasPreloadedHome) return;
    try {
      final results = await Future.wait([
        searchSongs('Top Charts India Music'),
        searchSongs('Trending Songs 2026'),
      ]);
      _preloadedTopChartsIndia = results[0];
      _preloadedTrending = results[1];
      _hasPreloadedHome = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Preload] Home data preload: $e');
    }
  }

  void _initAudioPlayer() {
    if (kIsWeb) {
      WebPlayerBridge.init();
      WebPlayerBridge.onTrackEnded.listen((_) async {
        if (_isTransitioning) return;
        _isTransitioning = true;
        try {
          if (_loopMode == LoopMode.one && _currentSong != null) {
            WebPlayerBridge.seek(Duration.zero);
            WebPlayerBridge.resume();
          } else {
            await nextSong();
          }
        } catch (e) {
          debugPrint('[WebPlayer] Completion error: $e');
        } finally {
          _isTransitioning = false;
        }
      });
      WebPlayerBridge.onNext.listen((_) => nextSong());
      WebPlayerBridge.onPrevious.listen((_) => previousSong());
      WebPlayerBridge.stateStream.listen((_) => notifyListeners());
    }

    _audioPlayer.playerStateStream.listen((state) async {
      notifyListeners();
      if (state.processingState == ProcessingState.completed) {
        if (_isTransitioning) return;
        _isTransitioning = true;
        try {
          if (_loopMode == LoopMode.one) {
            debugPrint('[AudioPlayer] LoopMode.one active: repeating current track…');
            await _audioPlayer.seek(Duration.zero);
            await _audioPlayer.play();
          } else {
            debugPrint('[AudioPlayer] Track completed. Advancing to next song…');
            await nextSong();
          }
        } catch (e) {
          debugPrint('[AudioPlayer] Error handling song completion: $e');
        } finally {
          _isTransitioning = false;
        }
      }
    });
    loadLikedSongs();
    loadCustomPlaylists();
  }

  Future<void> loadLikedSongs() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('liked_songs_web');
        if (raw != null && raw.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(raw);
          _likedSongs = jsonList.map((e) => Map<String, String>.from(e)).toList();
          notifyListeners();
        }
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/liked_songs.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        _likedSongs = jsonList.map((e) => Map<String, String>.from(e)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading liked songs: $e');
    }
  }

  void toggleLike(Video song) async {
    final exists = _likedSongs.any((s) => s['id'] == song.id.value);
    if (exists) {
      _likedSongs.removeWhere((s) => s['id'] == song.id.value);
    } else {
      _likedSongs.add({
        'id': song.id.value,
        'title': song.title,
        'author': song.author,
        'thumbnail': getHdThumbnail(song.id.value),
      });
    }
    notifyListeners();

    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('liked_songs_web', json.encode(_likedSongs));
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/liked_songs.json');
      await file.writeAsString(json.encode(_likedSongs));
    } catch (e) {
      debugPrint('Error saving liked songs: $e');
    }
  }

  Future<void> removeLikedSong(String videoId) async {
    _likedSongs.removeWhere((s) => s['id'] == videoId);
    notifyListeners();
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('liked_songs_web', json.encode(_likedSongs));
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/liked_songs.json');
      await file.writeAsString(json.encode(_likedSongs));
    } catch (e) {
      debugPrint('Error saving liked songs: $e');
    }
  }

  Future<void> loadCustomPlaylists() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('custom_playlists_web');
        if (raw != null && raw.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(raw);
          _customPlaylists = List<Map<String, dynamic>>.from(jsonList);
          notifyListeners();
        }
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/custom_playlists.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        _customPlaylists = List<Map<String, dynamic>>.from(jsonList);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading custom playlists: $e');
    }
  }

  Future<void> saveCustomPlaylists() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_playlists_web', json.encode(_customPlaylists));
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/custom_playlists.json');
      await file.writeAsString(json.encode(_customPlaylists));
    } catch (e) {
      debugPrint('Error saving custom playlists: $e');
    }
  }

  String createPlaylist(String name) {
    final playlistId = DateTime.now().millisecondsSinceEpoch.toString();
    _customPlaylists.add({
      'id': playlistId,
      'name': name,
      'songs': [],
    });
    saveCustomPlaylists();
    notifyListeners();
    return playlistId;
  }

  void addSongToPlaylist(String playlistId, Video song) {
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex != -1) {
      final songs = List<Map<String, dynamic>>.from(_customPlaylists[playlistIndex]['songs'] ?? []);
      
      // Prevent duplicates
      if (!songs.any((s) => s['id'] == song.id.value)) {
        songs.add({
          'id': song.id.value,
          'title': song.title,
          'author': song.author,
          'thumbnail': getHdThumbnail(song.id.value),
        });
        _customPlaylists[playlistIndex]['songs'] = songs;
        saveCustomPlaylists();
        notifyListeners();
      }
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    _customPlaylists.removeWhere((p) => p['id'] == playlistId);
    await saveCustomPlaylists();
    notifyListeners();
  }

  Future<void> playCustomPlaylist(String playlistId, int startIndex) async {
    final playlist = _customPlaylists.firstWhere((p) => p['id'] == playlistId, orElse: () => <String, dynamic>{});
    if (playlist.isEmpty) return;

    final songs = List<Map<String, dynamic>>.from(playlist['songs'] ?? []);
    if (songs.isEmpty) return;

    _playlist = songs.map((item) => Video(
      VideoId((item['id'] as String?) ?? ''),
      (item['title'] as String?) ?? 'Unknown Title',
      (item['author'] as String?) ?? 'Unknown Artist',
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      null,
      ThumbnailSet((item['id'] as String?) ?? ''),
      null,
      Engagement(0, null, null),
      false,
    )).toList();

    _currentIndex = startIndex;
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) _currentIndex = 0;
    
    await playSong(_playlist[_currentIndex], updateQueue: false);
  }


  Future<void> playLikedSong(Map<String, String> songData) async {
    _playlist = _likedSongs.map((item) => Video(
      VideoId(item['id'] ?? ''),
      item['title'] ?? 'Unknown Title',
      item['author'] ?? 'Unknown Artist',
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      null,
      ThumbnailSet(item['id'] ?? ''),
      null,
      Engagement(0, null, null),
      false,
    )).toList();

    _currentIndex = _likedSongs.indexWhere((item) => item['id'] == songData['id']);
    if (_currentIndex == -1) _currentIndex = 0;
    if (_playlist.isNotEmpty) {
      await playSong(_playlist[_currentIndex], updateQueue: false);
    }
  }

  void seekRelative(Duration offset) {
    final current = position;
    final target = current + offset;
    seek(target);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (!kIsWeb) {
      _audioPlayer.setShuffleModeEnabled(_isShuffle);
    }
    notifyListeners();
  }

  void toggleRepeat() {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    if (!kIsWeb) {
      _audioPlayer.setLoopMode(_loopMode);
    }
    notifyListeners();
  }

  Future<List<Video>> searchSongs(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];

    // Web / PWA: Query official JioSaavn catalog for instant 320kbps streams & pristine covers
    if (kIsWeb) {
      try {
        final response = await http
            .get(ApiConfig.jioSearchUri(query, limit: 25))
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final List<dynamic> jsonList = json.decode(response.body);
          if (jsonList.isNotEmpty) {
            final List<Video> results = [];
            for (var item in jsonList) {
              final songId = item['id'] as String? ?? '';
              if (songId.isEmpty) continue;
              final title = item['title'] as String? ?? 'Unknown Title';
              final author = item['author'] as String? ?? 'DilSe Music';
              final durationSec = item['duration'] != null ? int.tryParse(item['duration'].toString()) : null;
              final duration = durationSec != null ? Duration(seconds: durationSec) : null;
              final artwork = item['thumbnail'] as String? ?? '';

              // Format valid 11-char ID for Video model
              final vidString = songId.length >= 11 ? songId.substring(0, 11) : songId.padRight(11, '0');

              if (artwork.isNotEmpty) {
                _artworkMap[songId] = artwork;
                _artworkMap[vidString] = artwork;
              }
              // Stream URLs are time-limited — we store artwork only.
              // The Cloudflare Worker will resolve a fresh URL at play time.

              results.add(
                Video(
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
                ),
              );
            }
            debugPrint('[JioSaavn Search][Web] Returned ${results.length} items for "$query"');
            return results;
          }
        }
      } catch (e) {
        debugPrint('[JioSaavn Search][Web] Error: $e, falling back to YouTube search');
      }
    }

    // Android Mobile & Web Fallback: Python Backend / YouTube search
    try {
      final response = await http
          .get(ApiConfig.searchUri(query, page: page, limit: 20))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final List<Video> results = [];

        for (var item in jsonList) {
          final videoId = item['id'] as String;
          final title = item['title'] as String? ?? 'Unknown Title';
          final author = item['author'] as String? ?? 'Unknown Artist';
          final durationSec = item['duration'] != null ? int.tryParse(item['duration'].toString()) : null;
          final duration = durationSec != null ? Duration(seconds: durationSec) : null;

          results.add(
            Video(
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
            ),
          );
        }
        debugPrint('[Backend Search] Returned ${results.length} items for "$query" (page $page)');
        return results;
      }
    } catch (e) {
      debugPrint('Backend search error: $e');
    }
    return [];
  }

  /// Live query suggestions while typing (up to [limit] suggestions)
  Future<List<String>> fetchSuggestions(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return [];

    if (kIsWeb) {
      try {
        final response = await http
            .get(ApiConfig.jioSuggestionsUri(query, limit: limit))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final List<dynamic> jsonList = json.decode(response.body);
          return jsonList.map((e) => e.toString()).toList();
        }
      } catch (e) {
        debugPrint('jioSuggestions error: $e');
      }
    }

    try {
      final response = await http
          .get(ApiConfig.suggestionsUri(query, limit: limit))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('fetchSuggestions error: $e');
    }
    return [];
  }

  /// Reports track completion for collaborative filtering co-occurrence
  Future<void> reportTrackFinished(String currentId, String nextId) async {
    try {
      await http.post(
        ApiConfig.trackFinishedUri(),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'current_id': currentId, 'next_id': nextId}),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[Collaborative] Reported track transition: $currentId -> $nextId');
    } catch (e) {
      debugPrint('reportTrackFinished error: $e');
    }
  }

  /// Fetches the next 20 songs using collaborative patterns, genre, and radio
  Future<List<Video>> fetchNextCandidates(
    String videoId, {
    int limit = 20,
    String? title,
    String? artist,
  }) async {
    try {
      final response = await http
          .get(ApiConfig.nextCandidatesUri(videoId, limit: limit, title: title, artist: artist))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final List<Video> results = [];
        for (var item in jsonList) {
          final vid = item['id'] as String;
          final title = item['title'] as String? ?? 'Unknown Title';
          final author = item['author'] as String? ?? 'Unknown Artist';
          final durationSec = item['duration'] != null ? int.tryParse(item['duration'].toString()) : null;
          results.add(
            Video(
              VideoId(vid),
              title,
              author,
              ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
              DateTime.now(),
              '',
              null,
              '',
              durationSec != null ? Duration(seconds: durationSec) : null,
              ThumbnailSet(vid),
              null,
              Engagement(0, null, null),
              false,
            ),
          );
        }
        return results;
      }
    } catch (e) {
      debugPrint('fetchNextCandidates error: $e');
    }
    return [];
  }

  Future<void> _extractPalette(String videoId) async {
    try {
      // hqdefault is guaranteed to exist on YouTube CDN, preventing 404 SocketExceptions
      final imageUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(100, 100),
        maximumColorCount: 8,
      ).timeout(const Duration(seconds: 3));

      // BUG-1 fix: discard stale palette if the song changed while we were extracting.
      // Rapid skips can launch multiple concurrent extractions; only apply the result
      // for the song that is currently playing.
      if (_currentSong?.id.value != videoId) return;

      final dominant = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? const Color(0xFF1E1E2C);
      final vibrant = palette.vibrantColor?.color ?? palette.lightVibrantColor?.color ?? dominant;

      _dominantColor = dominant;
      _vibrantColor = vibrant;
      notifyListeners();
    } catch (e) {
      debugPrint('[Palette] Extraction error: $e');
    }
  }

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepRemaining = duration;
    _stopAtEndOfTrack = false;
    notifyListeners();

    // BUG-6 fix: only count down while audio is actually playing.
    // The original code used wall-clock time, so pausing the player did not
    // pause the countdown — sleep fired earlier than the user expected.
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final isCurrentlyPlaying = kIsWeb ? WebPlayerBridge.isPlaying : _audioPlayer.playing;
      if (!isCurrentlyPlaying) return; // player is paused — don't advance countdown

      if (_sleepRemaining != null && _sleepRemaining!.inSeconds > 0) {
        _sleepRemaining = _sleepRemaining! - const Duration(seconds: 1);
        notifyListeners();
        if (_sleepRemaining!.inSeconds <= 0) {
          timer.cancel();
          _stopPlayback();
        }
      } else {
        timer.cancel();
      }
    });

    // Keep the hard-deadline Timer as a safety net but cancel it in cancelSleepTimer
    _sleepTimer = Timer(duration * 2, () {
      // Safety fallback in case periodic timer missed stopping playback
      if (_sleepRemaining != null && _sleepRemaining!.inSeconds <= 0) {
        _stopPlayback();
      }
    });
  }

  void setStopAtEndOfTrack(bool enable) {
    cancelSleepTimer();
    _stopAtEndOfTrack = enable;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepCountdownTimer?.cancel();
    _sleepCountdownTimer = null;
    _sleepRemaining = null;
    _stopAtEndOfTrack = false;
    notifyListeners();
  }

  void _stopPlayback() {
    if (kIsWeb) {
      WebPlayerBridge.pause();
    } else {
      _audioPlayer.pause();
    }
    cancelSleepTimer();
    notifyListeners();
  }

  Future<void> playPlaylist(List<Video> playlist, int index) async {
    _playlist = List.from(playlist);
    _currentIndex = index;
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      await playSong(_playlist[_currentIndex], updateQueue: false);
    }
  }

  void _checkAndPreloadNextQueue() {
    // When 5 or fewer songs remain after current playing song, silently load next 20 songs
    if ((_playlist.length - (_currentIndex + 1)) <= 5 && _currentSong != null) {
      final seedSong = _playlist.isNotEmpty ? _playlist.last : _currentSong!;
      _fetchNextRecommendations(seedSong);
    }
  }

  Future<void> nextSong() async {
    if (_stopAtEndOfTrack) {
      debugPrint('[SleepTimer] Reached end of current track. Stopping playback.');
      _stopPlayback();
      return;
    }

    if (_playlist.isNotEmpty) {
      if (_isShuffle && _playlist.length > 1) {
        final random = Random();
        int nextIdx = random.nextInt(_playlist.length);
        if (nextIdx == _currentIndex) {
          nextIdx = (nextIdx + 1) % _playlist.length;
        }
        final prevSong = _currentSong;
        _currentIndex = nextIdx;
        final nextTrack = _playlist[_currentIndex];
        if (prevSong != null) {
          reportTrackFinished(prevSong.id.value, nextTrack.id.value);
        }
        await playSong(nextTrack, updateQueue: false);
        _checkAndPreloadNextQueue();
        return;
      } else if (_currentIndex + 1 < _playlist.length) {
        final prevSong = _currentSong;
        _currentIndex++;
        final nextTrack = _playlist[_currentIndex];
        if (prevSong != null) {
          reportTrackFinished(prevSong.id.value, nextTrack.id.value);
        }
        await playSong(nextTrack, updateQueue: false);
        _checkAndPreloadNextQueue();
        return;
      }
    }

    if (_currentSong != null) {
      debugPrint('[Queue] End of queue reached. Fetching next recommendations…');
      _isLoading = true;
      notifyListeners();
      await _fetchNextRecommendations(_currentSong!);
      if (_currentIndex + 1 < _playlist.length) {
        final prevSong = _currentSong;
        _currentIndex++;
        final nextTrack = _playlist[_currentIndex];
        if (prevSong != null) {
          reportTrackFinished(prevSong.id.value, nextTrack.id.value);
        }
        await playSong(nextTrack, updateQueue: false);
        _checkAndPreloadNextQueue();
      } else {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> previousSong() async {
    if (_playlist.isNotEmpty && _currentIndex - 1 >= 0) {
      _currentIndex--;
      await playSong(_playlist[_currentIndex], updateQueue: false);
    } else if (_playlist.isNotEmpty && position.inSeconds > 3) {
      // Replay current track from start
      if (kIsWeb) {
        WebPlayerBridge.seek(Duration.zero);
        notifyListeners();
      } else {
        await _audioPlayer.seek(Duration.zero);
      }
    }
  }

  // Full browser headers to avoid CDN 403s and throttling
  static const Map<String, String> _ytHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://www.youtube.com',
    'Referer': 'https://www.youtube.com/',
  };

  /// Fetches the stream URL from the backend.
  /// [bustCache] forces the backend to re-extract the URL (used on retry).
  Future<String?> _fetchStreamUrl(String videoId, {bool bustCache = false}) async {
    try {
      if (bustCache) {
        // Tell backend to discard its cached URL for this video
        await http.delete(ApiConfig.cacheInvalidateUri(videoId))
            .timeout(const Duration(seconds: 3));
      }
      final response = await http
          .get(ApiConfig.streamUrlUri(videoId))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['url'] as String?;
      }
    } catch (e) {
      debugPrint('_fetchStreamUrl error: $e');
    }
    return null;
  }

  void _reportClientLog(String stage, Map<String, dynamic> data) {
    try {
      final payload = {
        'stage': stage,
        'timestamp': DateTime.now().toIso8601String(),
        ...data,
      };
      http.post(
        ApiConfig.clientLogUri(),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  /// Resolves ordered stream candidates natively on the user's device.
  /// Prioritizes Format 18 (Progressive MP4 AAC) to eliminate ExoPlayer DASH fragmentation errors.
  Future<List<StreamCandidate>> _resolveStreamCandidates(String videoId) async {
    StreamManifest? manifest;

    try {
      manifest = await _ytExplode.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[StreamResolver] Primary instance error for $videoId: $e. Retrying with fresh instance…');
      try {
        final freshYt = YoutubeExplode();
        try {
          manifest = await freshYt.videos.streamsClient
              .getManifest(videoId)
              .timeout(const Duration(seconds: 20));
        } finally {
          freshYt.close();
        }
      } catch (e2) {
        debugPrint('[StreamResolver] Fresh instance error for $videoId: $e2');
        _reportClientLog('resolve_error', {'videoId': videoId, 'error': e2.toString()});
      }
    }

    if (manifest == null) return [];

    final List<StreamCandidate> candidates = [];

    // Candidate 1: Progressive Format 18 (MP4 with AAC stereo audio).
    // This is the golden standard for ExoPlayer on Android and AVPlayer on iOS
    // because it contains a progressive moov atom, avoiding DASH single-segment parser errors.
    final muxed18 = manifest.muxed.where((s) => s.tag == 18);
    if (muxed18.isNotEmpty) {
      candidates.add(StreamCandidate(muxed18.first.url.toString(), 18, 'mp4_progressive_360p_aac'));
    }

    // Candidate 2: Progressive WebM Opus (e.g. itag 251, 160kbps high-quality Opus)
    // ExoPlayer has native Matroska/WebM demuxing and plays this seamlessly on Android.
    final webmOpus = manifest.audioOnly.where(
      (s) => s.container.name.toLowerCase() == 'webm' || s.codec.mimeType.contains('webm') || s.codec.mimeType.contains('opus'),
    );
    if (webmOpus.isNotEmpty) {
      final best = webmOpus.withHighestBitrate();
      candidates.add(StreamCandidate(best.url.toString(), best.tag, 'audio_webm_opus'));
    }

    // Candidate 3: AudioOnly MP4 (itag 140, 128k AAC)
    final mp4Audio = manifest.audioOnly.where(
      (s) => s.container.name.toLowerCase() == 'mp4' || s.codec.mimeType.contains('mp4'),
    );
    if (mp4Audio.isNotEmpty) {
      candidates.add(StreamCandidate(mp4Audio.withHighestBitrate().url.toString(), 140, 'mp4_audio_dash'));
    }

    // Candidate 4: Any other muxed stream (e.g. itag 22 720p MP4)
    for (final m in manifest.muxed) {
      if (m.tag != 18) {
        candidates.add(StreamCandidate(m.url.toString(), m.tag, 'muxed_${m.container.name}'));
        break;
      }
    }

    return candidates;
  }

  Future<void> playSong(Video song, {bool updateQueue = true}) async {
    _isLoading = true;
    _currentSong = song;

    if (updateQueue) {
      final existingIndex = _playlist.indexWhere((item) => item.id == song.id);
      if (existingIndex != -1) {
        _currentIndex = existingIndex;
      } else {
        _playlist = [song];
        _currentIndex = 0;
      }
    }
    notifyListeners();

    // Immediately stop the current audio so the old song doesn't keep playing
    // while the new stream is being resolved. Stream resolution via
    // youtube_explode_dart can take 5–20 seconds, during which the previous
    // track would otherwise continue to play even though the UI already shows
    // the new song — causing the "ghost playback" skip bug.
    if (kIsWeb) {
      WebPlayerBridge.pause();
    } else {
      await _audioPlayer.stop();
    }

    // Trigger palette extraction asynchronously
    _extractPalette(song.id.value);

    // Pre-fetch lyrics concurrently so they are instant when opened
    fetchLyrics(song);

    // Track play count and history for personalization algorithm
    PreferencesService().recordSongPlay(song.author, song.title);
    PreferencesService().addToListeningHistory({
      'id': song.id.value,
      'title': song.title,
      'author': song.author,
      'thumbnail': getHdThumbnail(song.id.value),
      'playedAt': DateTime.now().toIso8601String(),
    });

    final mediaItem = MediaItem(
      id: song.id.value,
      album: 'DilSe',
      title: song.title,
      artist: song.author,
      artUri: Uri.tryParse(getHdThumbnail(song.id.value)),
      duration: song.duration,
    );

    try {
      // 1. If this song is downloaded locally, play directly from disk (mobile only)
      if (!kIsWeb) {
        final downloadedItem = _downloadedSongs.firstWhere(
          (item) => item['id'] == song.id.value,
          orElse: () => {},
        );

        if (downloadedItem.isNotEmpty && downloadedItem['localPath'] != null) {
          final localFile = File(downloadedItem['localPath']!);
          if (await localFile.exists()) {
            debugPrint('[Play] Playing locally downloaded file: ${localFile.path}');
            await _audioPlayer.setAudioSource(
              AudioSource.uri(Uri.file(localFile.path), tag: mediaItem),
            );
            await _audioPlayer.play();
            _isLoading = false;
            notifyListeners();
            _checkAndPreloadNextQueue();
            return;
          }
        }
      }

      // 2. Web Mode (PWA / Browser):
      // Always resolve a fresh stream URL via Cloudflare Worker at play time.
      // We never reuse a previously-cached stream URL because JioSaavn/YouTube
      // CDN URLs are signed and expire after ~6 hours, which causes buffering
      // in songs played from saved/imported playlists.
      if (kIsWeb) {
        final freshStreamUrl = ApiConfig.cloudflareStreamUri(song.id.value).toString();
        debugPrint('[Play][Web] Resolving fresh stream via Cloudflare Worker for: ${song.id.value}');
        _reportClientLog('web_stream_start', {'videoId': song.id.value, 'engine': 'cloudflare_fresh'});
        WebPlayerBridge.play(
          song.id.value,
          title: song.title,
          artist: song.author,
          artworkUrl: getHdThumbnail(song.id.value),
          streamUrl: freshStreamUrl,
        );
        _isLoading = false;
        notifyListeners();
        _checkAndPreloadNextQueue();
        return;
      }

      bool playbackSourceSet = false;

      // 3. Mobile Native Mode (Android / iOS app):
      // Direct On-Device Multi-Candidate Resolution (Format 18 progressive AAC / itag 251)
      try {
        debugPrint('[Play] Resolving direct audio candidates on mobile device for ${song.id.value}…');
        final candidates = await _resolveStreamCandidates(song.id.value);
        if (_currentSong?.id.value != song.id.value) return;


          if (candidates.isNotEmpty) {
            final tempDir = await getTemporaryDirectory();

            for (final candidate in candidates) {
              if (_currentSong?.id.value != song.id.value) return;

              debugPrint('[Play] Trying stream candidate (tag: ${candidate.tag}, type: ${candidate.type})…');
              _reportClientLog('trying_stream_candidate', {
                'videoId': song.id.value,
                'tag': candidate.tag,
                'type': candidate.type,
              });

              // 1. First attempt: Direct native AudioSource.uri (fastest, progressive hardware decoding)
              try {
                await _audioPlayer.setAudioSource(
                  AudioSource.uri(Uri.parse(candidate.url), tag: mediaItem),
                  preload: true,
                );
                playbackSourceSet = true;
                _reportClientLog('playback_started_uri', {
                  'videoId': song.id.value,
                  'tag': candidate.tag,
                });
                break;
              } catch (uriError) {
                debugPrint('[Play] AudioSource.uri failed ($uriError), trying LockCachingAudioSource…');
                // 2. Second attempt: LockCachingAudioSource fallback.
                // Always delete any pre-existing temp cache file first.
                // A stale/partial cache from a previous play attempt (e.g. an expired URL
                // that wrote a corrupt or incomplete file) will silently cause buffering
                // if we try to resume it instead of downloading fresh bytes.
                try {
                  final cacheFile = File('${tempDir.path}/track_${song.id.value}_${candidate.tag}.m4a');
                  if (await cacheFile.exists()) {
                    // Delete stale cache unconditionally so we always fetch fresh CDN bytes.
                    await cacheFile.delete();
                    debugPrint('[Play] Deleted stale temp-cache file for ${song.id.value} (tag: ${candidate.tag})');
                  }
                  await _audioPlayer.setAudioSource(
                    // ignore: experimental_member_use
                    LockCachingAudioSource(
                      Uri.parse(candidate.url),
                      cacheFile: cacheFile,
                      tag: mediaItem,
                    ),
                    preload: true,
                  );
                  playbackSourceSet = true;
                  _reportClientLog('playback_started_lockcache', {
                    'videoId': song.id.value,
                    'tag': candidate.tag,
                  });
                  break;
                } catch (lockError) {
                  debugPrint('[Play] Candidate tag ${candidate.tag} failed: $lockError');
                  _reportClientLog('candidate_failed', {
                    'videoId': song.id.value,
                    'tag': candidate.tag,
                    'uriError': uriError.toString(),
                    'lockError': lockError.toString(),
                  });
                }
              }
            }
          }
        } catch (directError) {
          if (_isInterrupted(directError)) {
            debugPrint('[Play] Load interrupted by newer request');
            return;
          }
          debugPrint('[Play] Direct resolution error ($directError), trying fallbacks…');
          _reportClientLog('direct_play_failed', {'videoId': song.id.value, 'error': directError.toString()});
        }

      // 3. Fallback 1: Backend /stream_url
      if (!playbackSourceSet) {
        if (_currentSong?.id.value != song.id.value) return;
        try {
          debugPrint('[Play] Fallback 1: Requesting /stream_url from backend…');
          final backendUrl = await _fetchStreamUrl(song.id.value);
          if (_currentSong?.id.value != song.id.value) return;
          if (backendUrl != null) {
            await _audioPlayer.setAudioSource(
              AudioSource.uri(Uri.parse(backendUrl), headers: _ytHeaders, tag: mediaItem),
              preload: true,
            );
            playbackSourceSet = true;
          }
        } catch (backendUrlError) {
          debugPrint('[Play] Backend /stream_url error: $backendUrlError');
        }
      }

      // 4. Fallback 2: Backend proxy /stream/{id}.m4a
      if (!playbackSourceSet) {
        if (_currentSong?.id.value != song.id.value) return;
        final proxyUri = ApiConfig.streamProxyUri(song.id.value);
        debugPrint('[Play] Fallback 2: Setting audio source to proxy: $proxyUri');
        await _audioPlayer.setAudioSource(
          AudioSource.uri(proxyUri, tag: mediaItem),
          preload: true,
        );
      }

      if (_currentSong?.id.value != song.id.value) return;

      debugPrint('[Play] Starting playback…');
      await _audioPlayer.play();
      _isLoading = false;
      notifyListeners();

      _reportClientLog('playback_active', {
        'videoId': song.id.value,
        'title': song.title,
      });

      _preloadUpcomingTracks();
      _checkAndPreloadNextQueue();
    } catch (e, st) {
      if (_isInterrupted(e)) {
        debugPrint('[Play] Playback superseded by newer song selection');
        return;
      }
      debugPrint('[Play] Error playing song: $e\n$st');
    } finally {
      if (_currentSong?.id.value == song.id.value) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isInterrupted(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('loading interrupted') || msg.contains('interrupted');
  }

  void _preloadUpcomingTracks() {
    if (_playlist.isEmpty) return;
    final nextTracks = _playlist.skip(_currentIndex + 1).take(2);
    for (final track in nextTracks) {
      http.get(ApiConfig.preloadUri(track.id.value)).catchError((_) => http.Response('', 500));
    }
  }

  Future<void> _fetchNextRecommendations(Video song) async {
    if (_isFetchingNextQueue) return;
    _isFetchingNextQueue = true;
    try {
      debugPrint('[Recommendations] Silently fetching next 20 songs for ${song.title}…');
      final candidates = await fetchNextCandidates(
        song.id.value,
        limit: 20,
        title: song.title,
        artist: song.author,
      );

      if (candidates.isNotEmpty) {
        int added = 0;
        for (var track in candidates) {
          if (!_playlist.any((item) => item.id.value == track.id.value)) {
            _playlist.add(track);
            added++;
          }
        }
        debugPrint('[Queue] Appended $added recommended tracks. Total in queue: ${_playlist.length}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching recommendations: $e');
    } finally {
      _isFetchingNextQueue = false;
    }
  }

  List<Map<String, String>> _downloadedSongs = [];
  bool _isDownloading = false;

  List<Map<String, String>> get downloadedSongs => _downloadedSongs;
  bool get isDownloading => _isDownloading;

  Future<void> loadDownloadedSongs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/downloads.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        _downloadedSongs = jsonList.map((e) => Map<String, String>.from(e)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading downloaded songs: $e');
    }
  }

  Future<bool> downloadSong(Video song) async {
    _isDownloading = true;
    notifyListeners();

    try {
      final client = http.Client();
      http.StreamedResponse? response;

      // 1. Primary: Direct on-device stream URL candidates
      try {
        final candidates = await _resolveStreamCandidates(song.id.value);
        for (final candidate in candidates) {
          try {
            final request = http.Request('GET', Uri.parse(candidate.url));
            final res = await client.send(request).timeout(const Duration(seconds: 25));
            if (res.statusCode == 200) {
              response = res;
              break;
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[Download] Direct URL error: $e');
      }

      // 2. Fallback 1: Backend /stream_url
      if (response == null || response.statusCode != 200) {
        try {
          final streamUrl = await _fetchStreamUrl(song.id.value);
          if (streamUrl != null) {
            final request = http.Request('GET', Uri.parse(streamUrl));
            request.headers.addAll(_ytHeaders);
            response = await client.send(request).timeout(const Duration(seconds: 25));
          }
        } catch (e) {
          debugPrint('[Download] Backend streamUrl error: $e');
        }
      }

      // 3. Fallback 2: Backend proxy stream
      if (response == null || response.statusCode != 200) {
        try {
          final proxyUri = ApiConfig.streamProxyUri(song.id.value);
          final request = http.Request('GET', proxyUri);
          response = await client.send(request).timeout(const Duration(seconds: 25));
        } catch (e) {
          debugPrint('[Download] Proxy error: $e');
        }
      }

      if (response != null && response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/${song.id.value}.m4a';
        final file = File(filePath);
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();

        final songInfo = {
          'id': song.id.value,
          'title': song.title,
          'author': song.author,
          'thumbnail': song.thumbnails.highResUrl,
          'localPath': filePath,
        };

        _downloadedSongs.removeWhere((item) => item['id'] == song.id.value);
        _downloadedSongs.add(songInfo);

        final jsonFile = File('${dir.path}/downloads.json');
        await jsonFile.writeAsString(json.encode(_downloadedSongs));

        debugPrint('Successfully downloaded song to $filePath');
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error downloading song: $e');
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
    return false;
  }

  Future<void> deleteDownloadedSong(String videoId) async {
    try {
      final item = _downloadedSongs.firstWhere((s) => s['id'] == videoId, orElse: () => {});
      if (item.isNotEmpty && item['localPath'] != null) {
        final file = File(item['localPath']!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _downloadedSongs.removeWhere((s) => s['id'] == videoId);
      final dir = await getApplicationDocumentsDirectory();
      final jsonFile = File('${dir.path}/downloads.json');
      await jsonFile.writeAsString(json.encode(_downloadedSongs));
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting downloaded song: $e');
    }
  }

  Future<void> playDownloadedSong(Map<String, String> songData) async {
    _isLoading = true;

    // Load ALL downloaded songs into queue so Next and Prev work seamlessly!
    _playlist = _downloadedSongs.map((item) => Video(
      VideoId(item['id']!),
      item['title'] ?? 'Unknown Title',
      item['author'] ?? 'Unknown Artist',
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      null,
      ThumbnailSet(item['id']!),
      null,
      Engagement(0, null, null),
      false,
    )).toList();

    _currentIndex = _downloadedSongs.indexWhere((item) => item['id'] == songData['id']);
    if (_currentIndex == -1) _currentIndex = 0;
    if (_playlist.isNotEmpty) {
      await playSong(_playlist[_currentIndex], updateQueue: false);
    }
  }

  Future<void> playHistorySong(Map<String, String> songData) async {
    final history = PreferencesService().listeningHistory;
    _playlist = history.map((item) => Video(
      VideoId(item['id'] ?? ''),
      item['title'] ?? 'Unknown Title',
      item['author'] ?? 'Unknown Artist',
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      null,
      ThumbnailSet(item['id'] ?? ''),
      null,
      Engagement(0, null, null),
      false,
    )).toList();

    _currentIndex = history.indexWhere((item) => item['id'] == songData['id']);
    if (_currentIndex == -1) _currentIndex = 0;
    if (_playlist.isNotEmpty) {
      await playSong(_playlist[_currentIndex], updateQueue: false);
    }
  }

  Future<int> getTotalDownloadedBytes() async {
    int total = 0;
    for (final song in _downloadedSongs) {
      if (song['localPath'] != null) {
        try {
          final file = File(song['localPath']!);
          if (await file.exists()) {
            total += await file.length();
          }
        } catch (_) {}
      }
    }
    return total;
  }

  Future<int> getDownloadedSongSize(String videoId) async {
    final s = _downloadedSongs.firstWhere((item) => item['id'] == videoId, orElse: () => {});
    if (s.isNotEmpty && s['localPath'] != null) {
      try {
        final f = File(s['localPath']!);
        if (await f.exists()) {
          return await f.length();
        }
      } catch (_) {}
    }
    return 0;
  }

  Future<void> seek(Duration position) async {
    if (kIsWeb) {
      WebPlayerBridge.seek(position);
      notifyListeners();
      return;
    }
    await _audioPlayer.seek(position);
  }

  void togglePlayPause() {
    if (kIsWeb) {
      if (WebPlayerBridge.isPlaying) {
        WebPlayerBridge.pause();
      } else {
        WebPlayerBridge.resume();
      }
      notifyListeners();
      return;
    }
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
    notifyListeners();
  }
}
