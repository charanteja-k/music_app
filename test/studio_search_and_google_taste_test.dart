import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/studio_search_service.dart';
import 'package:music_app/services/dynamic_artist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  group('StudioSearchService Tests', () {
    test('StudioSearchService singleton initializes properly', () {
      final s1 = StudioSearchService();
      final s2 = StudioSearchService();
      expect(identical(s1, s2), isTrue);
    });

    test('searchSongs returns empty list on empty query', () async {
      final results = await StudioSearchService().searchSongs('   ');
      expect(results, isEmpty);
    });
  });

  group('Popular Search Filtering & Noise Removal Tests', () {
    Video makeVideo(String title, String author, {String id = 'video123456'}) {
      return Video(
        VideoId(id.padRight(11, '0').substring(0, 11)),
        title,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        const Duration(minutes: 3, seconds: 30),
        ThumbnailSet(id.padRight(11, '0').substring(0, 11)),
        null,
        Engagement(0, null, null),
        false,
      );
    }

    test(
      'Strictly filters out amateur covers and edits from user screenshot',
      () {
        final query = 'after hours';

        // The 4 unwanted amateur cuts reported by the user
        final pianoCover = makeVideo('After Hours (Piano Version)', 'pianaura');
        final oudCover = makeVideo('After Hours (Arabic Oud)', 'oud awwad');
        final ambientEdit = makeVideo(
          'after hours (ambient version)',
          'stillsilent',
        );
        final slowedEdit = makeVideo(
          'After Hours (slowed to perfection)',
          'hollowhoney',
        );

        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(pianoCover, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(oudCover, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(ambientEdit, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(slowedEdit, query),
          isTrue,
        );
      },
    );

    test(
      'Filters out other derivative noise: guitar/flute/karaoke/8D/TikTok/reverb',
      () {
        final query = 'after hours';

        final guitarCover = makeVideo(
          'After Hours (Guitar Cover)',
          'Acoustic Guitar Guy',
        );
        final fluteCover = makeVideo(
          'After Hours (Flute Rendition)',
          'FluteMaster',
        );
        final violinCover = makeVideo(
          'After Hours (Violin Version)',
          'Solo Strings',
        );
        final karaokeCut = makeVideo(
          'After Hours (Karaoke Version)',
          'Sing King',
        );
        final slowedReverb = makeVideo(
          'After Hours (Slowed + Reverb)',
          'Sad Vibes',
        );
        final spedUp = makeVideo('After Hours (Sped Up)', 'Speed Beats');
        final eightD = makeVideo('After Hours (8D Audio)', '8D Soundscapes');
        final tikTokCut = makeVideo(
          'After Hours (TikTok Remix)',
          'Trending Tunes',
        );
        final ringtoneCut = makeVideo('After Hours Ringtone', 'Mobile Tones');

        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(guitarCover, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(fluteCover, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(violinCover, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(karaokeCut, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(slowedReverb, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(spedUp, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(eightD, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(tikTokCut, query),
          isTrue,
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(ringtoneCut, query),
          isTrue,
        );
      },
    );

    test('Allows genuine official studio songs', () {
      final query = 'after hours';

      final officialWeeknd = makeVideo('After Hours', 'The Weeknd');
      final officialKehlani = makeVideo('After Hours', 'Kehlani');
      final officialBrownEyed = makeVideo('after hours', 'brown eyed girl');

      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(officialWeeknd, query),
        isFalse,
      );
      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(
          officialKehlani,
          query,
        ),
        isFalse,
      );
      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(
          officialBrownEyed,
          query,
        ),
        isFalse,
      );
    });

    test(
      'Preserves legitimate classic tracks containing instrument words in title',
      () {
        final queryBillyJoel = 'billy joel';
        final pianoMan = makeVideo('Piano Man', 'Billy Joel');
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(
            pianoMan,
            queryBillyJoel,
          ),
          isFalse,
        );

        final queryBeatles = 'the beatles';
        final guitarWeeps = makeVideo(
          'While My Guitar Gently Weeps',
          'The Beatles',
        );
        expect(
          StudioSearchService.isUnnecessaryOrAmateurResult(
            guitarWeeps,
            queryBeatles,
          ),
          isFalse,
        );
      },
    );

    test('Allows instrumental or cover if explicitly searched by the user', () {
      final pianoCover = makeVideo('After Hours (Piano Version)', 'pianaura');
      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(
          pianoCover,
          'after hours piano',
        ),
        isFalse,
      );

      final slowedEdit = makeVideo(
        'After Hours (slowed to perfection)',
        'hollowhoney',
      );
      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(
          slowedEdit,
          'after hours slowed',
        ),
        isFalse,
      );

      final guitarCover = makeVideo(
        'After Hours (Guitar Cover)',
        'Acoustic Guy',
      );
      expect(
        StudioSearchService.isUnnecessaryOrAmateurResult(
          guitarCover,
          'after hours cover',
        ),
        isFalse,
      );
    });
  });

  group('Google/YouTube Taste Seeding Tests', () {
    test(
      'seedTasteFromYouTube populates artist counts and updates top artist',
      () async {
        final prefs = PreferencesService();

        final likedSongs = [
          Video(
            VideoId('dQw4w9WgXcQ'),
            'Kesariya',
            'Arijit Singh, Pritam',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            const Duration(minutes: 4),
            ThumbnailSet('dQw4w9WgXcQ'),
            null,
            Engagement(0, null, null),
            false,
          ),
          Video(
            VideoId('9bZkp7q19f0'),
            'Apna Bana Le',
            'Arijit Singh, Sachin-Jigar',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            const Duration(minutes: 3),
            ThumbnailSet('9bZkp7q19f0'),
            null,
            Engagement(0, null, null),
            false,
          ),
        ];

        final playlistSongs = [
          Video(
            VideoId('kJQP7kiw5Fk'),
            'Samajavaragamana',
            'Sid Sriram, Thaman S',
            ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
            DateTime.now(),
            '',
            null,
            '',
            const Duration(minutes: 4),
            ThumbnailSet('kJQP7kiw5Fk'),
            null,
            Engagement(0, null, null),
            false,
          ),
        ];

        await prefs.seedTasteFromYouTube(
          likedSongs: likedSongs,
          playlistSongs: playlistSongs,
        );

        final topArtists = prefs.getTopPlayedArtists(limit: 10);
        expect(topArtists.isNotEmpty, isTrue);

        // Arijit Singh was in 2 liked songs (+5 each = +10), should be top artist
        expect(prefs.mostPlayedArtist.toLowerCase(), contains('arijit'));

        // Check dynamic artists includes seeded taste
        final dynamicArtists = DynamicArtistService().getDynamicArtists();
        expect(dynamicArtists.isNotEmpty, isTrue);
      },
    );
  });
}
