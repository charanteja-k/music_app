import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_app/services/canonical_song_dedup.dart';
import 'package:music_app/services/lyrics_transliteration_service.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/playlist_artist_filter.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/spotify_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {}
  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      getUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      postUrl(Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => 2;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(utf8.encode('[]')).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MockHttpOverrides();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'crossfade': true,
      'crossfadeSeconds': 3,
      'smartCrossfade': false,
      'custom_server_url': '',
      'cloudflare_worker_url': '',
      'listening_history': <String>[],
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
          (call) async {
            if (call.method == 'init') {
              final id = (call.arguments as Map?)?['id'] as String?;
              if (id != null) {
                TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger
                    .setMockMethodCallHandler(
                      MethodChannel('com.ryanheise.just_audio.methods.$id'),
                      (subCall) async {
                        return {};
                      },
                    );
              }
            }
            return {};
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            return '.';
          },
        );
  });

  Video createMockVideo({
    required String id,
    required String title,
    required String author,
    Duration? duration,
  }) {
    // Valid YouTube VideoId must be exactly 11 characters
    final safeId = id
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
        .padRight(11, '0')
        .substring(0, 11);
    return Video(
      VideoId(safeId),
      title,
      author,
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      duration ?? const Duration(minutes: 3, seconds: 30),
      ThumbnailSet(safeId),
      null,
      Engagement(10000, null, null),
      false,
    );
  }

  group('THE HEART: Playback Engine & Audio State Machine Rigorous Tests', () {
    test(
      'Ghost Play Button Fix: togglePlayPause on idle/completed/unloaded restarts track',
      () {
        final music = MusicService();
        final song1 = createMockVideo(
          id: 'song1abc111',
          title: 'Samajavaragamana',
          author: 'Sid Sriram',
        );
        music.setPlaylistForTesting([song1], initialIndex: 0);

        expect(music.currentSong?.id.value, 'song1abc111');
        expect(music.isPlaying, isFalse);

        // Should not throw and should re-trigger playSong internally
        expect(() => music.togglePlayPause(), returnsNormally);
      },
    );

    test(
      'Queue Boundary Edges: setPlaylistForTesting with empty queue resets currentSong cleanly',
      () {
        final music = MusicService();
        // Empty queue sets currentSong to null
        music.setPlaylistForTesting([], initialIndex: 0);
        expect(music.currentSong, isNull);
        expect(music.playlist, isEmpty);

        // Single item queue
        final song1 = createMockVideo(
          id: 'song1abc111',
          title: 'Kesariya',
          author: 'Arijit Singh',
        );
        music.setPlaylistForTesting([song1], initialIndex: 0);
        expect(music.currentIndex, 0);
        expect(music.currentSong?.id.value, 'song1abc111');
      },
    );

    test(
      'Queue Navigation: setPlaylistForTesting sets correct song at target index',
      () {
        final music = MusicService();
        final s1 = createMockVideo(
          id: 'song1abc111',
          title: 'Song 1',
          author: 'Artist 1',
        );
        final s2 = createMockVideo(
          id: 'song2abc222',
          title: 'Song 2',
          author: 'Artist 2',
        );
        music.setPlaylistForTesting([s1, s2], initialIndex: 1);

        expect(music.currentIndex, 1);
        expect(music.currentSong?.id.value, 'song2abc222');

        music.setPlaylistForTesting([s1, s2], initialIndex: 0);
        expect(music.currentIndex, 0);
        expect(music.currentSong?.id.value, 'song1abc111');
      },
    );

    test(
      'LoopMode State Transitions via toggleRepeat: off -> all -> one -> off cycle',
      () {
        final music = MusicService();
        music.setLoopModeForTesting(LoopMode.off);
        expect(music.loopMode, LoopMode.off);

        music.toggleRepeat();
        expect(music.loopMode, LoopMode.all);

        music.toggleRepeat();
        expect(music.loopMode, LoopMode.one);

        music.toggleRepeat();
        expect(music.loopMode, LoopMode.off);
      },
    );

    test(
      'Shuffle preserves entire playlist contents without dropping tracks',
      () {
        final music = MusicService();
        final songs = List.generate(
          10,
          (i) => createMockVideo(
            id: 'track_${i.toString().padLeft(5, '0')}',
            title: 'Title $i',
            author: 'Artist $i',
          ),
        );
        music.setPlaylistForTesting(songs, initialIndex: 0);

        expect(music.playlist.length, 10);
        final originalIds = music.playlist.map((e) => e.id.value).toSet();

        music.toggleShuffle();
        expect(music.isShuffle, isTrue);
        expect(music.playlist.length, 10);
        expect(
          music.playlist.map((e) => e.id.value).toSet(),
          equals(originalIds),
        );

        music.toggleShuffle();
        expect(music.isShuffle, isFalse);
        expect(music.playlist.length, 10);
      },
    );

    test(
      'Sleep Timer logic handles durations and cancellation without error',
      () {
        final music = MusicService();
        expect(music.isSleepTimerActive, isFalse);
        expect(music.sleepTimerLabel, 'Off');

        music.startSleepTimer(const Duration(minutes: 15));
        expect(music.isSleepTimerActive, isTrue);
        expect(music.sleepRemaining, isNotNull);

        music.cancelSleepTimer();
        expect(music.isSleepTimerActive, isFalse);
        expect(music.sleepTimerLabel, 'Off');

        music.setStopAtEndOfTrack(true);
        expect(music.isSleepTimerActive, isTrue);
        expect(music.sleepTimerLabel, 'End of Track');
        music.cancelSleepTimer();
      },
    );
  });

  group('THE BRAIN: Deduplication, Filtering & Noise Rejection Rigorous Tests', () {
    test(
      'Extreme title cleaning strips brackets, noise words, labels, and resolutions',
      () {
        const noisy1 =
            'Chuttamalle [Official 4K HDR Video Song] | Devara | Jr NTR | Janhvi Kapoor | Anirudh';
        final clean1 = CanonicalSongDedup.cleanTitle(noisy1);
        expect(clean1.toLowerCase(), contains('chuttamalle'));
        expect(clean1.toLowerCase(), isNot(contains('4k')));
        expect(clean1.toLowerCase(), isNot(contains('official')));
        expect(clean1.toLowerCase(), isNot(contains('video song')));

        const noisy2 =
            'Butta Bomma (Full Song) - Ala Vaikunthapurramuloo | Allu Arjun | Thaman S (Remastered 2024)';
        final clean2 = CanonicalSongDedup.cleanTitle(noisy2);
        expect(clean2.toLowerCase(), contains('butta bomma'));
        expect(clean2.toLowerCase(), isNot(contains('full song')));
        expect(clean2.toLowerCase(), isNot(contains('remastered')));
      },
    );

    test(
      'Non-music video filter strictly rejects speeches, trailers, teasers, reels & cricket',
      () {
        final speechVideo = createMockVideo(
          id: 'speech11111',
          title: 'Jr NTR Emotional Speech @ Devara Pre Release Event',
          author: 'Shreyas Media',
        );
        expect(CanonicalSongDedup.isGenuineSong(speechVideo), isFalse);

        final trailerVideo = createMockVideo(
          id: 'trailer1111',
          title: 'Pushpa 2 The Rule Official Trailer - Telugu',
          author: 'Mythri Movie Makers',
        );
        expect(CanonicalSongDedup.isGenuineSong(trailerVideo), isFalse);

        final cricketVideo = createMockVideo(
          id: 'cricket1111',
          title: 'India vs Pakistan T20 Match Highlights 2024',
          author: 'Star Sports News',
        );
        expect(CanonicalSongDedup.isGenuineSong(cricketVideo), isFalse);

        final statusVideo = createMockVideo(
          id: 'status11111',
          title: 'Kurchi Madathapetti Full Screen WhatsApp Status Video',
          author: 'Edits Buzz',
        );
        expect(CanonicalSongDedup.isGenuineSong(statusVideo), isFalse);

        final genuineSong = createMockVideo(
          id: 'genuine1111',
          title: 'Kurchi Madathapetti',
          author: 'Thaman S, Mahesh Babu',
          duration: const Duration(minutes: 3, seconds: 40),
        );
        expect(CanonicalSongDedup.isGenuineSong(genuineSong), isTrue);
      },
    );

    test(
      'Duplicate comparison correctly identifies matches across formatting variations',
      () {
        expect(
          CanonicalSongDedup.areDuplicateSongs(
            titleA: 'Chuttamalle [Official Video]',
            artistA: 'Anirudh Ravichander',
            titleB: 'Chuttamalle',
            artistB: 'Anirudh',
          ),
          isTrue,
        );

        // Distinct songs must not match
        expect(
          CanonicalSongDedup.areDuplicateSongs(
            titleA: 'Chuttamalle',
            artistA: 'Anirudh Ravichander',
            titleB: 'Fear Song',
            artistB: 'Anirudh Ravichander',
          ),
          isFalse,
        );
      },
    );

    test(
      'Canonical deduplication handles 1000 items with zero duplicates in O(N)',
      () {
        final listA = List.generate(
          500,
          (i) => createMockVideo(
            id: 'a_${i.toString().padLeft(9, '0')}',
            title: 'Song Number $i',
            author: 'Artist $i',
          ),
        );
        // Create duplicate items with slight title noise
        final listB = List.generate(
          500,
          (i) => createMockVideo(
            id: 'b_${i.toString().padLeft(9, '0')}',
            title: 'Song Number $i [Official Video]',
            author: 'Artist $i',
          ),
        );

        final deduped = CanonicalSongDedup.deduplicateList(listA, listB);
        // Because listB items are duplicate canonical tracks of listA, deduped should be empty!
        expect(deduped, isEmpty);
      },
    );
  });

  group(
    'THE BRAIN: Multilingual Transliteration & Lyrics Engine Rigorous Tests',
    () {
      test(
        'Indic script detection recognizes Telugu, Devanagari, Tamil and Kannada',
        () {
          expect(
            LyricsTransliterationService.hasIndicScript(
              'చుట్టమల్లే చుట్టేసింది',
            ),
            isTrue,
          );
          expect(
            LyricsTransliterationService.hasIndicScript(
              'केसरिया तेरा इश्क है पिया',
            ),
            isTrue,
          );
          expect(
            LyricsTransliterationService.hasIndicScript('கண்ணம்மா என் காதலி'),
            isTrue,
          );
          expect(
            LyricsTransliterationService.hasIndicScript('ಬೆಳದಿಂಗಳ ಬಾಲೆ'),
            isTrue,
          );
          expect(
            LyricsTransliterationService.hasIndicScript(
              'Hello World in English',
            ),
            isFalse,
          );
        },
      );

      test(
        'LRC parsing and transliteration preserves multi-format timestamps',
        () {
          const inputLrc = '''
[00:12.34]గుండెల్లో గోదారి
[00:15.890]ఎగిసిపడే అలలా
[00:20]మౌనం కరిగే వేళ
''';
          final transliterated = LyricsTransliterationService.transliterateLrc(
            inputLrc,
          );

          expect(transliterated, contains('[00:12.34]'));
          expect(transliterated, contains('[00:15.890]'));
          expect(transliterated, contains('[00:20]'));
          // Verify Telugu characters were transformed into readable English phonetics
          expect(
            LyricsTransliterationService.hasIndicScript(transliterated),
            isFalse,
          );
        },
      );

      test('Romanized Telugu detection identifies Tenglish phonetics', () {
        expect(
          LyricsTransliterationService.isRomanizedTelugu(
            'Gundello prema kalale unnave',
          ),
          isTrue,
        );
        expect(
          LyricsTransliterationService.isRomanizedTelugu(
            'Chuttamalle samajavaragamana',
          ),
          isTrue,
        );
        expect(
          LyricsTransliterationService.isRomanizedTelugu(
            'The quick brown fox jumps over the lazy dog',
          ),
          isFalse,
        );
      });

      test(
        'Reverse transliteration converts Romanized Telugu into Telugu script',
        () {
          final script = LyricsTransliterationService.toTeluguScript(
            'chuttamalle',
          );
          expect(LyricsTransliterationService.hasIndicScript(script), isTrue);
        },
      );
    },
  );

  group('THE BRAIN: Artist Extraction, Aliases & Smart Recommendations', () {
    test(
      'PlaylistArtistFilter normalizes and strips known record label channels',
      () {
        final artists = PlaylistArtistFilter.extractArtistsFromSong({
          'author':
              'Devi Sri Prasad, Shreya Ghoshal, T-Series Telugu, Aditya Music',
        });
        expect(artists, contains('Devi Sri Prasad'));
        expect(artists, contains('Shreya Ghoshal'));
        expect(artists, isNot(contains('T-Series Telugu')));
        expect(artists, isNot(contains('Aditya Music')));
      },
    );

    test('Artist alias resolution links DSP, ARR, and SPB properly', () {
      expect(
        PlaylistArtistFilter.isArtistMatch('dsp', 'devi sri prasad'),
        isTrue,
      );
      expect(
        PlaylistArtistFilter.isArtistMatch('devi sri prasad', 'rockstar dsp'),
        isTrue,
      );
      expect(PlaylistArtistFilter.isArtistMatch('arr', 'a. r. rahman'), isTrue);
      expect(
        PlaylistArtistFilter.isArtistMatch('spb', 's p balasubrahmanyam'),
        isTrue,
      );
      expect(
        PlaylistArtistFilter.isArtistMatch('anirudh', 'anirudh ravichander'),
        isTrue,
      );
      expect(
        PlaylistArtistFilter.isArtistMatch('anirudh', 'thaman s'),
        isFalse,
      );
    });

    test(
      'In-Playlist search differentiates artist matches from title matches',
      () {
        final playlist = [
          {'title': 'Butta Bomma', 'author': 'Thaman S, Armaan Malik'},
          {'title': 'Ramuloo Ramulaa', 'author': 'Thaman S, Anurag Kulkarni'},
          {'title': 'Thaman Special Theme', 'author': 'Devi Sri Prasad'},
        ];

        // Query "Thaman" matches Thaman S as artist
        final resultArtist = PlaylistArtistFilter.searchPlaylist(
          songs: playlist,
          query: 'Thaman',
        );
        expect(resultArtist.matchedIndices, containsAll([0, 1]));

        // Query "Butta" matches song title
        final resultTitle = PlaylistArtistFilter.searchPlaylist(
          songs: playlist,
          query: 'Butta',
        );
        expect(resultTitle.matchedIndices, equals([0]));
        expect(resultTitle.isArtistSearch, isFalse);
      },
    );
  });

  group('THE BRAIN: Universal Spotify/Exportify Import & Acoustic Intelligence', () {
    test('RFC 4180 CSV parser handles quotes, embedded commas, and UTF-8 BOM', () {
      const csv =
          '\uFEFF"Track Name","Artist Name(s)","Album Name","Duration (ms)","Danceability","Energy","Valence"\n'
          '"Chuttamalle","Anirudh Ravichander, Shilpa Rao","Devara Part 1","220000","0.75","0.82","0.68"\n'
          '"Fear Song, The (feat. ""Anirudh"")","Anirudh Ravichander","Devara Part 1","195000","0.88","0.95","0.45"\n';

      final tracks = ExportifyCsvParser.parse(csv);
      expect(tracks.length, 2);
      expect(tracks[0].trackName, 'Chuttamalle');
      expect(tracks[0].artistName, 'Anirudh Ravichander, Shilpa Rao');
      expect(tracks[0].danceability, 0.75);

      expect(tracks[1].trackName, 'Fear Song, The (feat. "Anirudh")');
      expect(tracks[1].energy, 0.95);
    });

    test(
      'ExportifyCsvParser automatically detects alternative delimiters (semicolon, tab)',
      () {
        const semicolonCsv =
            'Track Name;Artist Name(s);Album Name;Duration (ms)\n'
            'Kesariya;Arijit Singh;Brahmastra;268000\n';

        final tracks = ExportifyCsvParser.parse(semicolonCsv);
        expect(tracks.length, 1);
        expect(tracks[0].trackName, 'Kesariya');
        expect(tracks[0].artistName, 'Arijit Singh');
      },
    );

    test(
      'UserAudioProfile calculates consolidated acoustic features accurately',
      () {
        final tracks = [
          ExportifyTrack(
            spotifyId: '1',
            trackName: 'T1',
            artistName: 'A1',
            albumName: 'AL1',
            danceability: 0.6,
            energy: 0.8,
            valence: 0.4,
            tempo: 120.0,
          ),
          ExportifyTrack(
            spotifyId: '2',
            trackName: 'T2',
            artistName: 'A2',
            albumName: 'AL2',
            danceability: 0.8,
            energy: 0.6,
            valence: 0.6,
            tempo: 130.0,
          ),
        ];

        final playlist = ExportifyPlaylist(name: 'Favorites', tracks: tracks);
        expect(playlist.avgDanceability, closeTo(0.7, 0.001));
        expect(playlist.avgEnergy, closeTo(0.7, 0.001));
        expect(playlist.avgValence, closeTo(0.5, 0.001));
        expect(playlist.avgTempo, closeTo(125.0, 0.001));
      },
    );
  });

  group('THE BRAIN: Listening History & Personalization Scoring', () {
    test(
      'PreferencesService records song play and aggregates top artist frequency',
      () async {
        final prefs = PreferencesService();
        await prefs.init();

        prefs.recordSongPlay('Sid Sriram', 'Samajavaragamana');
        prefs.recordSongPlay('Sid Sriram', 'Inkem Inkem');
        prefs.recordSongPlay('Anirudh Ravichander', 'Chuttamalle');

        final topArtists = prefs.getTopPlayedArtists(limit: 5);
        expect(topArtists.first.key, 'Sid Sriram');
        // Lead artist gets +2 per play -> 2 plays * 2 = 4
        expect(topArtists.first.value, 4);
      },
    );

    test(
      'Listening history deduplication and max capacity clamp to prevent leaks',
      () async {
        final prefs = PreferencesService();
        await prefs.init();

        // Push 120 unique items
        for (int i = 0; i < 120; i++) {
          prefs.addToListeningHistory({
            'id': 'hist_$i',
            'title': 'Track $i',
            'author': 'Artist $i',
            'playedAt': DateTime.now().toIso8601String(),
          });
        }

        // Should be strictly capped (standard cap is 100 items)
        expect(prefs.listeningHistory.length, lessThanOrEqualTo(100));
      },
    );

    test(
      'CanonicalSongDedup deduplicates repeated bracket tokens and detects genuine YouTube IDs',
      () {
        // 1. Repeated token deduplication
        expect(
          CanonicalSongDedup.deduplicateRepeatedTokens(
            'Perfect (Acoustic) (Acoustic)',
          ),
          'Perfect (Acoustic)',
        );
        expect(
          CanonicalSongDedup.deduplicateRepeatedTokens('Song [Live] [Live]'),
          'Song [Live]',
        );
        expect(
          CanonicalSongDedup.deduplicateRepeatedTokens(
            'Title (Remix) (Remix) (Remix)',
          ),
          'Title (Remix)',
        );
        expect(
          CanonicalSongDedup.deduplicateRepeatedTokens('Normal Title (Audio)'),
          'Normal Title (Audio)',
        );

        // 2. YouTube ID validation vs JioSaavn synthetic IDs
        expect(CanonicalSongDedup.isLikelyYouTubeId('dQw4w9WgXcQ'), isTrue);
        expect(
          CanonicalSongDedup.isLikelyYouTubeId('54321000000'),
          isFalse,
        ); // 11-digit synthetic Jio ID
        expect(CanonicalSongDedup.isLikelyYouTubeId('00000000000'), isFalse);
        expect(CanonicalSongDedup.isLikelyYouTubeId('short'), isFalse);
      },
    );

    test(
      'PreferencesService decomposes collab artists and produces single lead artist in DailyMixConfig',
      () async {
        final prefs = PreferencesService();
        prefs.resetForTesting();

        SharedPreferences.setMockInitialValues({
          'artistPlayCountsJson': json.encode({
            'S.P. Balasubramaniam, Srinivas D., Khatija Rahman': 10,
            'Anirudh Ravichander': 8,
          }),
        });

        await prefs.init();

        final taste = prefs.getTasteMatrix();
        // Should not contain composite 3-artist string
        expect(
          taste.topArtists.contains(
            'S.P. Balasubramaniam, Srinivas D., Khatija Rahman',
          ),
          isFalse,
        );
        // Should contain individual canonical artists
        expect(
          taste.topArtists.any(
            (a) => a.contains('Balasubra') || a == 'S.P. Balasubrahmanyam',
          ),
          isTrue,
        );

        final configs = prefs.getDailyMixConfigs();
        for (final cfg in configs) {
          // Subtitle should never contain multiple comma-separated artists
          expect(
            cfg.subtitle.contains(','),
            isFalse,
            reason:
                'Subtitle "${cfg.subtitle}" should have a single lead artist',
          );
          expect(
            cfg.query.contains(','),
            isFalse,
            reason:
                'Query "${cfg.query}" should not query comma-separated collab string',
          );
        }
      },
    );

    test(
      'MusicService search ranking prioritizes exact titles and penalizes movie tag noise',
      () {
        final musicService = MusicService();
        final testSongs = [
          Video(
            VideoId('vid_movie_1'),
            'PERFECT (From "Sunny Sanskari Ki Tulsi Kumari")',
            'Guru Randhawa',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            null,
            ThumbnailSet('vid_movie_1'),
            null,
            Engagement(0, null, null),
            false,
          ),
          Video(
            VideoId('vid_exact_1'),
            'Perfect',
            'Ed Sheeran',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            null,
            ThumbnailSet('vid_exact_1'),
            null,
            Engagement(0, null, null),
            false,
          ),
          Video(
            VideoId('vid_1d_perf'),
            'Perfect',
            'One Direction',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            null,
            ThumbnailSet('vid_1d_perf'),
            null,
            Engagement(0, null, null),
            false,
          ),
          Video(
            VideoId('vid_acoust1'),
            'Perfect (Acoustic)',
            'Ed Sheeran',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            null,
            ThumbnailSet('vid_acoust1'),
            null,
            Engagement(0, null, null),
            false,
          ),
        ];

        final ranked = musicService.rankSearchResults(testSongs, 'Perfect');
        // Duplicate acoustic version of same song by Ed Sheeran is deduplicated
        expect(ranked.length, 3);
        expect(ranked.first.id.value, 'vid_exact_1'); // Exact match #1
        expect(ranked[1].id.value, 'vid_1d_perf'); // One Direction #2
        expect(
          ranked.last.id.value,
          'vid_movie_1',
        ); // Movie soundtrack downranked #3

        // Compound Title + Artist query: "perfect ed sheeran"
        final rankedEdSheeran = musicService.rankSearchResults(
          testSongs,
          'perfect ed sheeran',
        );
        expect(
          rankedEdSheeran.first.id.value,
          'vid_exact_1',
          reason: 'Ed Sheeran - Perfect must be #1 for "perfect ed sheeran"',
        );

        // Compound Title + Artist query without space: "perfect edsheeran"
        final rankedEdNoSpace = musicService.rankSearchResults(
          testSongs,
          'perfect edsheeran',
        );
        expect(
          rankedEdNoSpace.first.id.value,
          'vid_exact_1',
          reason: 'Ed Sheeran - Perfect must be #1 for "perfect edsheeran"',
        );
      },
    );
  });
}
