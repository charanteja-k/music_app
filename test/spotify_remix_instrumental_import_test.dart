import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/spotify_import_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Video makeVideo(
    String title,
    String author, {
    String id = 'vid_12345678',
    Duration duration = const Duration(seconds: 210),
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
      duration,
      ThumbnailSet(id),
      null,
      Engagement(0, null, null),
      false,
    );
  }

  group('Spotify Remix & Instrumental Detection Tests', () {
    test('isRemixTrack accurately identifies remix and club mix tracks', () {
      final t1 = ExportifyTrack(
        spotifyId: '1',
        trackName: 'Save Your Tears (Remix)',
        artistName: 'The Weeknd, Ariana Grande',
        albumName: 'Save Your Tears (Remix)',
      );
      final t2 = ExportifyTrack(
        spotifyId: '2',
        trackName: 'After Hours - The Blaze Remix',
        artistName: 'The Weeknd',
        albumName: 'After Hours (Remixes)',
      );
      final t3 = ExportifyTrack(
        spotifyId: '3',
        trackName: 'Levitating - Don Diablo Club Mix',
        artistName: 'Dua Lipa',
        albumName: 'Club Future Nostalgia',
      );
      final tNormal = ExportifyTrack(
        spotifyId: '4',
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
      );

      expect(SpotifyImportService.isRemixTrack(t1), isTrue);
      expect(SpotifyImportService.isRemixTrack(t2), isTrue);
      expect(SpotifyImportService.isRemixTrack(t3), isTrue);
      expect(SpotifyImportService.isRemixTrack(tNormal), isFalse);
    });

    test('isInstrumentalTrack accurately identifies instrumental tracks', () {
      final t1 = ExportifyTrack(
        spotifyId: '1',
        trackName: 'Blinding Lights - Instrumental',
        artistName: 'The Weeknd',
        albumName: 'After Hours (Instrumentals)',
      );
      final t2 = ExportifyTrack(
        spotifyId: '2',
        trackName: 'Die With A Smile',
        artistName: 'Lady Gaga, Bruno Mars',
        albumName: 'Die With A Smile',
        instrumentalness: 0.85,
      );
      final tNormal = ExportifyTrack(
        spotifyId: '3',
        trackName: 'Die With A Smile',
        artistName: 'Lady Gaga, Bruno Mars',
        albumName: 'Die With A Smile',
        instrumentalness: 0.05,
      );

      expect(SpotifyImportService.isInstrumentalTrack(t1), isTrue);
      expect(SpotifyImportService.isInstrumentalTrack(t2), isTrue);
      expect(SpotifyImportService.isInstrumentalTrack(tNormal), isFalse);
    });
  });

  group('Verified Artist Check Tests', () {
    test('Identifies curated and verified global recording artists', () {
      expect(SpotifyImportService.isVerifiedArtist('The Weeknd'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('Taylor Swift'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('Dua Lipa'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('A.R. Rahman'), isTrue);
      expect(
        SpotifyImportService.isVerifiedArtist('Anirudh Ravichander'),
        isTrue,
      );
      expect(SpotifyImportService.isVerifiedArtist('Arijit Singh'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('David Guetta'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('Coldplay'), isTrue);
      expect(SpotifyImportService.isVerifiedArtist('Alan Walker'), isTrue);
    });

    test(
      'Identifies verified artists in collaborative / multi-credit strings',
      () {
        expect(
          SpotifyImportService.isVerifiedArtist('The Weeknd, The Blaze'),
          isTrue,
        );
        expect(
          SpotifyImportService.isVerifiedArtist('Dua Lipa, Blessed Madonna'),
          isTrue,
        );
        expect(
          SpotifyImportService.isVerifiedArtist('The Weeknd, Ariana Grande'),
          isTrue,
        );
        expect(
          SpotifyImportService.isVerifiedArtist('Ed Sheeran feat. FuntCase'),
          isTrue,
        );
      },
    );

    test('Identifies verified publication for authentic Spotify tracks', () {
      final validSpotifyTrack = ExportifyTrack(
        spotifyId: 'spotify:track:4Dvkj6JhhA12EX05fT7y2e',
        trackName: 'Special Remix',
        artistName: 'Indie Authentic Artist',
        albumName: 'Album',
        popularity: 45,
      );
      expect(
        SpotifyImportService.isVerifiedArtist(
          'Indie Authentic Artist',
          track: validSpotifyTrack,
        ),
        isTrue,
      );
    });

    test('Rejects amateur and unverified uploaders / noise channels', () {
      expect(SpotifyImportService.isVerifiedArtist(''), isFalse);
      expect(SpotifyImportService.isVerifiedArtist('Unknown Artist'), isFalse);
      expect(
        SpotifyImportService.isVerifiedArtist('DJ Ramesh Remix Hub'),
        isFalse,
      );
      expect(
        SpotifyImportService.isVerifiedArtist('Wedding Varmala Ceremony'),
        isFalse,
      );
      expect(
        SpotifyImportService.isVerifiedArtist('Amateur Cover Band'),
        isFalse,
      );
    });
  });

  group('Title Cleaning with Remix & Instrumental Preservation', () {
    test('Preserves remix and instrumental descriptors when requested', () {
      expect(
        SpotifyImportService.cleanTrackTitle(
          'Save Your Tears (with Ariana Grande) (Remix)',
          preserveRemixOrInstrumental: true,
        ),
        equals('Save Your Tears (Remix)'),
      );

      expect(
        SpotifyImportService.cleanTrackTitle(
          'After Hours - The Blaze Remix',
          preserveRemixOrInstrumental: true,
        ),
        equals('After Hours - The Blaze Remix'),
      );

      expect(
        SpotifyImportService.cleanTrackTitle(
          'Blinding Lights - Instrumental Version',
          preserveRemixOrInstrumental: true,
        ),
        equals('Blinding Lights - Instrumental Version'),
      );

      expect(
        SpotifyImportService.cleanTrackTitle(
          'Shape of You - Remastered 2020',
          preserveRemixOrInstrumental: true,
        ),
        equals('Shape of You'),
      );
    });
  });

  group('Remix & Instrumental Candidate Validation Tests', () {
    test('Accepts remix candidate for verified artist remix track', () {
      final track = ExportifyTrack(
        spotifyId: 'sp_sytr',
        trackName: 'Save Your Tears (Remix)',
        artistName: 'The Weeknd, Ariana Grande',
        albumName: 'Save Your Tears (Remix)',
        durationMs: 191000,
      );

      final remixCandidate = makeVideo(
        'Save Your Tears (Remix)',
        'The Weeknd',
        id: 'jio_sytr_remix',
        duration: const Duration(seconds: 191),
      );

      expect(
        SpotifyImportService.isValidMatchCandidate(remixCandidate, track),
        isTrue,
      );
    });

    test('Rejects non-remix original song when target is explicitly a remix', () {
      final track = ExportifyTrack(
        spotifyId: 'sp_sytr',
        trackName: 'Save Your Tears (Remix)',
        artistName: 'The Weeknd, Ariana Grande',
        albumName: 'Save Your Tears (Remix)',
        durationMs: 191000,
      );

      final originalCandidate = makeVideo(
        'Save Your Tears',
        'The Weeknd',
        duration: const Duration(seconds: 215),
      );

      // Ensures the importer does not import the standard song in place of the requested remix
      expect(
        SpotifyImportService.isValidMatchCandidate(originalCandidate, track),
        isFalse,
      );
    });

    test(
      'Rejects remix candidate when artist in CSV is unverified / amateur',
      () {
        final track = ExportifyTrack(
          spotifyId: '',
          trackName: 'Shape of You (DJ Ramesh Remix)',
          artistName: 'DJ Ramesh Remix Hub',
          albumName: 'Party Mashups',
          durationMs: 200000,
        );

        final amateurCandidate = makeVideo(
          'Shape of You (DJ Ramesh Remix)',
          'DJ Ramesh',
          duration: const Duration(seconds: 200),
        );

        expect(
          SpotifyImportService.isValidMatchCandidate(amateurCandidate, track),
          isFalse,
        );
      },
    );

    test(
      'Accepts instrumental candidate for verified artist instrumental track',
      () {
        final track = ExportifyTrack(
          spotifyId: 'sp_bl_inst',
          trackName: 'Blinding Lights - Instrumental',
          artistName: 'The Weeknd',
          albumName: 'After Hours (Instrumentals)',
          durationMs: 200000,
        );

        final instrumentalCandidate = makeVideo(
          'Blinding Lights (Instrumental)',
          'The Weeknd',
          id: 'jio_bl_inst',
          duration: const Duration(seconds: 200),
        );

        expect(
          SpotifyImportService.isValidMatchCandidate(
            instrumentalCandidate,
            track,
          ),
          isTrue,
        );
      },
    );

    test(
      'findBestMatch selects authentic remix over original or amateur cuts',
      () {
        final target = ExportifyTrack(
          spotifyId: 'sp_sytr',
          trackName: 'Save Your Tears (Remix)',
          artistName: 'The Weeknd, Ariana Grande',
          albumName: 'Save Your Tears (Remix)',
          durationMs: 191000,
        );

        final candidates = [
          makeVideo(
            'Save Your Tears (Piano Cover)',
            'pianaura',
            duration: const Duration(seconds: 180),
          ),
          makeVideo(
            'Save Your Tears',
            'The Weeknd',
            duration: const Duration(seconds: 215),
          ),
          makeVideo(
            'Save Your Tears (Remix)',
            'The Weeknd, Ariana Grande',
            id: 'jio_sytr_match',
            duration: const Duration(seconds: 191),
          ),
        ];

        final match = SpotifyImportService.findBestMatch(candidates, target);
        expect(match, isNotNull);
        expect(match!.title, equals('Save Your Tears (Remix)'));
        expect(match.author, equals('The Weeknd, Ariana Grande'));
      },
    );
  });
}
