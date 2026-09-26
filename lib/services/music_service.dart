import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:palette_generator/palette_generator.dart';
import 'api_config.dart';
import 'preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_session/audio_session.dart';
import 'web_player_bridge.dart';
import 'canonical_song_dedup.dart';
import 'youtube_music_client.dart';
import 'album_color_deriver.dart';

enum SearchSuggestionType { artist, song, album, history, query }

class SearchSuggestion {
  final String text;
  final String subtitle;
  final SearchSuggestionType type;

  const SearchSuggestion({
    required this.text,
    required this.subtitle,
    required this.type,
  });
}

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
    if (!kIsWeb) {
      _initAudioSession();
    }
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
  bool _hasRepeatedOnce = false;
  List<Map<String, String>> _likedSongs = [];
  List<Map<String, dynamic>> _customPlaylists = [];

  // Bidirectional Shuffle History Stack
  final List<int> _shuffleHistory = [];
  int _shuffleHistoryPointer = -1;
  bool _isGeneratingQueue = false;

  // Multi-artist playlist recommendation state
  List<String> _seedPlaylistArtists = [];
  int _playlistArtistRecommendationOffset = 0;

  String? _cachedLyrics;
  String? _cachedLyricsSongId;
  bool _isFetchingLyrics = false;

  // Palette Extraction
  Color _dominantColor = const Color(0xFF1E1E2C);
  Color _vibrantColor = const Color(0xFFFA2D48);
  Color _darkVibrantColor = const Color(0xFF101018);

  // Sleep Timer (DateTime-based: immune to lock-screen throttling)
  DateTime? _sleepEndTime;
  Timer? _sleepCountdownTimer;
  bool _stopAtEndOfTrack = false;
  bool _wasInterruptedBySystem = false;

  // Crossfade & Volume Fading Engine
  bool _isCrossfading = false;
  StreamSubscription<Duration>? _positionCrossfadeSub;

  Video? get currentSong => _currentSong;
  List<Video> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isShuffle => _isShuffle;
  LoopMode get loopMode => _loopMode;
  List<Map<String, String>> get likedSongs => _likedSongs;
  List<Map<String, dynamic>> get customPlaylists => _customPlaylists;
  AudioPlayer get audioPlayer => _audioPlayer;
  bool get isCrossfading => _isCrossfading;

  bool get isPlaying => kIsWeb ? WebPlayerBridge.isPlaying : _audioPlayer.playing;
  Duration get position => kIsWeb ? WebPlayerBridge.currentPosition : _audioPlayer.position;
  Duration? get duration => kIsWeb ? WebPlayerBridge.currentDuration : _audioPlayer.duration;
  Stream<Duration> get positionStream => kIsWeb ? WebPlayerBridge.positionStream : _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => kIsWeb ? WebPlayerBridge.durationStream : _audioPlayer.durationStream;

  String? get cachedLyrics => _cachedLyrics;
  bool get isFetchingLyrics => _isFetchingLyrics;

  Color get dominantColor => _dominantColor;
  Color get vibrantColor => _vibrantColor;
  Color get darkVibrantColor => _darkVibrantColor;

  bool get isSleepTimerActive =>
      (_sleepEndTime != null && _sleepEndTime!.isAfter(DateTime.now())) || _stopAtEndOfTrack;

  Duration? get sleepRemaining {
    if (_sleepEndTime == null) return null;
    final diff = _sleepEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get stopAtEndOfTrack => _stopAtEndOfTrack;

  String get sleepTimerLabel {
    if (_stopAtEndOfTrack) return 'End of Track';
    final rem = sleepRemaining;
    if (rem != null) {
      final mins = rem.inMinutes;
      final secs = rem.inSeconds.remainder(60).toString().padLeft(2, '0');
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
      final songCtx = CanonicalSongDedup.extractSongContext(song.title, song.author);
      final cleanTitle = (songCtx['title'] as String?)?.isNotEmpty == true
          ? songCtx['title'] as String
          : _cleanSongTitle(song.title);
      final cleanArtist = (songCtx['artist'] as String?)?.isNotEmpty == true
          ? songCtx['artist'] as String
          : _cleanArtistName(song.author);
      final contextKeywords = (songCtx['contextKeywords'] as List<String>?) ?? [];
      final durationSec = song.duration?.inSeconds;

      // High-precision language detection:
      // 1. Check registered song language (from JioSaavn or Spotify import)
      String? targetLang = CanonicalSongDedup.getSongLanguage(song.id.value);
      // 2. Check title (native Unicode script or keywords)
      targetLang ??= CanonicalSongDedup.detectLanguage(song.title);
      // 3. Check author / channel
      targetLang ??= CanonicalSongDedup.detectLanguage(song.author);
      // 4. Check user's preferred primary language if available and not generic English
      if (targetLang == null && PreferencesService().preferredLanguages.isNotEmpty) {
        final pref = PreferencesService().preferredLanguages.first.toLowerCase();
        if (pref != 'english') {
          targetLang = pref;
        }
      }

      // Tier 1: Cloudflare Edge Worker Lyrics Proxy (Zero CORS blocks, ~200ms latency, language & script scored)
      if (cleanTitle.isNotEmpty) {
        try {
          final edgeUri = ApiConfig.cloudflareLyricsUri(
            cleanTitle,
            artist: cleanArtist,
            lang: targetLang,
            duration: durationSec,
          );
          final res = await http.get(edgeUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data is Map && data['status'] == 'ok' && data['data'] != null) {
              final d = data['data'];
              final lyricsText = (d['syncedLyrics'] as String?)?.trim();
              final plainText = (d['plainLyrics'] as String?)?.trim();
              if (lyricsText != null && lyricsText.isNotEmpty) {
                _cachedLyrics = lyricsText;
                return;
              } else if (plainText != null && plainText.isNotEmpty) {
                _cachedLyrics = plainText;
                return;
              }
            }
          }
        } catch (_) {}
      }

      // Tier 2: Render Backend Lyrics Proxy Fallback (language & script scored)
      if (cleanTitle.isNotEmpty) {
        try {
          final backendUri = ApiConfig.backendLyricsUri(
            cleanTitle,
            artist: cleanArtist,
            lang: targetLang,
            duration: durationSec,
          );
          final res = await http.get(backendUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data is Map && data['status'] == 'ok' && data['data'] != null) {
              final d = data['data'];
              final lyricsText = (d['syncedLyrics'] as String?)?.trim();
              final plainText = (d['plainLyrics'] as String?)?.trim();
              if (lyricsText != null && lyricsText.isNotEmpty) {
                _cachedLyrics = lyricsText;
                return;
              } else if (plainText != null && plainText.isNotEmpty) {
                _cachedLyrics = plainText;
                return;
              }
            }
          }
        } catch (_) {}
      }

      // Tier 3: Direct lrclib.net fallback with client-side script, context & language validation
      final safeHeaders = {'Accept': 'application/json'};
      final List<dynamic> candidatePool = [];

      // 3A: Language-augmented search if targetLang is known
      if (cleanTitle.isNotEmpty && targetLang != null && targetLang.isNotEmpty) {
        try {
          final urlLang = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $targetLang")}');
          final resLang = await http.get(urlLang, headers: safeHeaders).timeout(const Duration(seconds: 5));
          if (resLang.statusCode == 200) {
            final list = json.decode(resLang.body);
            if (list is List) candidatePool.addAll(list);
          }
        } catch (_) {}
      }

      // 3B: Clean Title + Context Keyword search (e.g. movie/album name like "Devara")
      if (cleanTitle.isNotEmpty && contextKeywords.isNotEmpty) {
        try {
          final urlCtx = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle ${contextKeywords.first}")}');
          final resCtx = await http.get(urlCtx, headers: safeHeaders).timeout(const Duration(seconds: 5));
          if (resCtx.statusCode == 200) {
            final list = json.decode(resCtx.body);
            if (list is List) candidatePool.addAll(list);
          }
        } catch (_) {}
      }

      // 3C: Clean Title + Clean Artist search
      if (cleanTitle.isNotEmpty && cleanArtist.isNotEmpty) {
        try {
          final url1 = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $cleanArtist")}');
          final res1 = await http.get(url1, headers: safeHeaders).timeout(const Duration(seconds: 5));
          if (res1.statusCode == 200) {
            final list = json.decode(res1.body);
            if (list is List) candidatePool.addAll(list);
          }
        } catch (_) {}
      }

      // 3D: Title-only search
      if (cleanTitle.isNotEmpty) {
        try {
          final url2 = Uri.parse('https://lrclib.net/api/search?track_name=${Uri.encodeComponent(cleanTitle)}');
          final res2 = await http.get(url2, headers: safeHeaders).timeout(const Duration(seconds: 5));
          if (res2.statusCode == 200) {
            final list = json.decode(res2.body);
            if (list is List) candidatePool.addAll(list);
          }
        } catch (_) {}
      }

      // Score all candidates through CanonicalSongDedup with context keywords & strict filtering
      final seenIds = <dynamic>{};
      Map<String, dynamic>? bestCandidate;
      int bestScore = 120; // Strict minimum threshold

      for (final item in candidatePool) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'];
        if (id != null && seenIds.contains(id)) continue;
        if (id != null) seenIds.add(id);

        final score = CanonicalSongDedup.scoreLyricsCandidate(
          targetLang: targetLang,
          targetTitle: cleanTitle,
          targetArtist: cleanArtist,
          targetDuration: durationSec,
          candidate: map,
          contextKeywords: contextKeywords,
        );

        if (score > bestScore) {
          bestScore = score;
          bestCandidate = map;
        }
      }

      if (bestCandidate != null) {
        final synced = (bestCandidate['syncedLyrics'] as String?)?.trim();
        final plain = (bestCandidate['plainLyrics'] as String?)?.trim();
        _cachedLyrics = (synced != null && synced.isNotEmpty)
            ? synced
            : (plain != null && plain.isNotEmpty ? plain : 'No lyrics available.');
      } else {
        _cachedLyrics = 'No lyrics found for "$cleanTitle".';
      }
    } catch (e) {
      _cachedLyrics = 'Lyrics temporarily unavailable.';
    } finally {
      _isFetchingLyrics = false;
      notifyListeners();
    }
  }

  static final Map<String, String> _artworkMap = {};
  static final Map<String, String> _webStreamUrls = {};

  static void cacheWebStreamUrl(String videoId, String streamUrl) {
    if (videoId.isEmpty || streamUrl.isEmpty) return;
    _webStreamUrls[videoId] = streamUrl;
    if (kIsWeb) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('web_stream_$videoId', streamUrl);
      }).catchError((_) {});
    }
  }

  static String? getCachedWebStreamUrl(String videoId) {
    return _webStreamUrls[videoId];
  }

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
      final prefs = PreferencesService();
      final primaryLang = prefs.preferredLanguages.isNotEmpty ? prefs.preferredLanguages.first : 'Telugu';
      final results = await Future.wait([
        searchSongs('$primaryLang Top Hits'),
        searchSongs('$primaryLang Trending'),
      ]);
      _preloadedTopChartsIndia = results[0];
      _preloadedTrending = results[1];
      _hasPreloadedHome = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Preload] Home data preload: $e');
    }
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(0.3);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _wasInterruptedBySystem = true;
              _audioPlayer.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              if (_wasInterruptedBySystem) {
                _wasInterruptedBySystem = false;
                _audioPlayer.play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });
    } catch (e) {
      debugPrint('[AudioSession] Error setting up session: $e');
    }
  }

  void _initAudioPlayer() {
    if (kIsWeb) {
      WebPlayerBridge.init();
      WebPlayerBridge.onTrackEnded.listen((_) async {
        if (_isTransitioning || _isCrossfading) return;
        _isTransitioning = true;
        try {
          if (_loopMode == LoopMode.one && _currentSong != null) {
            if (!_hasRepeatedOnce) {
              _hasRepeatedOnce = true;
              debugPrint('[WebPlayer] LoopMode.one active: repeating track once…');
              WebPlayerBridge.seek(Duration.zero);
              WebPlayerBridge.resume();
            } else {
              debugPrint('[WebPlayer] Single repeat complete. Resetting repeat mode and advancing…');
              _hasRepeatedOnce = false;
              _loopMode = LoopMode.off;
              notifyListeners();
              await nextSong();
            }
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
      WebPlayerBridge.onError.listen((code) async {
        debugPrint('[WebPlayer] Error $code encountered. Handling recovery…');
        _isLoading = false;
        notifyListeners();
        if (_playlist.length > 1 && _currentIndex + 1 < _playlist.length) {
          await Future.delayed(const Duration(milliseconds: 500));
          await nextSong();
        }
      });
    }

    _audioPlayer.playerStateStream.listen((state) async {
      notifyListeners();
      if (state.processingState == ProcessingState.completed) {
        if (_isTransitioning || _isCrossfading) return;
        _isTransitioning = true;
        try {
          if (_loopMode == LoopMode.one) {
            if (!_hasRepeatedOnce) {
              _hasRepeatedOnce = true;
              debugPrint('[AudioPlayer] LoopMode.one active: repeating current track once…');
              await _audioPlayer.seek(Duration.zero);
              await _audioPlayer.play();
            } else {
              debugPrint('[AudioPlayer] Track completed its single repeat. Resetting repeat and advancing…');
              _hasRepeatedOnce = false;
              _loopMode = LoopMode.off;
              notifyListeners();
              await nextSong();
            }
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

    _positionCrossfadeSub?.cancel();
    _positionCrossfadeSub = positionStream.listen((pos) {
      _checkCrossfadeTrigger(pos);
    });

    loadLikedSongs();
    loadCustomPlaylists();
  }

  int _fadeSession = 0;

  void _cancelActiveFade() {
    _fadeSession++;
    _isCrossfading = false;
  }

  Future<void> _setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 1.0);
    if (kIsWeb) {
      WebPlayerBridge.setVolume(clamped);
    } else {
      try {
        await _audioPlayer.setVolume(clamped);
      } catch (_) {}
    }
  }

  Future<void> _fadeVolume({
    required double from,
    required double to,
    required Duration duration,
  }) async {
    final session = ++_fadeSession;
    const int steps = 18;
    final int stepMs = (duration.inMilliseconds / steps).clamp(15, 120).toInt();
    try {
      for (int i = 0; i <= steps; i++) {
        if (_fadeSession != session) return;
        final double progress = i / steps;
        final double currentVol = from + (to - from) * progress;
        await _setVolume(currentVol);
        await Future.delayed(Duration(milliseconds: stepMs));
      }
    } catch (_) {}
    if (_fadeSession == session && to >= 0.9) {
      await _setVolume(1.0);
    }
  }

  Future<void> fadeInCurrentSong({Duration duration = const Duration(milliseconds: 900)}) async {
    await _fadeVolume(from: 0.0, to: 1.0, duration: duration);
  }

  void _checkCrossfadeTrigger(Duration pos) {
    if (_isCrossfading || _isTransitioning || _isLoading || _currentSong == null) return;
    if (_loopMode == LoopMode.one) return;
    final prefs = PreferencesService();
    if (!prefs.crossfadeEnabled) return;

    final dur = duration;
    if (dur == null || dur.inSeconds <= 15) return;

    // Only crossfade if there is a next track in queue or one can be preloaded
    if (_playlist.isEmpty) return;
    if (!_isShuffle && _currentIndex + 1 >= _playlist.length) {
      _checkAndPreloadNextQueue();
      if (_currentIndex + 1 >= _playlist.length) return;
    }

    int crossfadeSec = prefs.crossfadeSeconds;
    if (prefs.smartCrossfadeEnabled) {
      // Smart Sync: Synchronize crossfade duration to 4 musical bars based on BPM
      final profile = prefs.audioProfile;
      if (profile.avgTempo > 60 && profile.avgTempo < 200) {
        final beatSec = 60.0 / profile.avgTempo;
        // 4 bars of 4/4 time = 16 beats
        crossfadeSec = (16 * beatSec).clamp(3.0, 9.0).round();
      } else if (dur.inMinutes >= 4 && crossfadeSec < 6) {
        crossfadeSec = (crossfadeSec + 2).clamp(1, 10);
      } else if (dur.inMinutes <= 2 && crossfadeSec > 4) {
        crossfadeSec = (crossfadeSec - 1).clamp(2, 6);
      }
    }

    final remaining = dur - pos;
    // Proactively pre-resolve upcoming track 5 seconds before crossfade initiates so network delay is eliminated
    if (remaining <= Duration(seconds: crossfadeSec + 5) && remaining > Duration(seconds: crossfadeSec)) {
      if (_currentIndex + 1 < _playlist.length) {
        _prewarmSingleTrack(_playlist[_currentIndex + 1]);
      }
    }

    if (remaining <= Duration(seconds: crossfadeSec) && remaining > const Duration(milliseconds: 600)) {
      _triggerCrossfade(Duration(seconds: crossfadeSec));
    }
  }

  Future<void> _triggerCrossfade(Duration crossfadeDuration) async {
    if (_isCrossfading || _isTransitioning) return;
    _isCrossfading = true;
    debugPrint('[Crossfade] Starting ${crossfadeDuration.inSeconds}s crossfade merge…');
    try {
      if (kIsWeb) {
        // On Web, invoke nextSong(isCrossfade: true) immediately so dilseCrossfade overlaps Deck A & Deck B in real time
        await nextSong(isCrossfade: true);
      } else {
        final fadeDownMs = (crossfadeDuration.inMilliseconds * 0.75).toInt().clamp(500, 6000);
        await _fadeVolume(
          from: 1.0,
          to: 0.05,
          duration: Duration(milliseconds: fadeDownMs),
        );
        if (!_isCrossfading) return;
        await nextSong(isCrossfade: true);
      }
    } catch (e) {
      debugPrint('[Crossfade] Transition error: $e');
      await _setVolume(1.0);
    } finally {
      _isCrossfading = false;
    }
  }

  Future<void> _startPlaybackWithFade({
    required bool isCrossfade,
    required Future<void> Function() playAction,
  }) async {
    final prefs = PreferencesService();
    final shouldFade = isCrossfade || prefs.fadeInOnStartEnabled;

    if (!shouldFade) {
      await _setVolume(1.0);
      unawaited(playAction());
      return;
    }

    // Never mute to 0.0 because Android hardware AudioTrack can initialize muted.
    // Start from 0.3 so it is audible from the first millisecond and smoothly reaches 1.0.
    await _setVolume(0.3);
    unawaited(playAction());

    unawaited(() async {
      try {
        await _fadeVolume(
          from: 0.3,
          to: 1.0,
          duration: isCrossfade ? const Duration(milliseconds: 1000) : const Duration(milliseconds: 600),
        );
      } catch (_) {} finally {
        await _setVolume(1.0);
      }
    }());
  }

  Future<void> loadLikedSongs() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('liked_songs_web');
        if (raw != null && raw.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(raw);
          _likedSongs = jsonList.map((e) => Map<String, String>.from(e)).toList();
          _restoreLikedSongsMemoryCaches();
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
        _restoreLikedSongsMemoryCaches();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading liked songs: $e');
    }
  }

  void _restoreLikedSongsMemoryCaches() {
    for (final item in _likedSongs) {
      final id = item['id'] ?? '';
      final thumb = item['thumbnail'] ?? '';
      final stream = item['streamUrl'] ?? '';
      if (id.isNotEmpty) {
        if (thumb.isNotEmpty && !_artworkMap.containsKey(id)) _artworkMap[id] = thumb;
        if (stream.isNotEmpty && !_webStreamUrls.containsKey(id)) _webStreamUrls[id] = stream;
      }
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
        'streamUrl': _webStreamUrls[song.id.value] ?? '',
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
          _restorePlaylistMemoryCaches();
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
        _restorePlaylistMemoryCaches();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading custom playlists: $e');
    }
  }

  void _restorePlaylistMemoryCaches() {
    for (final playlist in _customPlaylists) {
      final songs = playlist['songs'] as List<dynamic>? ?? [];
      for (final s in songs) {
        if (s is Map<String, dynamic>) {
          final id = s['id'] as String? ?? '';
          final thumb = s['thumbnail'] as String? ?? '';
          final streamUrl = s['streamUrl'] as String? ?? '';
          final lang = s['language'] as String? ?? '';
          if (id.isNotEmpty) {
            if (thumb.isNotEmpty && !_artworkMap.containsKey(id)) {
              _artworkMap[id] = thumb;
            }
            if (streamUrl.isNotEmpty && !_webStreamUrls.containsKey(id)) {
              _webStreamUrls[id] = streamUrl;
            }
            if (lang.isNotEmpty) {
              CanonicalSongDedup.registerSongLanguage(id, lang);
            }
          }
        }
      }
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
    final playlistId = '${DateTime.now().millisecondsSinceEpoch}_${_customPlaylists.length}';
    return createPlaylistWithId(playlistId, name);
  }

  String createPlaylistWithId(String playlistId, String name) {
    // If playlist with this ID already exists, return existing
    final existingIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (existingIndex != -1) {
      return playlistId;
    }
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
    addSongsToPlaylist(playlistId, [song]);
  }

  /// High-performance batch addition of songs to avoid repeated disk serialization
  void addSongsToPlaylist(String playlistId, List<Video> songs, {bool commit = true}) {
    if (songs.isEmpty) return;
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex != -1) {
      final existingSongs = List<Map<String, dynamic>>.from(_customPlaylists[playlistIndex]['songs'] ?? []);
      final existingIds = existingSongs.map((s) => s['id'] as String).toSet();
      bool modified = false;

      for (final song in songs) {
        if (!existingIds.contains(song.id.value)) {
          existingIds.add(song.id.value);
          existingSongs.add({
            'id': song.id.value,
            'title': song.title,
            'author': song.author,
            'thumbnail': getHdThumbnail(song.id.value),
            'streamUrl': _webStreamUrls[song.id.value] ?? '',
          });
          modified = true;
        }
      }

      if (modified) {
        _customPlaylists[playlistIndex]['songs'] = existingSongs;
        if (commit) {
          saveCustomPlaylists();
          notifyListeners();
        }
      }
    }
  }

  /// Sets or updates all songs in a playlist, preserving exact order and updating storage
  void setPlaylistSongs(String playlistId, List<Video> songs, {bool commit = true}) {
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex != -1) {
      final songMaps = songs.map((song) => {
        'id': song.id.value,
        'title': song.title,
        'author': song.author,
        'thumbnail': getHdThumbnail(song.id.value),
        'streamUrl': _webStreamUrls[song.id.value] ?? '',
      }).toList();

      _customPlaylists[playlistIndex]['songs'] = songMaps;
      if (commit) {
        saveCustomPlaylists();
        notifyListeners();
      }
    }
  }

  Future<void> reorderPlaylistSongs(String playlistId, int oldIndex, int newIndex) async {
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex == -1) return;

    final songs = List<Map<String, dynamic>>.from(_customPlaylists[playlistIndex]['songs'] ?? []);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 || oldIndex >= songs.length || newIndex < 0 || newIndex >= songs.length) return;

    final item = songs.removeAt(oldIndex);
    songs.insert(newIndex, item);

    _customPlaylists[playlistIndex]['songs'] = songs;
    await saveCustomPlaylists();
    notifyListeners();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex == -1) return;

    final songs = List<Map<String, dynamic>>.from(_customPlaylists[playlistIndex]['songs'] ?? []);
    songs.removeWhere((s) => s['id'] == songId);

    _customPlaylists[playlistIndex]['songs'] = songs;
    await saveCustomPlaylists();
    notifyListeners();
  }

  bool isLiked(String videoId) {
    return _likedSongs.any((s) => s['id'] == videoId);
  }

  bool isDownloaded(String videoId) {
    return _downloadedSongs.any((s) => s['id'] == videoId);
  }

  void playNext(Video song) {
    if (_playlist.isEmpty) {
      playSong(song);
      return;
    }
    final insertIndex = (_currentIndex + 1).clamp(0, _playlist.length);
    _playlist.insert(insertIndex, song);
    notifyListeners();
  }

  void addToQueue(Video song) {
    if (_playlist.isEmpty) {
      playSong(song);
      return;
    }
    _playlist.add(song);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 || oldIndex >= _playlist.length || newIndex < 0 || newIndex >= _playlist.length) return;
    final currentSong = _currentSong;
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);

    if (currentSong != null) {
      final newCurrent = _playlist.indexWhere((s) => s.id == currentSong.id);
      if (newCurrent != -1) _currentIndex = newCurrent;
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final currentSong = _currentSong;
    _playlist.removeAt(index);
    if (currentSong != null) {
      final newCurrent = _playlist.indexWhere((s) => s.id == currentSong.id);
      if (newCurrent != -1) {
        _currentIndex = newCurrent;
      } else if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.isNotEmpty ? _playlist.length - 1 : 0;
      }
    }
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;
    final playlistIndex = _customPlaylists.indexWhere((p) => p['id'] == playlistId);
    if (playlistIndex != -1) {
      _customPlaylists[playlistIndex]['name'] = cleanName;
      await saveCustomPlaylists();
      notifyListeners();
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

    for (final item in songs) {
      final id = (item['id'] as String?) ?? '';
      final thumb = (item['thumbnail'] as String?) ?? '';
      final stream = (item['streamUrl'] as String?) ?? '';
      if (id.isNotEmpty) {
        if (thumb.isNotEmpty) _artworkMap[id] = thumb;
        if (stream.isNotEmpty) _webStreamUrls[id] = stream;
      }
    }

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
    
    _seedPlaylistArtists = _extractArtistsFromSongs(_playlist);
    _playlistArtistRecommendationOffset = 0;

    // Proactively pre-warm upcoming tracks in background so instant rapid skips never buffer!
    _prewarmUpcomingTracks(_currentIndex, count: 4);

    await playSong(_playlist[_currentIndex], updateQueue: false);
  }

  void _prewarmUpcomingTracks(int fromIndex, {int count = 3}) {
    if (_playlist.isEmpty) return;
    final toIndex = (fromIndex + count).clamp(0, _playlist.length);
    for (int i = fromIndex; i < toIndex; i++) {
      final track = _playlist[i];
      final trackId = track.id.value;
      if (_webStreamUrls[trackId] != null && _webStreamUrls[trackId]!.isNotEmpty) {
        continue;
      }
      _prewarmSingleTrack(track);
    }
  }

  Future<void> _prewarmSingleTrack(Video track) async {
    final trackId = track.id.value;
    if (_webStreamUrls[trackId] != null && _webStreamUrls[trackId]!.isNotEmpty) return;
    try {
      final cleanT = CanonicalSongDedup.cleanTitle(track.title);
      final cleanA = CanonicalSongDedup.cleanArtist(track.author);
      final q = cleanA.isNotEmpty ? '$cleanT $cleanA' : cleanT;
      if (cleanT.isNotEmpty) {
        final jioUri = ApiConfig.jioSearchUri(q, limit: 5);
        final resp = await http.get(jioUri).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final List<dynamic> list = json.decode(resp.body);
          for (final item in list) {
            final itemTitle = item['title'] as String? ?? '';
            final itemArtist = item['author'] as String? ?? '';
            final itemStream = item['streamUrl'] as String? ?? '';
            final itemThumb = item['thumbnail'] as String? ?? '';
            if (itemStream.isEmpty) continue;
            if (_isCoverOrKaraokeTrack(itemTitle, itemArtist)) continue;

            final isMatch = CanonicalSongDedup.areDuplicateSongs(
              titleA: track.title,
              artistA: track.author,
              titleB: itemTitle,
              artistB: itemArtist,
            );

            if (isMatch) {
              _webStreamUrls[trackId] = itemStream;
              if (itemThumb.isNotEmpty && !_artworkMap.containsKey(trackId)) {
                _artworkMap[trackId] = itemThumb;
              }
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> playLikedSong(Map<String, String> songData) async {
    for (final item in _likedSongs) {
      final id = item['id'] ?? '';
      final thumb = item['thumbnail'] ?? '';
      final stream = item['streamUrl'] ?? '';
      if (id.isNotEmpty) {
        if (thumb.isNotEmpty) _artworkMap[id] = thumb;
        if (stream.isNotEmpty) _webStreamUrls[id] = stream;
      }
    }

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
      _seedPlaylistArtists = _extractArtistsFromSongs(_playlist);
      _playlistArtistRecommendationOffset = 0;
      _prewarmUpcomingTracks(_currentIndex, count: 4);
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
    _shuffleHistory.clear();
    _shuffleHistoryPointer = -1;
    if (_isShuffle && _currentIndex >= 0 && _currentIndex < _playlist.length) {
      _shuffleHistory.add(_currentIndex);
      _shuffleHistoryPointer = 0;
    }
    if (!kIsWeb) {
      _audioPlayer.setShuffleModeEnabled(_isShuffle);
    }
    notifyListeners();
  }

  void toggleRepeat() {
    _hasRepeatedOnce = false;
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    if (!kIsWeb) {
      // Keep just_audio loop mode at off so track completion events are dispatched to Dart,
      // allowing us to repeat the track once and advance cleanly without infinite loops.
      _audioPlayer.setLoopMode(LoopMode.off);
    }
    notifyListeners();
  }

  static bool _isCoverOrKaraokeTrack(String title, String author, {String? query}) {
    final lowerTitle = title.toLowerCase();
    final lowerAuthor = author.toLowerCase();
    final q = (query ?? '').toLowerCase();

    // If the user explicitly searched for karaoke, cover, or instrumental, allow it
    if (q.contains('karaoke') ||
        q.contains('instrumental') ||
        q.contains('tribute') ||
        q.contains('backing track') ||
        q.contains('cover')) {
      return false;
    }

    const badKeywords = [
      'karaoke',
      'originally performed',
      'in the style of',
      'tribute to',
      'tribute version',
      'tribute band',
      'cover version',
      'backing track',
      'piano version',
      'guitar backing',
      'sing-along',
      'acoustic tribute',
      'zzang',
      'luxebeats',
      'sweet strings',
      'boostereo',
      'shadow tower',
      'party hits band',
      'karaoke party',
      'the hit crew',
      'the covers',
    ];

    for (final bad in badKeywords) {
      if (lowerTitle.contains(bad) || lowerAuthor.contains(bad)) {
        return true;
      }
    }
    return false;
  }

  /// 3-Tier Source Cascade Search:
  /// Tier 1: JioSaavn (320kbps studio master audio)
  /// Tier 2: YouTube Music (Clean official releases, no video sketches)
  /// Tier 3: YouTube Standard (Safety net fallback)
  /// Guaranteed Zero Cross-Source Duplicates via CanonicalSongDedup.
  List<Video> _parseJioResults(String body, {String? query}) {
    final List<Video> list = [];
    try {
      final List<dynamic> jsonList = json.decode(body);
      for (var item in jsonList) {
        final songId = item['id'] as String? ?? '';
        if (songId.isEmpty) continue;
        final title = item['title'] as String? ?? 'Unknown Title';
        final author = item['author'] as String? ?? 'DilSe Music';
        final durationSec = item['duration'] != null ? int.tryParse(item['duration'].toString()) : null;
        final duration = durationSec != null ? Duration(seconds: durationSec) : null;
        final artwork = item['thumbnail'] as String? ?? '';
        final streamUrl = item['streamUrl'] as String? ?? '';

        if (_isCoverOrKaraokeTrack(title, author, query: query)) {
          continue;
        }

        final vidString = songId.length >= 11 ? songId.substring(0, 11) : songId.padRight(11, '0');

        if (artwork.isNotEmpty) {
          _artworkMap[songId] = artwork;
          _artworkMap[vidString] = artwork;
        }
        if (streamUrl.isNotEmpty) {
          _webStreamUrls[songId] = streamUrl;
          _webStreamUrls[vidString] = streamUrl;
        }
        final lang = item['language'] as String? ?? '';
        if (lang.isNotEmpty) {
          CanonicalSongDedup.registerSongLanguage(songId, lang);
          CanonicalSongDedup.registerSongLanguage(vidString, lang);
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

  /// 3-Tier Multi-Engine Search with JioSaavn Studio-First Priority:
  /// Tier 1: JioSaavn (320kbps studio releases with pristine album covers)
  /// Tier 2: YouTube Music (Official studio releases via InnerTube)
  /// Tier 3: YouTube Standard (Safety net fallback only if Jio + YTM have < 8 results)
  /// Guaranteed Zero Cross-Source Duplicates & 100% Genuine Audio via CanonicalSongDedup.
  Future<List<Video>> searchSongs(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];

    try {
      // 1. Tier 1: JioSaavn search (highest priority for 320k studio quality)
      final jioFuture = http
          .get(ApiConfig.jioSearchUri(query, limit: 25))
          .timeout(const Duration(seconds: 8));

      // 2. Tier 2: YouTube Music Search (official releases)
      final ytmFuture = YouTubeMusicClient().searchSongs(query, limit: 15);

      final jioResponse = await jioFuture.catchError((_) => http.Response('[]', 500));
      List<Video> jioResults = jioResponse.statusCode == 200 ? _parseJioResults(jioResponse.body, query: query) : [];

      // Await Tier 2 in parallel
      final ytmResults = await ytmFuture.catchError((_) => <Video>[]);

      // Fallback: If JioSaavn from edge worker returned fewer than 8 genuine tracks, query the Render Jio backend
      if (jioResults.length < 8) {
        try {
          final backendJioResp = await http
              .get(ApiConfig.jioBackendSearchUri(query, limit: 20))
              .timeout(const Duration(seconds: 8))
              .catchError((_) => http.Response('[]', 500));
          if (backendJioResp.statusCode == 200) {
            final fallbackList = _parseJioResults(backendJioResp.body, query: query);
            if (fallbackList.isNotEmpty) {
              final dedupedFallback = CanonicalSongDedup.deduplicateList(jioResults, fallbackList);
              jioResults = [...jioResults, ...dedupedFallback];
            }
          }
        } catch (_) {}
      }

      // Tier 3: YouTube Standard backend (safety net only if JioSaavn + YTM return fewer than 8 tracks)
      final List<Video> backendResults = [];
      if (jioResults.length + ytmResults.length < 8) {
        final backendResponse = await http
            .get(ApiConfig.searchUri(query, page: page, limit: 15))
            .timeout(const Duration(seconds: 10))
            .catchError((_) => http.Response('[]', 500));

        if (backendResponse.statusCode == 200) {
          try {
            final List<dynamic> jsonList = json.decode(backendResponse.body);
            for (var item in jsonList) {
              final videoId = item['id'] as String;
              final title = item['title'] as String? ?? 'Unknown Title';
              final author = item['author'] as String? ?? 'Unknown Artist';
              final durationSec = item['duration'] != null ? int.tryParse(item['duration'].toString()) : null;
              final duration = durationSec != null ? Duration(seconds: durationSec) : null;

              final video = Video(
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

              // Strict audio validation: drop non-music, speeches, trailers, cricket clips
              if (CanonicalSongDedup.isGenuineSong(video)) {
                backendResults.add(video);
              }
            }
          } catch (_) {}
        }
      }

      // Deduplicate Tier 2 against Tier 1
      final dedupedYtm = CanonicalSongDedup.deduplicateList(jioResults, ytmResults);

      // Deduplicate Tier 3 against JioSaavn + YTM
      final known = <Video>[...jioResults, ...dedupedYtm];
      final dedupedYt = CanonicalSongDedup.deduplicateList(known, backendResults);

      final combined = <Video>[...jioResults, ...dedupedYtm, ...dedupedYt];
      debugPrint('[Studio Search] Returned ${combined.length} songs (${jioResults.length} Jio + ${dedupedYtm.length} YTM + ${dedupedYt.length} YT)');
      return combined;
    } catch (e) {
      debugPrint('[Studio Search] Error: $e');
    }

    return [];
  }

  /// Structured Spotify-grade suggestions (Artist 👤, Song 🎵, History 🕒, Query 🔍)
  Future<List<SearchSuggestion>> fetchEntitySuggestions(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return [];

    final suggestions = <SearchSuggestion>[];
    final qLower = query.toLowerCase().trim();

    // 1. Instant Local Search History (🕒)
    final history = PreferencesService().searchHistory;
    for (final item in history) {
      if (item.toLowerCase().contains(qLower)) {
        suggestions.add(SearchSuggestion(
          text: item,
          subtitle: 'Recent Search',
          type: SearchSuggestionType.history,
        ));
        if (suggestions.length >= 2) break;
      }
    }

    // 2. Instant Local Top Artists (👤)
    final topArtists = PreferencesService().getTopArtists(limit: 10);
    for (final artist in topArtists) {
      if (artist.toLowerCase().contains(qLower)) {
        suggestions.add(SearchSuggestion(
          text: artist,
          subtitle: 'Artist',
          type: SearchSuggestionType.artist,
        ));
        if (suggestions.length >= 4) break;
      }
    }

    // 3. JioSaavn Autocomplete API (clean entity categorization)
    try {
      final response = await http
          .get(ApiConfig.jioSuggestionsUri(query, limit: limit))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        for (var item in jsonList) {
          final text = item.toString().trim();
          if (text.isEmpty || suggestions.any((s) => s.text.toLowerCase() == text.toLowerCase())) {
            continue;
          }

          final isArtist = topArtists.any((a) => a.toLowerCase() == text.toLowerCase());
          suggestions.add(SearchSuggestion(
            text: text,
            subtitle: isArtist ? 'Artist' : 'Song',
            type: isArtist ? SearchSuggestionType.artist : SearchSuggestionType.song,
          ));
          if (suggestions.length >= limit) break;
        }
      }
    } catch (_) {}

    // 4. Fill with YouTube suggestions if still sparse
    if (suggestions.length < limit) {
      try {
        final rawStrings = await fetchSuggestions(query, limit: limit - suggestions.length);
        for (final str in rawStrings) {
          if (!suggestions.any((s) => s.text.toLowerCase() == str.toLowerCase())) {
            suggestions.add(SearchSuggestion(
              text: str,
              subtitle: 'Search',
              type: SearchSuggestionType.query,
            ));
            if (suggestions.length >= limit) break;
          }
        }
      } catch (_) {}
    }

    return suggestions;
  }

  /// Live query suggestions while typing (up to [limit] suggestions)
  Future<List<String>> fetchSuggestions(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return [];

    // 1. Primary: JioSaavn Instant Edge Suggestions (both Mobile and Web)
    try {
      final response = await http
          .get(ApiConfig.jioSuggestionsUri(query, limit: limit))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final list = jsonList.map((e) => e.toString()).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('jioSuggestions error: $e');
    }

    // 2. Secondary fallback
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
      final thumbUrl = getHdThumbnail(videoId);
      final imageUrl = thumbUrl.isNotEmpty ? thumbUrl : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(100, 100),
        maximumColorCount: 12,
      ).timeout(const Duration(seconds: 3));

      // Guard against race condition: discard if song changed while extracting
      if (_currentSong?.id.value != videoId) return;

      final dominant = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? const Color(0xFF1E1E2C);
      final vibrant = palette.vibrantColor?.color ?? palette.lightVibrantColor?.color ?? dominant;
      final darkVibrant = palette.darkVibrantColor?.color ?? palette.darkMutedColor?.color ?? dominant;

      _dominantColor = dominant;
      _vibrantColor = vibrant;
      _darkVibrantColor = darkVibrant;
      AlbumColorDeriver.registerExtractedPalette(videoId, dominant, vibrant, darkVibrant);
      notifyListeners();
    } catch (e) {
      debugPrint('[Palette] Extraction error: $e');
      if (_currentSong != null && _currentSong?.id.value == videoId) {
        final palette = AlbumColorDeriver.getPalette(_currentSong!);
        _dominantColor = palette.dominant;
        _vibrantColor = palette.vibrant;
        _darkVibrantColor = palette.darkVibrant;
        notifyListeners();
      }
    }
  }

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepEndTime = DateTime.now().add(duration);
    _stopAtEndOfTrack = false;
    notifyListeners();

    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rem = sleepRemaining;
      if (rem == null || rem == Duration.zero) {
        timer.cancel();
        _stopPlayback();
      } else {
        // Smooth 5-second fade-out before stopping
        if (rem.inSeconds <= 5 && rem.inSeconds > 0) {
          final vol = (rem.inSeconds / 5.0).clamp(0.0, 1.0);
          if (!kIsWeb) {
            _audioPlayer.setVolume(vol);
          } else {
            WebPlayerBridge.setVolume((vol * 100.0));
          }
        }
        notifyListeners();
      }
    });
  }

  void setStopAtEndOfTrack(bool enable) {
    cancelSleepTimer();
    _stopAtEndOfTrack = enable;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepEndTime = null;
    _sleepCountdownTimer?.cancel();
    _sleepCountdownTimer = null;
    _stopAtEndOfTrack = false;
    if (!kIsWeb) {
      _audioPlayer.setVolume(1.0);
    } else {
      WebPlayerBridge.setVolume(100.0);
    }
    notifyListeners();
  }

  void _stopPlayback() {
    if (kIsWeb) {
      WebPlayerBridge.pause();
      WebPlayerBridge.setVolume(100.0);
    } else {
      _audioPlayer.pause();
      _audioPlayer.setVolume(1.0);
    }
    cancelSleepTimer();
    notifyListeners();
  }

  Future<void> playPlaylist(List<Video> playlist, int index) async {
    _playlist = List.from(playlist);
    _currentIndex = index;
    _seedPlaylistArtists = _extractArtistsFromSongs(_playlist);
    _playlistArtistRecommendationOffset = 0;
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      await playSong(_playlist[_currentIndex], updateQueue: false);
    }
  }

  void _checkAndPreloadNextQueue() {
    // When repeat mode is on (all or one), do not append recommendations to the queue
    if (_loopMode == LoopMode.all || _loopMode == LoopMode.one) return;

    // When 5 or fewer songs remain after current playing song, silently load next recommendations
    if ((_playlist.length - (_currentIndex + 1)) <= 5 && _currentSong != null) {
      final seedSong = _playlist.isNotEmpty ? _playlist.last : _currentSong!;
      _fetchNextRecommendations(seedSong);
    }
  }

  Future<void> nextSong({bool isCrossfade = false}) async {
    if (!isCrossfade && _isCrossfading) {
      _isCrossfading = false;
      unawaited(_setVolume(1.0));
    }

    if (_stopAtEndOfTrack) {
      debugPrint('[SleepTimer] Reached end of current track. Stopping playback.');
      _stopPlayback();
      return;
    }

    if (_currentSong != null && _audioPlayer.position.inSeconds < 30) {
      PreferencesService().recordSongSkip(_currentSong!.author);
    }

    if (_playlist.isNotEmpty) {
      if (_isShuffle && _playlist.length > 1) {
        // If navigating forward within existing shuffle history
        if (_shuffleHistoryPointer + 1 < _shuffleHistory.length) {
          _shuffleHistoryPointer++;
          _currentIndex = _shuffleHistory[_shuffleHistoryPointer];
        } else {
          // Select next song avoiding consecutive artist repetition
          final random = Random();
          final currentArtist = _currentSong != null ? CanonicalSongDedup.cleanArtist(_currentSong!.author) : '';

          final candidateIndices = <int>[];
          for (int i = 0; i < _playlist.length; i++) {
            if (i == _currentIndex) continue;
            final artist = CanonicalSongDedup.cleanArtist(_playlist[i].author);
            if (currentArtist.isEmpty || artist != currentArtist) {
              candidateIndices.add(i);
            }
          }

          int nextIdx;
          if (candidateIndices.isNotEmpty) {
            nextIdx = candidateIndices[random.nextInt(candidateIndices.length)];
          } else {
            nextIdx = (random.nextInt(_playlist.length - 1) + _currentIndex + 1) % _playlist.length;
          }

          _currentIndex = nextIdx;
          _shuffleHistory.add(_currentIndex);
          _shuffleHistoryPointer = _shuffleHistory.length - 1;
        }

        final prevSong = _currentSong;
        final nextTrack = _playlist[_currentIndex];
        if (prevSong != null) {
          reportTrackFinished(prevSong.id.value, nextTrack.id.value);
        }
        await playSong(nextTrack, updateQueue: false, isCrossfade: isCrossfade);
        _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
        _checkAndPreloadNextQueue();
        return;
      } else if (_currentIndex + 1 < _playlist.length) {
        final prevSong = _currentSong;
        _currentIndex++;
        final nextTrack = _playlist[_currentIndex];
        if (prevSong != null) {
          reportTrackFinished(prevSong.id.value, nextTrack.id.value);
        }
        await playSong(nextTrack, updateQueue: false, isCrossfade: isCrossfade);
        _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
        _checkAndPreloadNextQueue();
        return;
      }
    }

    if (_loopMode == LoopMode.all && _playlist.isNotEmpty) {
      _currentIndex = 0;
      final nextTrack = _playlist[_currentIndex];
      await playSong(nextTrack, updateQueue: false, isCrossfade: isCrossfade);
      _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
      _checkAndPreloadNextQueue();
      return;
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
        await playSong(nextTrack, updateQueue: false, isCrossfade: isCrossfade);
        _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
        _checkAndPreloadNextQueue();
      } else {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> previousSong() async {
    if (_isCrossfading) {
      _isCrossfading = false;
      unawaited(_setVolume(1.0));
    }

    // 1. If in shuffle mode and history exists, traverse back through true shuffle history
    if (_isShuffle && _shuffleHistoryPointer > 0) {
      _shuffleHistoryPointer--;
      _currentIndex = _shuffleHistory[_shuffleHistoryPointer];
      await playSong(_playlist[_currentIndex], updateQueue: false);
      _prewarmUpcomingTracks(_currentIndex + 1, count: 2);
      return;
    }

    // 2. Normal sequential playback previous
    if (_playlist.isNotEmpty && _currentIndex - 1 >= 0) {
      _currentIndex--;
      await playSong(_playlist[_currentIndex], updateQueue: false);
      _prewarmUpcomingTracks(_currentIndex + 1, count: 2);
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

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (_currentIndex == index && isPlaying) return;
    if (_isCrossfading) {
      _isCrossfading = false;
      unawaited(_setVolume(1.0));
    }
    _currentIndex = index;
    _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
    await playSong(_playlist[_currentIndex], updateQueue: false);
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
          .timeout(const Duration(seconds: 7));
    } catch (e) {
      debugPrint('[StreamResolver] StreamClient error for $videoId: $e');
      _reportClientLog('resolve_error', {'videoId': videoId, 'error': e.toString()});
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

  Future<void> playSong(Video song, {bool updateQueue = true, bool isCrossfade = false}) async {
    _cancelActiveFade();
    if (!isCrossfade) {
      if (kIsWeb && WebPlayerBridge.isPlaying) {
        WebPlayerBridge.pause();
      } else if (!kIsWeb && _audioPlayer.playing) {
        unawaited(_audioPlayer.pause());
      }
      unawaited(_setVolume(1.0));
    }

    _isLoading = true;
    _currentSong = song;
    _hasRepeatedOnce = false;

    if (updateQueue) {
      final existingIndex = _playlist.indexWhere((item) => item.id == song.id);
      if (existingIndex != -1) {
        _currentIndex = existingIndex;
      } else {
        _playlist = [song];
        _currentIndex = 0;
        _seedPlaylistArtists = [];
        _playlistArtistRecommendationOffset = 0;
        _generate50SongProgressiveQueue(song);
      }
    }
    notifyListeners();

    // Trigger palette extraction asynchronously with race-condition guard
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

    // Proactively check JioSaavn to upgrade any track to 320kbps studio master!
    if (_webStreamUrls[song.id.value] == null || _webStreamUrls[song.id.value]!.isEmpty) {
      try {
        final cleanT = CanonicalSongDedup.cleanTitle(song.title);
        final cleanA = CanonicalSongDedup.cleanArtist(song.author);
        final q = cleanA.isNotEmpty ? '$cleanT $cleanA' : cleanT;
        if (cleanT.isNotEmpty) {
          Future<bool> tryResolveFromUri(Uri uri) async {
            final jioResp = await http.get(uri).timeout(const Duration(seconds: 4));
            if (_currentSong?.id.value != song.id.value) return false;
            if (jioResp.statusCode == 200) {
              final List<dynamic> list = json.decode(jioResp.body);
              for (final item in list) {
                final itemTitle = item['title'] as String? ?? '';
                final itemArtist = item['author'] as String? ?? '';
                final itemStream = item['streamUrl'] as String? ?? '';
                final itemThumb = item['thumbnail'] as String? ?? '';
                if (itemStream.isEmpty) continue;
                if (_isCoverOrKaraokeTrack(itemTitle, itemArtist)) continue;

                final isMatch = CanonicalSongDedup.areDuplicateSongs(
                  titleA: song.title,
                  artistA: song.author,
                  titleB: itemTitle,
                  artistB: itemArtist,
                );

                if (isMatch) {
                  debugPrint('[Play] Resolved "${song.title}" to JioSaavn 320k studio stream!');
                  _webStreamUrls[song.id.value] = itemStream;
                  if (itemThumb.isNotEmpty && !_artworkMap.containsKey(song.id.value)) {
                    _artworkMap[song.id.value] = itemThumb;
                  }
                  return true;
                }
              }
            }
            return false;
          }

          // 1. Try Cloudflare Worker edge first (ultra-fast 100ms)
          bool matched = await tryResolveFromUri(ApiConfig.jioSearchUri(q, limit: 5));

          // 2. If edge didn't match, fallback to Render backend
          if (!matched && _currentSong?.id.value == song.id.value) {
            await tryResolveFromUri(ApiConfig.jioBackendSearchUri(q, limit: 5));
          }
        }
      } catch (_) {}
    }

    final mediaItem = MediaItem(
      id: song.id.value,
      album: 'DilSe',
      title: song.title,
      artist: song.author,
      artUri: Uri.tryParse(getHdThumbnail(song.id.value)),
      duration: song.duration,
    );

    if (!kIsWeb && audioHandler != null) {
      audioHandler!.changeMediaItem(mediaItem);
    }

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
            await _startPlaybackWithFade(
              isCrossfade: isCrossfade,
              playAction: () async => await _audioPlayer.play(),
            );
            _isLoading = false;
            notifyListeners();
            _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
            _checkAndPreloadNextQueue();
            return;
          }
        }
      }

      // 2. Web Mode (PWA / Browser):
      // Dual Engine: Cloudflare Edge Direct Stream (<audio>) + YouTube IFrame Fallback
      if (kIsWeb) {
        final directStreamUrl = _webStreamUrls[song.id.value] ?? '';
        String webVideoId = song.id.value;
        // If direct stream URL is empty, resolve genuine YouTube ID for web fallback
        if (directStreamUrl.isEmpty) {
          try {
            final cleanT = CanonicalSongDedup.cleanTitle(song.title);
            final cleanA = CanonicalSongDedup.cleanArtist(song.author);
            final ytmQuery = cleanA.isNotEmpty ? '$cleanT $cleanA' : cleanT;
            final ytmResults = await YouTubeMusicClient().searchSongs(ytmQuery, limit: 1).timeout(const Duration(seconds: 4));
            if (ytmResults.isNotEmpty) {
              webVideoId = ytmResults.first.id.value;
            }
          } catch (_) {}
        }
        if (_currentSong?.id.value != song.id.value) return;
        debugPrint('[Play][Web] Playing via Web Dual Engine: $webVideoId (directStream: $directStreamUrl, isCrossfade: $isCrossfade)');
        _reportClientLog('web_stream_start', {'videoId': webVideoId, 'engine': 'dual'});

        if (isCrossfade) {
          final prefs = PreferencesService();
          int crossfadeSec = prefs.crossfadeSeconds;
          if (prefs.smartCrossfadeEnabled) {
            final profile = prefs.audioProfile;
            if (profile.avgTempo > 60 && profile.avgTempo < 200) {
              crossfadeSec = (16 * (60.0 / profile.avgTempo)).clamp(3.0, 9.0).round();
            }
          }
          debugPrint('[Play][Web] Triggering Web Dual-Deck Crossfade (${crossfadeSec}s) to: $webVideoId');
          WebPlayerBridge.crossfade(
            videoId: webVideoId,
            title: song.title,
            artist: song.author,
            artworkUrl: getHdThumbnail(song.id.value),
            streamUrl: directStreamUrl,
            crossfadeSeconds: crossfadeSec,
          );
        } else {
          _cancelActiveFade();
          unawaited(_setVolume(1.0));
          WebPlayerBridge.play(
            webVideoId,
            title: song.title,
            artist: song.author,
            artworkUrl: getHdThumbnail(song.id.value),
            streamUrl: directStreamUrl,
          );
        }
        _isLoading = false;
        notifyListeners();
        _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
        _checkAndPreloadNextQueue();
        return;
      }

      bool playbackSourceSet = false;

      // 3. Mobile Native Mode (Android / iOS app):
      // Check for direct JioSaavn 320kbps CDN stream first!
      final directStreamUrl = _webStreamUrls[song.id.value] ?? '';
      if (directStreamUrl.isNotEmpty) {
        debugPrint('[Play] Playing via Direct JioSaavn 320k Stream on Mobile: ${song.id.value}');
        _reportClientLog('direct_stream_start', {'videoId': song.id.value, 'engine': 'jiosaavn_320k'});
        try {
          if (_currentSong?.id.value != song.id.value) return;
          await _audioPlayer.setAudioSource(
            AudioSource.uri(Uri.parse(directStreamUrl), tag: mediaItem),
          );
          if (_currentSong?.id.value != song.id.value) return;
          _cancelActiveFade();
          await _startPlaybackWithFade(
            isCrossfade: isCrossfade,
            playAction: () async => await _audioPlayer.play(),
          );
          _isLoading = false;
          notifyListeners();
          _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
          _checkAndPreloadNextQueue();
          return;
        } catch (e) {
          debugPrint('[Play] Direct stream error on mobile ($e), falling back to YouTube resolver…');
        }
      }

      // Direct On-Device Multi-Candidate Resolution (Format 18 progressive AAC / itag 251)
      try {
        debugPrint('[Play] Resolving direct audio candidates on mobile device for ${song.id.value}…');
        String effectiveYtId = song.id.value;
        List<StreamCandidate> candidates = [];
        try {
          candidates = await _resolveStreamCandidates(effectiveYtId);
        } catch (_) {}

        if (candidates.isEmpty && _currentSong?.id.value == song.id.value) {
          // If song.id.value is not a YouTube ID (e.g. JioSaavn ID from Spotify import),
          // search YouTube Music to get the real official YouTube video ID!
          try {
            debugPrint('[Play] Searching YouTube Music for real video ID of "${song.title}"…');
            final cleanT = CanonicalSongDedup.cleanTitle(song.title);
            final cleanA = CanonicalSongDedup.cleanArtist(song.author);
            final ytmQuery = cleanA.isNotEmpty ? '$cleanT $cleanA' : cleanT;
            final ytmResults = await YouTubeMusicClient().searchSongs(ytmQuery, limit: 3).timeout(const Duration(seconds: 5));
            if (_currentSong?.id.value != song.id.value) return;
            if (ytmResults.isNotEmpty) {
              effectiveYtId = ytmResults.first.id.value;
              debugPrint('[Play] Found real YouTube track: $effectiveYtId ("${ytmResults.first.title}")');
              candidates = await _resolveStreamCandidates(effectiveYtId);
            }
          } catch (ytmErr) {
            debugPrint('[Play] YouTube Music search fallback error: $ytmErr');
          }
        }

        if (_currentSong?.id.value != song.id.value) return;

        if (candidates.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();

          for (final candidate in candidates) {
            if (_currentSong?.id.value != song.id.value) return;

            debugPrint('[Play] Trying stream candidate (tag: ${candidate.tag}, type: ${candidate.type})…');
            _reportClientLog('trying_stream_candidate', {
              'videoId': effectiveYtId,
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
                'videoId': effectiveYtId,
                'tag': candidate.tag,
              });
              break;
            } catch (uriError) {
              debugPrint('[Play] AudioSource.uri failed ($uriError), trying LockCachingAudioSource…');
              // 2. Second attempt: LockCachingAudioSource fallback
              try {
                final cacheFile = File('${tempDir.path}/track_${effectiveYtId}_${candidate.tag}.m4a');
                if (await cacheFile.exists() && await cacheFile.length() == 0) {
                  await cacheFile.delete();
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
                  'videoId': effectiveYtId,
                  'tag': candidate.tag,
                });
                break;
              } catch (lockError) {
                debugPrint('[Play] Candidate tag ${candidate.tag} failed: $lockError');
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
      }

      // 4. Fallback 1: Backend /stream_url
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

      // 5. Fallback 2: Backend proxy /stream/{id}.m4a
      if (!playbackSourceSet) {
        if (_currentSong?.id.value != song.id.value) return;
        final proxyUri = ApiConfig.streamProxyUri(song.id.value);
        debugPrint('[Play] Fallback 2: Setting audio source to proxy: $proxyUri');
        try {
          await _audioPlayer.setAudioSource(
            AudioSource.uri(proxyUri, tag: mediaItem),
            preload: true,
          );
          playbackSourceSet = true;
        } catch (proxyError) {
          debugPrint('[Play] Proxy error: $proxyError');
        }
      }

      if (_currentSong?.id.value != song.id.value) return;

      if (!playbackSourceSet) {
        debugPrint('[Play] Could not resolve audio source for "${song.title}". Auto-skipping to next track…');
        _isLoading = false;
        notifyListeners();
        if (_playlist.length > 1 && _currentIndex + 1 < _playlist.length) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_currentSong?.id.value == song.id.value) {
            await nextSong();
          }
        }
        return;
      }

      debugPrint('[Play] Starting playback…');
      _cancelActiveFade();
      await _startPlaybackWithFade(
        isCrossfade: isCrossfade,
        playAction: () async => await _audioPlayer.play(),
      );
      _isLoading = false;
      notifyListeners();

      _reportClientLog('playback_active', {
        'videoId': song.id.value,
        'title': song.title,
      });

      _prewarmUpcomingTracks(_currentIndex + 1, count: 3);
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

  List<Video> _getLibraryRecommendationsForSeed(Video seed) {
    final libraryTracks = <Video>[];
    final seen = <String>{seed.id.value, CanonicalSongDedup.cleanTitle(seed.title)};
    final cleanSeedArtist = CanonicalSongDedup.cleanArtist(seed.author);
    final topAffinities = PreferencesService()
        .getTasteMatrix()
        .topArtists
        .map(CanonicalSongDedup.cleanArtist)
        .where((a) => a.isNotEmpty)
        .toSet();

    // Gather all unique songs across user's customPlaylists (the 12k imported library) and liked songs
    final allLibrarySongs = <Map<String, dynamic>>[];
    for (final pl in _customPlaylists) {
      final songs = (pl['songs'] as List<dynamic>?) ?? [];
      for (final s in songs) {
        if (s is Map<String, dynamic>) {
          allLibrarySongs.add(s);
        }
      }
    }
    for (final s in _likedSongs) {
      allLibrarySongs.add(Map<String, dynamic>.from(s));
    }

    if (allLibrarySongs.isEmpty) return [];

    Video toVideo(Map<String, dynamic> item) {
      final id = (item['id'] as String?) ?? '';
      final lang = (item['language'] as String?) ?? '';
      if (id.isNotEmpty && lang.isNotEmpty) {
        CanonicalSongDedup.registerSongLanguage(id, lang);
      }
      return Video(
        VideoId(id),
        (item['title'] as String?) ?? 'Unknown Title',
        (item['author'] as String?) ?? 'Unknown Artist',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet(id),
        null,
        Engagement(0, null, null),
        false,
      );
    }

    // Step A: Exact / Collaborating Artist matches from user library
    final artistMatches = <Video>[];
    for (final item in allLibrarySongs) {
      final id = (item['id'] as String?) ?? '';
      final title = (item['title'] as String?) ?? '';
      final author = (item['author'] as String?) ?? '';
      final cleanT = CanonicalSongDedup.cleanTitle(title);
      if (seen.contains(id) || seen.contains(cleanT)) continue;

      final cleanA = CanonicalSongDedup.cleanArtist(author);
      if (cleanSeedArtist.isNotEmpty && cleanA.isNotEmpty) {
        if (cleanA == cleanSeedArtist || cleanA.contains(cleanSeedArtist) || cleanSeedArtist.contains(cleanA)) {
          seen.add(id);
          seen.add(cleanT);
          artistMatches.add(toVideo(item));
        }
      }
    }

    // Step B: Top User Taste Matrix Artists matches from user library
    final tasteMatches = <Video>[];
    for (final item in allLibrarySongs) {
      final id = (item['id'] as String?) ?? '';
      final title = (item['title'] as String?) ?? '';
      final author = (item['author'] as String?) ?? '';
      final cleanT = CanonicalSongDedup.cleanTitle(title);
      if (seen.contains(id) || seen.contains(cleanT)) continue;

      final cleanA = CanonicalSongDedup.cleanArtist(author);
      if (topAffinities.contains(cleanA)) {
        seen.add(id);
        seen.add(cleanT);
        tasteMatches.add(toVideo(item));
      }
    }

    // Step C: Other library tracks from the same playlist that contains the seed song
    final playlistContextMatches = <Video>[];
    for (final pl in _customPlaylists) {
      final songs = (pl['songs'] as List<dynamic>?) ?? [];
      final hasSeed = songs.any((s) => s is Map && s['id'] == seed.id.value);
      if (hasSeed) {
        for (final s in songs) {
          if (s is! Map<String, dynamic>) continue;
          final vid = toVideo(s);
          final cleanT = CanonicalSongDedup.cleanTitle(vid.title);
          if (!seen.contains(vid.id.value) && !seen.contains(cleanT)) {
            seen.add(vid.id.value);
            seen.add(cleanT);
            playlistContextMatches.add(vid);
          }
        }
        break;
      }
    }

    // Step D: Same-language tracks from user's imported library
    final seedLang = CanonicalSongDedup.detectLanguage(seed.title);
    final languageMatches = <Video>[];
    if (seedLang != null) {
      for (final item in allLibrarySongs) {
        final id = (item['id'] as String?) ?? '';
        final title = (item['title'] as String?) ?? '';
        final cleanT = CanonicalSongDedup.cleanTitle(title);
        if (seen.contains(id) || seen.contains(cleanT)) continue;

        if (CanonicalSongDedup.detectLanguage(title) == seedLang) {
          seen.add(id);
          seen.add(cleanT);
          languageMatches.add(toVideo(item));
        }
      }
    }

    // Shuffle within buckets for fresh variety, then compose prioritized queue
    final random = Random();
    artistMatches.shuffle(random);
    tasteMatches.shuffle(random);
    playlistContextMatches.shuffle(random);
    languageMatches.shuffle(random);

    libraryTracks.addAll(artistMatches.take(15));
    libraryTracks.addAll(playlistContextMatches.take(15));
    libraryTracks.addAll(tasteMatches.take(15));
    libraryTracks.addAll(languageMatches.take(15));

    return libraryTracks;
  }

  List<Video> _getLibraryRecommendationsForArtists(List<String> artists, {String? targetLang}) {
    if (artists.isEmpty) return [];
    final libraryTracks = <Video>[];
    final seen = <String>{};
    for (final s in _playlist) {
      seen.add(s.id.value);
      seen.add(CanonicalSongDedup.cleanTitle(s.title));
    }

    final allLibrarySongs = <Map<String, dynamic>>[];
    for (final pl in _customPlaylists) {
      final songs = (pl['songs'] as List<dynamic>?) ?? [];
      for (final s in songs) {
        if (s is Map<String, dynamic>) {
          allLibrarySongs.add(s);
        }
      }
    }
    for (final s in _likedSongs) {
      allLibrarySongs.add(Map<String, dynamic>.from(s));
    }

    if (allLibrarySongs.isEmpty) return [];

    Video toVideo(Map<String, dynamic> item) {
      final id = (item['id'] as String?) ?? '';
      return Video(
        VideoId(id),
        (item['title'] as String?) ?? 'Unknown Title',
        (item['author'] as String?) ?? 'Unknown Artist',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet(id),
        null,
        Engagement(0, null, null),
        false,
      );
    }

    final artistBuckets = <String, List<Video>>{};
    for (final a in artists) {
      artistBuckets[a] = [];
    }

    final random = Random();
    final shuffledLibrary = List<Map<String, dynamic>>.from(allLibrarySongs)..shuffle(random);

    for (final item in shuffledLibrary) {
      final id = (item['id'] as String?) ?? '';
      final title = (item['title'] as String?) ?? '';
      final author = (item['author'] as String?) ?? '';
      final cleanT = CanonicalSongDedup.cleanTitle(title);
      if (seen.contains(id) || seen.contains(cleanT)) continue;

      if (targetLang != null && !CanonicalSongDedup.isLanguageCompatible(targetLang, title)) {
        continue;
      }

      final cleanA = CanonicalSongDedup.cleanArtist(author);
      for (final targetArtist in artists) {
        if (cleanA == targetArtist || cleanA.contains(targetArtist) || targetArtist.contains(cleanA)) {
          seen.add(id);
          seen.add(cleanT);
          artistBuckets[targetArtist]?.add(toVideo(item));
          break;
        }
      }
    }

    // Interleave tracks round-robin across artist buckets
    int maxBucketLen = 0;
    for (final list in artistBuckets.values) {
      if (list.length > maxBucketLen) maxBucketLen = list.length;
    }
    for (int i = 0; i < maxBucketLen; i++) {
      for (final targetArtist in artists) {
        final bucket = artistBuckets[targetArtist];
        if (bucket != null && i < bucket.length) {
          libraryTracks.add(bucket[i]);
        }
      }
    }

    return libraryTracks;
  }

  List<String> _extractArtistsFromSongs(List<Video> songs) {
    final Map<String, int> frequency = {};
    for (final song in songs) {
      final parts = song.author.split(RegExp(r'[,;&/]|(?:\b(?:feat\.?|ft\.?)\b)', caseSensitive: false));
      for (final rawPart in parts) {
        final cleaned = CanonicalSongDedup.cleanArtist(rawPart);
        if (cleaned.isNotEmpty && cleaned.length >= 2) {
          frequency[cleaned] = (frequency[cleaned] ?? 0) + 1;
        }
      }
    }
    final sorted = frequency.keys.toList()
      ..sort((a, b) => frequency[b]!.compareTo(frequency[a]!));
    return sorted;
  }

  List<String> _getEffectivePlaylistArtists() {
    if (_seedPlaylistArtists.isNotEmpty) {
      return List<String>.from(_seedPlaylistArtists);
    }
    return _extractArtistsFromSongs(_playlist);
  }

  Future<void> _generate50SongProgressiveQueue(Video seed) async {
    if (_isGeneratingQueue) return;
    _isGeneratingQueue = true;

    try {
      debugPrint('[Queue50] Generating 50-song progressive chained queue for: "${seed.title}"…');
      final progressiveQueue = <Video>[seed];
      final seenKeys = <String>{CanonicalSongDedup.cleanTitle(seed.title)};

      final seedLanguage = CanonicalSongDedup.detectLanguage(seed.title);
      final cleanSeedArtist = CanonicalSongDedup.cleanArtist(seed.author);

      // Extract movie/soundtrack name if present e.g. (From "Nagabandham") or (From 'Movie')
      String? movieName;
      final movieMatch = RegExp(r'''from\s+["']([^"']+)["']''', caseSensitive: false).firstMatch(seed.title);
      if (movieMatch != null) {
        movieName = movieMatch.group(1)?.trim();
      }

      void addTracks(List<Video> tracks, {String? targetLang}) {
        for (final track in tracks) {
          if (!CanonicalSongDedup.isGenuineSong(track)) continue;
          if (targetLang != null && !CanonicalSongDedup.isLanguageCompatible(targetLang, track.title)) continue;
          final key = CanonicalSongDedup.cleanTitle(track.title);
          if (key.isNotEmpty && !seenKeys.contains(key)) {
            seenKeys.add(key);
            progressiveQueue.add(track);
            if (progressiveQueue.length >= 51) break;
          }
        }
      }

      // 1. Stage 1 (TOP PRIORITY): Pull matching tracks directly from user's 12k imported library
      final libraryMatches = _getLibraryRecommendationsForSeed(seed);
      addTracks(libraryMatches);

      // 2. Stage 2 (Primary): JioSaavn Movie / Album Affinity (if from a movie soundtrack)
      if (progressiveQueue.length < 51 && movieName != null && movieName.isNotEmpty) {
        final movieResults = await http
            .get(ApiConfig.jioSearchUri('$movieName songs', limit: 20))
            .timeout(const Duration(seconds: 4))
            .then((res) => _parseJioResults(res.body))
            .catchError((_) => <Video>[]);
        addTracks(movieResults, targetLang: seedLanguage);
      }

      // 3. Stage 3 (Primary): JioSaavn Primary Composer / Artist Studio Hits
      if (progressiveQueue.length < 51 && cleanSeedArtist.isNotEmpty) {
        final artistQuery = seedLanguage != null
            ? '$cleanSeedArtist $seedLanguage songs'
            : '$cleanSeedArtist songs';
        final artistResults = await http
            .get(ApiConfig.jioSearchUri(artistQuery, limit: 20))
            .timeout(const Duration(seconds: 4))
            .then((res) => _parseJioResults(res.body))
            .catchError((_) => <Video>[]);
        addTracks(artistResults, targetLang: seedLanguage);
      }

      // 4. Stage 4: Top User Taste Matrix Artists from JioSaavn
      if (progressiveQueue.length < 51) {
        final favArtists = PreferencesService().getTopArtists();
        for (final fav in favArtists) {
          if (progressiveQueue.length >= 51) break;
          final cleanFav = CanonicalSongDedup.cleanArtist(fav);
          if (cleanFav.isEmpty) continue;
          final favQuery = seedLanguage != null ? '$cleanFav $seedLanguage hits' : '$cleanFav hits';
          final favResults = await http
              .get(ApiConfig.jioSearchUri(favQuery, limit: 12))
              .timeout(const Duration(seconds: 4))
              .then((res) => _parseJioResults(res.body))
              .catchError((_) => <Video>[]);
          addTracks(favResults, targetLang: seedLanguage);
        }
      }

      // 5. Stage 5: Online Discovery (Only if library and artist queries yielded < 25 tracks)
      if (progressiveQueue.length < 25) {
        final fallbackQuery = seedLanguage != null
            ? '$seedLanguage top hit songs'
            : (cleanSeedArtist.isNotEmpty ? '$cleanSeedArtist hits' : 'Top Hits 2026');
        final jioFallback = await http
            .get(ApiConfig.jioSearchUri(fallbackQuery, limit: 15))
            .timeout(const Duration(seconds: 4))
            .then((res) => _parseJioResults(res.body))
            .catchError((_) => <Video>[]);
        addTracks(jioFallback, targetLang: seedLanguage);

        if (progressiveQueue.length < 20) {
          final ytmTracks = await YouTubeMusicClient().searchSongs(fallbackQuery, limit: 15);
          addTracks(ytmTracks, targetLang: seedLanguage);
        }
      }

      if (_currentSong?.id.value != seed.id.value) return;

      // Balance artist distribution while preserving rank
      if (progressiveQueue.length > 2) {
        final upcoming = progressiveQueue.sublist(1);
        final balancedUpcoming = CanonicalSongDedup.balanceArtistDistribution(upcoming);
        _playlist = [seed, ...balancedUpcoming];
      } else {
        _playlist = progressiveQueue;
      }

      debugPrint('[Queue50] Successfully generated progressive queue: ${_playlist.length} songs');
      notifyListeners();
    } catch (e) {
      debugPrint('[Queue50] Queue generation error: $e');
    } finally {
      _isGeneratingQueue = false;
    }
  }

  Future<void> _fetchNextRecommendations(Video song) async {
    if (_isFetchingNextQueue) return;
    _isFetchingNextQueue = true;
    try {
      debugPrint('[Queue] Fetching chained recommendations across playlist artists…');

      // 1. Detect dominant language across the active playlist (fallback to seed song)
      final langCounts = <String, int>{};
      for (final s in _playlist) {
        final l = CanonicalSongDedup.detectLanguage(s.title);
        if (l != null) langCounts[l] = (langCounts[l] ?? 0) + 1;
      }
      final dominantLang = langCounts.isNotEmpty
          ? langCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
          : CanonicalSongDedup.detectLanguage(song.title);

      // 2. Extract distinct artists from the active playlist
      final allPlaylistArtists = _getEffectivePlaylistArtists();
      List<Video> candidates = [];

      if (allPlaylistArtists.length > 1) {
        // Multi-artist playlist: Fetch popular hit songs from all/multiple artists in the playlist
        // Select up to 6 distinct artists per batch, rotating across batches so all artists get recommended
        final int batchSize = min(6, allPlaylistArtists.length);
        final selectedArtists = <String>[];
        for (int i = 0; i < batchSize; i++) {
          final idx = (_playlistArtistRecommendationOffset + i) % allPlaylistArtists.length;
          selectedArtists.add(allPlaylistArtists[idx]);
        }
        _playlistArtistRecommendationOffset = (_playlistArtistRecommendationOffset + batchSize) % allPlaylistArtists.length;

        debugPrint('[Queue] Blending popular recommendations from artists: ${selectedArtists.join(', ')} (Language: $dominantLang)');

        // Step A: Pull matching tracks directly from user's 12k imported library for all selected artists
        final libraryMatches = _getLibraryRecommendationsForArtists(selectedArtists, targetLang: dominantLang);
        candidates.addAll(libraryMatches);

        // Step B: Query JioSaavn concurrently for popular studio hits for each selected artist
        final artistQueries = selectedArtists.map((artist) {
          final query = dominantLang != null ? '$artist $dominantLang hits' : '$artist hits';
          return http
              .get(ApiConfig.jioSearchUri(query, limit: 8))
              .timeout(const Duration(seconds: 4))
              .then((res) => _parseJioResults(res.body))
              .catchError((_) => <Video>[]);
        }).toList();

        final artistTrackLists = await Future.wait(artistQueries);

        // Round-robin interleave results so the queue contains an even mix of all playlist artists
        int maxLen = 0;
        for (final list in artistTrackLists) {
          if (list.length > maxLen) maxLen = list.length;
        }
        for (int i = 0; i < maxLen; i++) {
          for (final list in artistTrackLists) {
            if (i < list.length) {
              candidates.add(list[i]);
            }
          }
        }
      } else {
        // Single-artist or single-track playback: Standard artist query
        final cleanArtist = allPlaylistArtists.isNotEmpty
            ? allPlaylistArtists.first
            : CanonicalSongDedup.cleanArtist(song.author);

        // 1. Primary: Library tracks from matching artist / taste matrix
        final libraryMatches = _getLibraryRecommendationsForSeed(song);
        candidates.addAll(libraryMatches);

        // 2. Secondary: JioSaavn Studio catalog query if library yielded < 10
        if (candidates.length < 10) {
          final query = cleanArtist.isNotEmpty
              ? (dominantLang != null ? '$cleanArtist $dominantLang hits' : '$cleanArtist hits')
              : (dominantLang != null ? '$dominantLang top songs' : 'Top Hits 2026');
          final jioResults = await http
              .get(ApiConfig.jioSearchUri(query, limit: 15))
              .timeout(const Duration(seconds: 4))
              .then((res) => _parseJioResults(res.body))
              .catchError((_) => <Video>[]);
          candidates.addAll(jioResults);
        }
      }

      // 3. Fallback: YouTube Music Radio automix only if still empty
      if (candidates.isEmpty && song.id.value.length == 11) {
        candidates = await YouTubeMusicClient().fetchRadioTracks(song.id.value, limit: 15);
      }
      if (candidates.isEmpty) {
        final fallbackQuery = dominantLang != null ? '$dominantLang top hit songs' : 'Top Hits 2026';
        candidates = await YouTubeMusicClient().searchSongs(fallbackQuery, limit: 15);
      }

      // Filter for genuine songs and language compatibility
      final valid = candidates.where((c) =>
          CanonicalSongDedup.isGenuineSong(c) &&
          (dominantLang == null || CanonicalSongDedup.isLanguageCompatible(dominantLang, c.title))
      ).toList();

      final fresh = CanonicalSongDedup.deduplicateList(_playlist, valid);
      if (fresh.isNotEmpty) {
        final balanced = CanonicalSongDedup.balanceArtistDistribution(fresh);
        final tracksToAdd = balanced.take(15).toList();
        _playlist.addAll(tracksToAdd);
        debugPrint('[Queue] Appended ${tracksToAdd.length} multi-artist recommended tracks. Total in queue: ${_playlist.length}');
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

      // 0. Super-fast direct CDN download if JioSaavn 320k stream URL exists
      final directCdnUrl = _webStreamUrls[song.id.value];
      if (directCdnUrl != null && directCdnUrl.isNotEmpty) {
        try {
          final request = http.Request('GET', Uri.parse(directCdnUrl));
          final res = await client.send(request).timeout(const Duration(seconds: 30));
          if (res.statusCode == 200) {
            response = res;
          }
        } catch (e) {
          debugPrint('[Download] Direct JioSaavn CDN error: $e');
        }
      }

      // 1. Primary: Direct on-device stream URL candidates
      if (response == null || response.statusCode != 200) {
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
    if (_isCrossfading) {
      _isCrossfading = false;
      unawaited(_setVolume(1.0));
    }
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
      unawaited(_setVolume(1.0));
      _audioPlayer.play();
    }
    notifyListeners();
  }
}
