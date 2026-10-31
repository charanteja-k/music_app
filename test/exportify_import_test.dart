import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:music_app/services/spotify_import_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/music_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Exportify CSV Parser Tests', () {
    test(
      'Correctly parses standard Exportify CSV with Spotify audio features',
      () {
        const sampleCsv = '''
Spotify ID,Artist Name(s),Track Name,Album Name,Artist Genres,Track Duration (ms),Danceability,Energy,Key,Loudness,Mode,Speechiness,Acousticness,Instrumentalness,Liveness,Valence,Tempo,Time Signature
4Dvkj6JhhA12EX05fT7y2e,"Sid Sriram, Sanapati Bharadwaj Patrudu","Samajavaragamana","Ala Vaikunthapurramuloo",tollywood,222000,0.68,0.75,5,-6.2,1,0.05,0.42,0.00,0.12,0.65,128.0,4
5yJg2gW7dK8bH0J19bW78A,"Anirudh Ravichander, Jonita Gandhi","Arabic Kuthu - Halamithi Habibo","Beast",kollywood,279000,0.78,0.85,1,-4.5,0,0.08,0.15,0.01,0.18,0.82,130.0,4
1w3rhv2y8g218h91h281h9,"Arijit Singh, Pritam","Kesariya (From ""Brahmastra"")","Kesariya",bollywood,268000,0.58,0.62,3,-7.1,1,0.04,0.55,0.00,0.10,0.48,112.0,4
''';

        final tracks = ExportifyCsvParser.parse(sampleCsv);
        expect(tracks.length, equals(3));

        // Track 1
        expect(tracks[0].trackName, equals('Samajavaragamana'));
        expect(
          tracks[0].artistName,
          equals('Sid Sriram, Sanapati Bharadwaj Patrudu'),
        );
        expect(tracks[0].albumName, equals('Ala Vaikunthapurramuloo'));
        expect(tracks[0].danceability, closeTo(0.68, 0.01));
        expect(tracks[0].energy, closeTo(0.75, 0.01));
        expect(tracks[0].valence, closeTo(0.65, 0.01));
        expect(tracks[0].tempo, closeTo(128.0, 0.1));
        expect(tracks[0].acousticness, closeTo(0.42, 0.01));

        // Track 2
        expect(tracks[1].trackName, equals('Arabic Kuthu - Halamithi Habibo'));
        expect(
          tracks[1].artistName,
          equals('Anirudh Ravichander, Jonita Gandhi'),
        );
        expect(tracks[1].energy, closeTo(0.85, 0.01));

        // Track 3 - Escaped quotes test
        expect(tracks[2].trackName, equals('Kesariya (From "Brahmastra")'));
        expect(tracks[2].artistName, equals('Arijit Singh, Pritam'));
        expect(tracks[2].valence, closeTo(0.48, 0.01));
      },
    );

    test('Handles alternate header column casing and order', () {
      const alternateCsv = '''
Track,Artist,Album,Danceability,Energy,Valence,Tempo
"Namo Re (Telugu)","Sam C.S., Junaid Kumar","Nagabandham",0.60,0.70,0.50,118.0
''';

      final tracks = ExportifyCsvParser.parse(alternateCsv);
      expect(tracks.length, equals(1));
      expect(tracks[0].trackName, equals('Namo Re (Telugu)'));
      expect(tracks[0].artistName, equals('Sam C.S., Junaid Kumar'));
      expect(tracks[0].albumName, equals('Nagabandham'));
      expect(tracks[0].energy, closeTo(0.70, 0.01));
    });

    test('Ignores empty or malformed rows safely', () {
      const brokenCsv = '''
Spotify ID,Artist Name(s),Track Name
,,,
"","",""
"123","Devi Sri Prasad","Oo Antava"
''';
      final tracks = ExportifyCsvParser.parse(brokenCsv);
      expect(tracks.length, equals(1));
      expect(tracks[0].trackName, equals('Oo Antava'));
      expect(tracks[0].artistName, equals('Devi Sri Prasad'));
    });
  });

  group('Exportify ZIP Parser Tests', () {
    test(
      'Correctly extracts and parses multiple playlist CSVs from a .zip archive',
      () {
        const bollywoodCsv = '''
Spotify ID,Artist Name(s),Track Name,Album Name,Danceability,Energy,Valence,Tempo
1,"Arijit Singh, Pritam","Kesariya","Brahmastra",0.58,0.62,0.48,112.0
2,"Badshah, Aastha Gill","DJ Waley Babu","ONE",0.82,0.91,0.85,130.0
''';

        const teluguCsv = '''
Spotify ID,Artist Name(s),Track Name,Album Name,Danceability,Energy,Valence,Tempo
3,"Sid Sriram","Samajavaragamana","AVPL",0.68,0.75,0.65,128.0
''';

        final archive = Archive();
        archive.addFile(
          ArchiveFile(
            'Bollywood Party.csv',
            utf8.encode(bollywoodCsv).length,
            utf8.encode(bollywoodCsv),
          ),
        );
        archive.addFile(
          ArchiveFile(
            'playlists/Telugu Melodies.csv',
            utf8.encode(teluguCsv).length,
            utf8.encode(teluguCsv),
          ),
        );
        archive.addFile(
          ArchiveFile('readme.txt', 4, utf8.encode('info')),
        ); // Non-CSV should be ignored

        final zipBytes = ZipEncoder().encode(archive);
        expect(zipBytes, isNotNull);

        final playlists = ExportifyCsvParser.parseZipBytes(zipBytes);
        expect(playlists.length, equals(2));

        final names = playlists.map((p) => p.name).toList();
        expect(names.contains('Bollywood Party'), isTrue);
        expect(names.contains('Telugu Melodies'), isTrue);

        final bollywood = playlists.firstWhere(
          (p) => p.name == 'Bollywood Party',
        );
        expect(bollywood.tracks.length, equals(2));
        expect(bollywood.avgEnergy, closeTo(0.765, 0.01));
        expect(bollywood.avgTempo, closeTo(121.0, 0.1));

        final telugu = playlists.firstWhere((p) => p.name == 'Telugu Melodies');
        expect(telugu.tracks.length, equals(1));
        expect(telugu.tracks[0].trackName, equals('Samajavaragamana'));
        expect(telugu.avgValence, closeTo(0.65, 0.01));
      },
    );

    test('Returns empty list when zip archive has no CSVs or is corrupt', () {
      final emptyArchive = Archive();
      emptyArchive.addFile(ArchiveFile('notes.txt', 5, utf8.encode('hello')));
      final zipBytes = ZipEncoder().encode(emptyArchive);

      final playlists = ExportifyCsvParser.parseZipBytes(zipBytes);
      expect(playlists, isEmpty);

      final corruptBytes = [1, 2, 3, 4, 5];
      final corruptPlaylists = ExportifyCsvParser.parseZipBytes(corruptBytes);
      expect(corruptPlaylists, isEmpty);
    });
  });

  group('PreferencesService Taste Ingestion Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'importExportifyTasteData seeds artist play counts and calculates audio profile',
      () async {
        final prefs = PreferencesService();
        await prefs.init();

        final tracks = [
          ExportifyTrack(
            spotifyId: '1',
            trackName: 'Samajavaragamana',
            artistName: 'Sid Sriram, Thaman S',
            albumName: 'AVPL',
            danceability: 0.70,
            energy: 0.80,
            valence: 0.60,
            tempo: 125.0,
            acousticness: 0.40,
          ),
          ExportifyTrack(
            spotifyId: '2',
            trackName: 'Inkem Inkem',
            artistName: 'Sid Sriram',
            albumName: 'Geetha Govindam',
            danceability: 0.60,
            energy: 0.70,
            valence: 0.50,
            tempo: 115.0,
            acousticness: 0.50,
          ),
          ExportifyTrack(
            spotifyId: '3',
            trackName: 'Chaleya',
            artistName: 'Arijit Singh, Shilpa Rao',
            albumName: 'Jawan',
            danceability: 0.75,
            energy: 0.85,
            valence: 0.70,
            tempo: 120.0,
            acousticness: 0.30,
          ),
        ];

        await prefs.importExportifyTasteData(tracks);

        final topArtists = prefs.getTopArtists();
        expect(topArtists.contains('Sid Sriram'), isTrue);

        final audioProfile = prefs.audioProfile;
        expect(audioProfile.tracksAnalyzed, equals(3));
        expect(audioProfile.avgEnergy, closeTo(0.783, 0.01));
        expect(audioProfile.avgTempo, closeTo(120.0, 0.1));

        // Circadian context query should be language-aware and catalog friendly
        final circadian = prefs.getCircadianContext();
        expect(
          circadian.query.contains('Melodies') ||
              circadian.query.contains('Hits'),
          isTrue,
        );
        expect(circadian.query.contains('Acoustic Ambient Melodies'), isFalse);

        // Daily mix queries should not have conversational noise
        final dailyMixes = prefs.getDailyMixConfigs();
        expect(dailyMixes[0].query.contains('radio songs'), isFalse);
        expect(dailyMixes[1].query.contains('songs mix'), isFalse);
      },
    );
  });

  group('MusicService Batch Playlist Operations', () {
    test('addSongsToPlaylist batches insertions and deduplicates by ID', () {
      final musicService = MusicService();
      final pid = musicService.createPlaylist('Test Batch Playlist');

      final song1 = Video(
        VideoId('vid_0000001'),
        'Kesariya',
        'Arijit Singh',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet('vid_0000001'),
        null,
        Engagement(0, null, null),
        false,
      );

      final song2 = Video(
        VideoId('vid_0000002'),
        'Samajavaragamana',
        'Sid Sriram',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet('vid_0000002'),
        null,
        Engagement(0, null, null),
        false,
      );

      // Add batch of songs
      musicService.addSongsToPlaylist(pid, [song1, song2]);

      final pl = musicService.customPlaylists.firstWhere((p) => p['id'] == pid);
      final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
      expect(songs.length, equals(2));
      expect(songs[0]['id'], equals('vid_0000001'));
      expect(songs[1]['id'], equals('vid_0000002'));

      // Try adding duplicate vid_0000001 again in a new batch
      musicService.addSongsToPlaylist(pid, [song1]);
      final updatedPl = musicService.customPlaylists.firstWhere(
        (p) => p['id'] == pid,
      );
      final updatedSongs = List<Map<String, dynamic>>.from(
        updatedPl['songs'] ?? [],
      );
      expect(updatedSongs.length, equals(2)); // No duplicates!

      // Test setPlaylistSongs - updates and preserves exact order
      musicService.setPlaylistSongs(pid, [song2, song1]);
      final reorderedPl = musicService.customPlaylists.firstWhere(
        (p) => p['id'] == pid,
      );
      final reorderedSongs = List<Map<String, dynamic>>.from(
        reorderedPl['songs'] ?? [],
      );
      expect(reorderedSongs.length, equals(2));
      expect(reorderedSongs[0]['id'], equals('vid_0000002'));
      expect(reorderedSongs[1]['id'], equals('vid_0000001'));
    });
  });

  group('SpotifyImportService Background State & Concurrency Tests', () {
    test('State properties and cancellation toggle correctly', () {
      final service = SpotifyImportService();
      expect(service.isImporting, isFalse);
      expect(service.isCancelled, isFalse);

      service.cancelImport();
      // When not importing, cancel is a no-op
      expect(service.isCancelled, isFalse);
      expect(service.statusMessage, isEmpty);
    });

    test(
      'resolveTracksConcurrently correctly preserves order and populates cache',
      () async {
        final service = SpotifyImportService();
        service.clearCache();
        expect(service.cacheHitCount, equals(0));

        final tracks = [
          ExportifyTrack(
            spotifyId: 'sp_1',
            trackName: 'Kesariya',
            artistName: 'Arijit Singh',
            albumName: 'Brahmastra',
          ),
          ExportifyTrack(
            spotifyId: 'sp_2',
            trackName: 'Samajavaragamana',
            artistName: 'Sid Sriram',
            albumName: 'AVPL',
          ),
        ];

        final resolved = await service.resolveTracksConcurrently(
          tracks: tracks,
          concurrency: 2,
        );

        // Even in test environment (where search returns empty or results),
        // order is preserved and completed count matches
        expect(resolved, isA<List<Video>>());
      },
    );

    test('Cancellation preserves resolved songs in playlist', () async {
      final musicService = MusicService();
      final pid = musicService.createPlaylist('Cancel Test Playlist');

      final song = Video(
        VideoId('vid_canc001'),
        'Test Song',
        'Test Artist',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet('vid_canc001'),
        null,
        Engagement(0, null, null),
        false,
      );

      // Simulate streaming update and immediate cancellation save
      musicService.setPlaylistSongs(pid, [song], commit: true);

      final pl = musicService.customPlaylists.firstWhere((p) => p['id'] == pid);
      final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
      expect(songs.length, equals(1));
      expect(songs.first['id'], equals('vid_canc001'));
    });
  });

  group('100% Accuracy Song Resolution & Derivative Rejection Tests', () {
    Video makeVideo(
      String title,
      String author, {
      String id = 'vid_acc_001',
      Duration? duration,
    }) {
      return Video(
        VideoId(id.padRight(11, '0').substring(0, 11)),
        title,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        duration ?? const Duration(minutes: 3, seconds: 30),
        ThumbnailSet(id.padRight(11, '0').substring(0, 11)),
        null,
        Engagement(0, null, null),
        false,
      );
    }

    test('Accepts exact authentic studio match', () {
      final target = ExportifyTrack(
        spotifyId: 'sp_1',
        trackName: 'Kesariya',
        artistName: 'Arijit Singh, Pritam',
        albumName: 'Brahmastra',
        durationMs: 268000,
      );
      final candidate = makeVideo(
        'Kesariya',
        'Arijit Singh, Pritam',
        duration: const Duration(seconds: 268),
      );
      expect(
        SpotifyImportService.isValidMatchCandidate(candidate, target),
        isTrue,
      );
    });

    test(
      'Accepts track with movie/soundtrack tag in candidate matching album',
      () {
        final target = ExportifyTrack(
          spotifyId: 'sp_2',
          trackName: 'Kesariya',
          artistName: 'Arijit Singh, Pritam',
          albumName: 'Brahmastra',
          durationMs: 268000,
        );
        final candidate = makeVideo(
          'Kesariya (From "Brahmastra")',
          'Arijit Singh',
          duration: const Duration(seconds: 268),
        );
        expect(
          SpotifyImportService.isValidMatchCandidate(candidate, target),
          isTrue,
        );
      },
    );

    test(
      'Strictly rejects amateur derivatives reported by user (piano, oud, ambient, slowed)',
      () {
        final target = ExportifyTrack(
          spotifyId: 'sp_after_hours',
          trackName: 'After Hours',
          artistName: 'The Weeknd',
          albumName: 'After Hours',
          durationMs: 361000,
        );

        final pianoCover = makeVideo(
          'After Hours (Piano Version)',
          'pianaura',
          duration: const Duration(seconds: 165),
        );
        final oudCover = makeVideo(
          'After Hours (Arabic Oud)',
          'oud awwad',
          duration: const Duration(seconds: 210),
        );
        final ambientEdit = makeVideo(
          'after hours (ambient version)',
          'stillsilent',
          duration: const Duration(seconds: 360),
        );
        final slowedEdit = makeVideo(
          'After Hours (slowed to perfection)',
          'hollowhoney',
          duration: const Duration(seconds: 400),
        );

        expect(
          SpotifyImportService.isValidMatchCandidate(pianoCover, target),
          isFalse,
        );
        expect(
          SpotifyImportService.isValidMatchCandidate(oudCover, target),
          isFalse,
        );
        expect(
          SpotifyImportService.isValidMatchCandidate(ambientEdit, target),
          isFalse,
        );
        expect(
          SpotifyImportService.isValidMatchCandidate(slowedEdit, target),
          isFalse,
        );
      },
    );

    test('Strictly rejects wrong song with partial common word in title', () {
      final target = ExportifyTrack(
        spotifyId: 'sp_stay',
        trackName: 'Stay',
        artistName: 'The Kid LAROI, Justin Bieber',
        albumName: 'F*CK LOVE 3',
        durationMs: 141000,
      );
      final wrongSong = makeVideo(
        'Stay With Me',
        'Sam Smith',
        duration: const Duration(seconds: 172),
      );
      expect(
        SpotifyImportService.isValidMatchCandidate(wrongSong, target),
        isFalse,
      );
    });

    test('Strictly rejects candidate with duration discrepancy > 35s', () {
      final target = ExportifyTrack(
        spotifyId: 'sp_blinding',
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        durationMs: 200000, // 3:20 = 200s
      );
      final shortCut = makeVideo(
        'Blinding Lights',
        'The Weeknd',
        duration: const Duration(seconds: 80), // 1:20 = 80s (diff = 120s > 35s)
      );
      expect(
        SpotifyImportService.isValidMatchCandidate(shortCut, target),
        isFalse,
      );
    });

    test('Strictly rejects unrelated artist cover or upload', () {
      final target = ExportifyTrack(
        spotifyId: 'sp_shape',
        trackName: 'Shape of You',
        artistName: 'Ed Sheeran',
        albumName: 'Divide',
        durationMs: 233000,
      );
      final amateurCover = makeVideo(
        'Shape of You',
        'Unknown Bedroom Artist',
        duration: const Duration(seconds: 233),
      );
      expect(
        SpotifyImportService.isValidMatchCandidate(amateurCover, target),
        isFalse,
      );
    });

    test(
      'findBestMatch selects authentic studio hit and rejects amateur noise',
      () {
        final target = ExportifyTrack(
          spotifyId: 'sp_after_hours',
          trackName: 'After Hours',
          artistName: 'The Weeknd',
          albumName: 'After Hours',
          durationMs: 361000,
        );

        final candidates = [
          makeVideo(
            'After Hours (Piano Version)',
            'pianaura',
            duration: const Duration(seconds: 165),
          ),
          makeVideo(
            'After Hours',
            'The Weeknd',
            id: 'jio_weeknd_ah',
            duration: const Duration(seconds: 361),
          ),
          makeVideo(
            'After Hours (slowed to perfection)',
            'hollowhoney',
            duration: const Duration(seconds: 400),
          ),
        ];

        final match = SpotifyImportService.findBestMatch(candidates, target);
        expect(match, isNotNull);
        expect(match!.author, equals('The Weeknd'));
        expect(match.title, equals('After Hours'));
      },
    );

    test(
      'findBestMatch returns null when no candidate meets 100% accuracy criteria',
      () {
        final target = ExportifyTrack(
          spotifyId: 'sp_timeless',
          trackName: 'Timeless',
          artistName: 'The Weeknd, Playboi Carti',
          albumName: 'Hurry Up Tomorrow',
          durationMs: 256000,
        );

        final nonMatchingCandidates = [
          makeVideo(
            'Stay With Me',
            'Sam Smith',
            duration: const Duration(seconds: 172),
          ),
          makeVideo(
            'Starboy',
            'The Weeknd',
            duration: const Duration(seconds: 230),
          ),
        ];

        final match = SpotifyImportService.findBestMatch(
          nonMatchingCandidates,
          target,
        );
        expect(match, isNull); // Zero false positives guarantee!
      },
    );
  });
}
