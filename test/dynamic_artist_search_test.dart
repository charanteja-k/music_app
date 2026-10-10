import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/dynamic_artist_service.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/widgets/artist_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DynamicArtistService & ArtistCard Tests', () {
    late PreferencesService prefs;
    late DynamicArtistService artistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService();
      prefs.resetForTesting();
      await prefs.init();
      artistService = DynamicArtistService();
    });

    test(
      'Initial getDynamicArtists returns rich diverse artist catalog with 0 duplicates',
      () {
        final artists = artistService.getDynamicArtists();
        expect(artists, isNotEmpty);
        expect(artists.length, greaterThanOrEqualTo(20));

        final names = <String>{};
        for (final a in artists) {
          expect(a.name, isNotEmpty);
          expect(a.genre, isNotEmpty);
          expect(a.imageUrl, isNotEmpty);
          expect(a.badge, isNotEmpty);
          expect(
            names.contains(a.name.toLowerCase()),
            isFalse,
            reason: 'Duplicate artist found: ${a.name}',
          );
          names.add(a.name.toLowerCase());
        }
      },
    );

    test(
      'User listening data dynamically bubbles top artists to the front',
      () async {
        // User listens to Devi Sri Prasad multiple times
        await prefs.recordSongPlay('Devi Sri Prasad', 'Pushpa Pushpa');
        await prefs.recordSongPlay('DSP, Sid Sriram', 'Srivalli');
        await prefs.recordSongPlay('Devi Sri Prasad', 'Oo Antava');

        final artists = artistService.getDynamicArtists();
        expect(artists.first.name, equals('Devi Sri Prasad'));
        expect(artists.first.isFromUserHistory, isTrue);
        expect(artists.first.badge, equals('TOP ARTIST'));
        expect(artists.first.genre, contains('Tollywood'));
      },
    );

    test(
      'Recommends genre-similar artists based on user listening taste',
      () async {
        // User listens heavily to Anirudh (Tamil)
        await prefs.recordSongPlay('Anirudh Ravichander', 'Hukum');
        await prefs.recordSongPlay('Anirudh Ravichander', 'Badass');

        final artists = artistService.getDynamicArtists();
        // First must be Anirudh
        expect(artists.first.name, equals('Anirudh Ravichander'));
        expect(artists.first.isFromUserHistory, isTrue);

        // Followed by genre/language similar artists (like Sai Abhyankkar, Santhosh Narayanan, etc.)
        final similarArtists = artists
            .where((a) => a.badge == 'FOR YOU')
            .toList();
        expect(similarArtists, isNotEmpty);
        expect(similarArtists.any((a) => a.language == 'Tamil'), isTrue);
      },
    );

    testWidgets(
      'ArtistCard renders image, bold artist name, small genre, and fires onTap',
      (tester) async {
        bool tapped = false;

        const testArtist = ArtistItem(
          name: 'Sai Abhyankkar',
          genre: 'Tamil Indie • Viral RnB & Pop',
          imageUrl:
              'https://cdn-images.dzcdn.net/images/artist/234646e93d6ab2923f3bdc363f53d330/500x500-000000-80-0-0.jpg',
          language: 'Tamil',
          badge: 'VIRAL HIT',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 120,
                child: ArtistCard(
                  artist: testArtist,
                  onTap: () {
                    tapped = true;
                  },
                ),
              ),
            ),
          ),
        );

        // Verify artist name in bold letters and genre in small letters
        expect(find.text('Sai Abhyankkar'), findsOneWidget);
        expect(find.text('Tamil Indie • Viral RnB & Pop'), findsOneWidget);
        expect(find.text('VIRAL HIT'), findsOneWidget);

        // Tap on the card
        await tester.tap(find.byType(ArtistCard));
        await tester.pumpAndSettle();

        expect(tapped, isTrue);
      },
    );

    test(
      'Curated catalog contains 45+ verified artists without placeholder hashes',
      () {
        final artists = artistService.getDynamicArtists();
        expect(artists.length, greaterThanOrEqualTo(45));

        for (final a in artists) {
          expect(a.imageUrl, contains('500x500'));
          expect(
            a.imageUrl.contains('c9d19c4bba2c1605876c762729974916'),
            isFalse,
            reason: '${a.name} has placeholder hash',
          );
        }

        // Verify specific key artists use official JioSaavn CDN
        final rahman = artists.firstWhere((a) => a.name == 'A.R. Rahman');
        expect(rahman.imageUrl, contains('c.saavncdn.com/artists/'));

        final keeravaani = artists.firstWhere(
          (a) => a.name.contains('Keerava'),
        );
        expect(keeravaani.imageUrl, contains('c.saavncdn.com/artists/'));
      },
    );

    test(
      'Non-artist strings, channel names and song titles in history are filtered out',
      () async {
        // User plays tracks with record label authors or full title tokens
        await prefs.recordSongPlay('Aditya Music', 'Pushpa Trailer');
        await prefs.recordSongPlay('T-Series Telugu', 'Devara Glimpse');
        await prefs.recordSongPlay('Love Me (From Movie)', 'Love Me');
        await prefs.recordSongPlay(
          'Akada Unnadu Ayyappa Full Song',
          'Devotional',
        );

        final artists = artistService.getDynamicArtists();
        final names = artists.map((a) => a.name.toLowerCase()).toList();

        expect(names.contains('aditya music'), isFalse);
        expect(names.contains('t-series telugu'), isFalse);
        expect(names.contains('love me (from movie)'), isFalse);
        expect(names.contains('akada unnadu ayyappa full song'), isFalse);
      },
    );

    test('isKnownArtist correctly recognizes catalog artists and aliases', () {
      expect(artistService.isKnownArtist('Devi Sri Prasad'), isTrue);
      expect(artistService.isKnownArtist('dsp'), isTrue);
      expect(artistService.isKnownArtist('Thaman S'), isTrue);
      expect(artistService.isKnownArtist('thaman'), isTrue);
      expect(artistService.isKnownArtist('A.R. Rahman'), isTrue);
      expect(artistService.isKnownArtist('ar rahman'), isTrue);
      expect(artistService.isKnownArtist('Anirudh'), isTrue);
      expect(artistService.isKnownArtist('Arijit Singh'), isTrue);
      expect(artistService.isKnownArtist('Diljit Dosanjh'), isTrue);
      expect(artistService.isKnownArtist('The Weeknd'), isTrue);

      // Negative cases
      expect(artistService.isKnownArtist('random song title'), isFalse);
      expect(artistService.isKnownArtist(''), isFalse);
      expect(artistService.isKnownArtist('aditya music'), isFalse);
    });

    test(
      'getArtistDiscographyQueries generates targeted, language-aware query fanout',
      () {
        // Telugu Artist (Devi Sri Prasad)
        final dspPage1 = artistService.getArtistDiscographyQueries(
          'Devi Sri Prasad',
          page: 1,
        );
        expect(dspPage1, contains('Devi Sri Prasad'));
        expect(dspPage1.any((q) => q.contains('melody hits')), isTrue);
        expect(dspPage1.any((q) => q.contains('mass hits')), isTrue);
        expect(dspPage1.any((q) => q.contains('classics')), isTrue);

        final dspPage2 = artistService.getArtistDiscographyQueries(
          'Devi Sri Prasad',
          page: 2,
        );
        expect(
          dspPage2.any(
            (q) =>
                q.contains('Pushpa') ||
                q.contains('Mirchi') ||
                q.contains('Rangasthalam'),
          ),
          isTrue,
        );
        expect(dspPage2.length, equals(6));

        // Tamil Artist (Anirudh)
        final anirudhPage1 = artistService.getArtistDiscographyQueries(
          'Anirudh Ravichander',
          page: 1,
        );
        expect(anirudhPage1.any((q) => q.contains('Tamil hits')), isTrue);

        // Hindi Artist (Arijit Singh)
        final arijitPage1 = artistService.getArtistDiscographyQueries(
          'Arijit Singh',
          page: 1,
        );
        expect(arijitPage1.any((q) => q.contains('Bollywood hits')), isTrue);

        // Global Artist (The Weeknd)
        final weekndPage1 = artistService.getArtistDiscographyQueries(
          'The Weeknd',
          page: 1,
        );
        expect(weekndPage1.any((q) => q.contains('greatest hits')), isTrue);
      },
    );

    test(
      'Echo-chamber prevention caps user history artists to at most 3',
      () async {
        // User listens to 6 different artists
        await prefs.recordSongPlay('Devi Sri Prasad', 'Song 1');
        await prefs.recordSongPlay('Thaman S', 'Song 2');
        await prefs.recordSongPlay('Sid Sriram', 'Song 3');
        await prefs.recordSongPlay('Anirudh Ravichander', 'Song 4');
        await prefs.recordSongPlay('Arijit Singh', 'Song 5');
        await prefs.recordSongPlay('Armaan Malik', 'Song 6');

        final artists = artistService.getDynamicArtists();
        final userHistoryArtists = artists
            .where((a) => a.isFromUserHistory)
            .toList();

        // Must be capped at 3 so curated icons remain immediately accessible
        expect(userHistoryArtists.length, lessThanOrEqualTo(3));
        expect(artists.length, greaterThanOrEqualTo(20));
      },
    );

    test(
      'getFilmography returns verified movies for artists with curated catalogs',
      () {
        final dspFilms = artistService.getFilmography('Devi Sri Prasad');
        expect(dspFilms, isNotEmpty);
        expect(dspFilms, contains('Pushpa The Rise'));
        expect(dspFilms, contains('Arya'));
        expect(dspFilms, contains('Jalsa'));

        final rahmanFilms = artistService.getFilmography('A.R. Rahman');
        expect(rahmanFilms, isNotEmpty);
        expect(rahmanFilms, contains('Roja'));
        expect(rahmanFilms, contains('Dil Se'));

        final unknownFilms = artistService.getFilmography(
          'NonExistentArtistXYZ',
        );
        expect(unknownFilms, isEmpty);
      },
    );

    test('getArtistLanguages returns multi-lingual repertoire or fallback', () {
      final dspLangs = artistService.getArtistLanguages('Devi Sri Prasad');
      expect(dspLangs, contains('Telugu'));
      expect(dspLangs, contains('Tamil'));
      expect(dspLangs, contains('Hindi'));

      final rahmanLangs = artistService.getArtistLanguages('A R Rahman');
      expect(rahmanLangs, contains('Tamil'));
      expect(rahmanLangs, contains('Hindi'));
      expect(rahmanLangs, contains('Telugu'));

      final defaultLang = artistService.getArtistLanguages(
        'Unknown Person 123',
      );
      expect(defaultLang, equals(['Telugu']));
    });

    test('rankSearchResults eliminates wedding/DJ noise and duplicates', () {
      Video makeVideo(String id, String title, String author) => Video(
        VideoId(id.padRight(11, '0')),
        title,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        const Duration(minutes: 3, seconds: 30),
        ThumbnailSet(id.padRight(11, '0')),
        null,
        Engagement(0, null, null),
        false,
      );

      final songs = [
        makeVideo('id1', 'Once Upon A Time', 'Anirudh Ravichander, Heisenberg'),
        makeVideo('id2', 'Once Upon a Time', 'Anirudh Ravichander, Heizenberg'),
        makeVideo(
          'id3',
          'Once Upon A Time (From "Vikram")',
          'Heisenberg, Anirudh',
        ),
        makeVideo('id4', 'Varmala Vidhi', 'Wedding Music Channel'),
        makeVideo('id5', 'Naatu Naatu (Instrumental)', 'Instrumental Channel'),
        makeVideo('id6', 'Bas Tera Saath Chahiye', 'DJ Karan Bhaii, sonu roy'),
        makeVideo(
          'id7',
          'Bloody Sweet (From "Leo")',
          'Anirudh Ravichander, Siddharth Basrur',
        ),
        makeVideo(
          'id8',
          "Bloody Sweet (From 'Leo')",
          'Siddharth Basrur, Anirudh Ravichander',
        ),
      ];

      final ranked = MusicService().rankSearchResults(songs, 'Anirudh');

      // Must strictly eliminate non-music / wedding / DJ noise
      expect(ranked.any((s) => s.title.contains('Varmala')), isFalse);
      expect(ranked.any((s) => s.title.contains('Instrumental')), isFalse);
      expect(ranked.any((s) => s.title.contains('Bas Tera Saath')), isFalse);

      // Must strictly deduplicate: exactly 1 Once Upon A Time and 1 Bloody Sweet
      final onceUponCount = ranked
          .where((s) => s.title.toLowerCase().contains('once upon a time'))
          .length;
      expect(onceUponCount, equals(1));

      final bloodySweetCount = ranked
          .where((s) => s.title.toLowerCase().contains('bloody sweet'))
          .length;
      expect(bloodySweetCount, equals(1));
    });

    test(
      'fetchEntitySuggestions returns artist suggestion for known curated artist',
      () async {
        final suggestions = await MusicService().fetchEntitySuggestions(
          'Ed Sheeran',
        );
        expect(
          suggestions.any(
            (s) =>
                s.type == SearchSuggestionType.artist &&
                s.text.toLowerCase().contains('ed sheeran'),
          ),
          isTrue,
        );
      },
    );
  });
}
