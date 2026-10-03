import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/jio_album.dart';
import 'package:music_app/screens/artist_profile_screen.dart';
import 'package:music_app/services/dynamic_artist_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/artist/artist_about_card.dart';
import 'package:music_app/widgets/artist/artist_action_deck.dart';
import 'package:music_app/widgets/artist/artist_albums_section.dart';
import 'package:music_app/widgets/artist/artist_popular_tracks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  const testArtist = ArtistItem(
    name: 'Devi Sri Prasad',
    genre: 'Tollywood • High Energy Dance & Melodies',
    imageUrl: 'https://example.com/dsp.jpg',
    language: 'Telugu',
    badge: 'TOP ARTIST',
  );

  testWidgets(
    'ArtistProfileScreen renders header, buttons, search bar, and filter chips',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ArtistProfileScreen(
            artist: testArtist,
            artistName: 'Devi Sri Prasad',
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Hero Header
      expect(find.text('Devi Sri Prasad'), findsOneWidget);
      expect(find.text('TOP ARTIST'), findsOneWidget);
      expect(
        find.text('Tollywood • High Energy Dance & Melodies'),
        findsOneWidget,
      );

      // Actions
      expect(find.textContaining('Play All'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);

      // Search Bar
      expect(
        find.text("Search within Devi Sri Prasad's tracks..."),
        findsOneWidget,
      );

      // Language Chips Header & Chips
      expect(find.text('LANGUAGE'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Telugu'), findsOneWidget);

      // Movie & Era Chips Header & Chips
      expect(find.text('MOVIE & ERA RANGE'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All Eras'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '2020–2025'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All Movies'), findsOneWidget);
      expect(find.text('Pushpa The Rise'), findsOneWidget);
    },
  );

  testWidgets(
    'ArtistProfileScreen selects language and movie chips interactively',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ArtistProfileScreen(
            artist: testArtist,
            artistName: 'Devi Sri Prasad',
          ),
        ),
      );
      await tester.pump();

      // Tap Tamil chip
      final tamilChip = find.widgetWithText(ChoiceChip, 'Tamil');
      if (tamilChip.evaluate().isNotEmpty) {
        await tester.tap(tamilChip);
        await tester.pump();
        final chip = tester.widget<ChoiceChip>(tamilChip);
        expect(chip.selected, isTrue);
      }

      // Tap Pushpa movie chip
      final pushpaChip = find.text('Pushpa The Rise');
      expect(pushpaChip, findsOneWidget);
      await tester.tap(pushpaChip);
      await tester.pump();

      // 'Clear Movie' should appear in header
      expect(find.text('Clear Movie'), findsOneWidget);

      // Tap Clear Movie
      await tester.tap(find.text('Clear Movie'));
      await tester.pump();
      expect(find.text('Clear Movie'), findsNothing);
    },
  );

  testWidgets('ArtistProfileScreen live search input updates search text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: ArtistProfileScreen(
          artist: testArtist,
          artistName: 'Devi Sri Prasad',
        ),
      ),
    );
    await tester.pump();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'Pushpa Pushpa');
    await tester.pump();

    expect(find.text('Pushpa Pushpa'), findsOneWidget);
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pump();
    expect(find.text('Pushpa Pushpa'), findsNothing);
  });

  testWidgets(
    'ArtistProfileScreen renders smoothly on mobile portrait (390x844)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ArtistProfileScreen(
            artist: testArtist,
            artistName: 'Devi Sri Prasad',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Devi Sri Prasad'), findsOneWidget);
    },
  );

  Video createMockVideo(String seedId, String title, String author) {
    final id = seedId.padRight(11, '0').substring(0, 11);
    return Video(
      VideoId(id),
      title,
      author,
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      const Duration(minutes: 3, seconds: 45),
      ThumbnailSet(id),
      null,
      Engagement(100, null, null),
      false,
    );
  }

  testWidgets(
    'ArtistActionDeck toggles follow status and persists to PreferencesService',
    (WidgetTester tester) async {
      await PreferencesService().init();
      final songs = [
        createMockVideo('vid1', 'Pushpa Pushpa', 'Devi Sri Prasad'),
        createMockVideo('vid2', 'Oo Antava', 'Devi Sri Prasad'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArtistActionDeck(
              artistName: 'Devi Sri Prasad',
              songs: songs,
              themeColor: const Color(0xFF6C5CE7),
            ),
          ),
        ),
      );
      await tester.pump();

      // Initial state: not followed
      expect(PreferencesService().isArtistFollowed('Devi Sri Prasad'), isFalse);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      // Tap follow button
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();

      // State updated in PreferencesService
      expect(PreferencesService().isArtistFollowed('Devi Sri Prasad'), isTrue);
    },
  );

  testWidgets(
    'ArtistPopularTracks renders top 5 ranked tracks with 1-5 index badges',
    (WidgetTester tester) async {
      final songs = List.generate(
        8,
        (i) => createMockVideo('vid$i', 'Hit Song ${i + 1}', 'Devi Sri Prasad'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArtistPopularTracks(
                songs: songs,
                themeColor: const Color(0xFF6C5CE7),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('POPULAR TRACKS'), findsOneWidget);
      // Badges 1 to 5 should be present
      for (int i = 1; i <= 5; i++) {
        expect(find.text('$i'), findsOneWidget);
        expect(find.text('Hit Song $i'), findsOneWidget);
      }
      // Song 6 should NOT be rendered in top 5
      expect(find.text('Hit Song 6'), findsNothing);
    },
  );

  testWidgets('ArtistAlbumsSection renders albums carousel and release count', (
    WidgetTester tester,
  ) async {
    final albums = [
      JioAlbum(
        id: 'alb_1',
        title: 'Pushpa 2: The Rule',
        artist: 'Devi Sri Prasad',
        artwork: 'https://example.com/p2.jpg',
        year: '2024',
        songCount: 6,
        language: 'Telugu',
      ),
      JioAlbum(
        id: 'alb_2',
        title: 'Arya 2',
        artist: 'Devi Sri Prasad',
        artwork: 'https://example.com/a2.jpg',
        year: '2009',
        songCount: 8,
        language: 'Telugu',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArtistAlbumsSection(
              albums: albums,
              themeColor: const Color(0xFF6C5CE7),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SOUNDTRACKS & ALBUMS'), findsOneWidget);
    expect(find.text('2 Releases'), findsOneWidget);
    expect(find.text('Pushpa 2: The Rule'), findsOneWidget);
    expect(find.text('Arya 2'), findsOneWidget);
    expect(find.textContaining('2024'), findsOneWidget);
    expect(find.textContaining('2009'), findsOneWidget);
  });

  testWidgets('ArtistAboutCard renders verified metadata and language chips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArtistAboutCard(
              canonicalName: 'Devi Sri Prasad',
              artistItem: testArtist,
              languages: ['All', 'Telugu', 'Tamil'],
              totalTracks: 142,
              themeColor: Color(0xFF6C5CE7),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ABOUT DEVI SRI PRASAD'), findsOneWidget);
    expect(find.text('142+ Tracks Cataloged'), findsOneWidget);
    expect(find.text('Verified TOP ARTIST'), findsOneWidget);
    expect(find.text('Telugu, Tamil'), findsOneWidget);
    // 'All' filter should be omitted from language chips
    expect(find.text('All'), findsNothing);
  });
}
