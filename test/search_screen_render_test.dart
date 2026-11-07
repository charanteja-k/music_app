import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/search_screen.dart';
import 'package:music_app/screens/artist_profile_screen.dart';
import 'package:music_app/widgets/artist_card.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_app/services/trending_catalog_service.dart';
import 'package:music_app/models/jio_album.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'searchHistory': [
        'snehithuda',
        'Akada Unnadu Ayyappa',
        'ayyappa',
        'kalyani',
        'Maula Mere Maula',
        'perfect',
        'Telugu Top Songs',
        'nanaku prematho',
        'love me',
        'o priya',
      ],
    });
    await PreferencesService().init();
  });

  testWidgets(
    'SearchScreen renders Categories and Recent Searches without layout error',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('snehithuda'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen switches smoothly between Categories and Artists tabs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Tap on Artists tab switcher
      final artistsTabFinder = find.widgetWithText(InkWell, 'Artists');
      expect(artistsTabFinder, findsOneWidget);
      await tester.tap(artistsTabFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Featured Artists'), findsOneWidget);

      // Tap back on Categories tab switcher
      final categoriesTabFinder = find.widgetWithText(InkWell, 'Categories');
      expect(categoriesTabFinder, findsOneWidget);
      await tester.tap(categoriesTabFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Browse Categories'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen switches smoothly to Albums tab and displays Soundtracks & Albums header',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Tap on Albums tab switcher
      final albumsTabFinder = find.widgetWithText(InkWell, 'Albums');
      expect(albumsTabFinder, findsOneWidget);
      await tester.tap(albumsTabFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Soundtracks & Albums'), findsOneWidget);
      expect(find.text('Telugu'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen Albums tab strictly filters out cross-language albums for Telugu',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await PreferencesService().setPreferredLanguages(['Telugu']);

      // Seed catalog cache with 1 Telugu album and 1 Hindi album
      TrendingCatalogService().setCachedAlbums('telugu', [
        const JioAlbum(
          id: 't1',
          title: 'Pushpa 2 The Rule [Telugu]',
          artist: 'Devi Sri Prasad',
          artwork: 'https://c.saavncdn.com/pushpa-telugu.jpg',
          year: '2024',
          songCount: 6,
          language: 'telugu',
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      final albumsTabFinder = find.widgetWithText(InkWell, 'Albums');
      await tester.tap(albumsTabFinder);
      await tester.pumpAndSettle();

      expect(find.text('Pushpa 2 The Rule [Telugu]'), findsOneWidget);
      expect(find.text('Udta Teer'), findsNothing);
      expect(find.text("Namit Malhotra's Ramayana [Hindi]"), findsNothing);
    },
  );

  testWidgets(
    'SearchScreen renders on mobile device portrait size without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen renders on mobile device landscape size without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tapping ArtistCard in Artists tab navigates to ArtistProfileScreen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Switch to Artists tab
      final artistsTab = find.widgetWithText(InkWell, 'Artists');
      await tester.tap(artistsTab);
      await tester.pumpAndSettle();

      // Find first ArtistCard and tap it
      final firstArtistCard = find.byType(ArtistCard).first;
      expect(firstArtistCard, findsOneWidget);
      await tester.tap(firstArtistCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should now be on ArtistProfileScreen
      expect(find.byType(ArtistProfileScreen), findsOneWidget);
      expect(find.text('LANGUAGE'), findsOneWidget);
      expect(find.text('MOVIE & ERA RANGE'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen embeds Browse tabs in NestedScrollView for unified screen scrolling',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Verify NestedScrollView is present in Browse mode
      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('Recent Searches'), findsOneWidget);

      // Drag up on categories content - outer scroll view scrolls header up
      await tester.drag(find.text('Browse Categories'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Drag back down - outer scroll view pulls header back down into view
      await tester.drag(find.text('Browse Categories'), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Albums and verify full scrolling
      await tester.tap(find.widgetWithText(InkWell, 'Albums'));
      await tester.pumpAndSettle();
      expect(find.text('Soundtracks & Albums'), findsOneWidget);
      await tester.drag(
        find.text('Soundtracks & Albums'),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Pull Albums back down
      await tester.drag(
        find.text('Soundtracks & Albums'),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();

      // Switch to Artists and verify full scrolling
      await tester.tap(find.widgetWithText(InkWell, 'Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Featured Artists'), findsOneWidget);
      await tester.drag(find.text('Featured Artists'), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
