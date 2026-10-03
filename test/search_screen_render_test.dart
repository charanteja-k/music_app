import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/search_screen.dart';
import 'package:music_app/screens/artist_profile_screen.dart';
import 'package:music_app/widgets/artist_card.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    'Search bar displays back arrow when query is entered and redirects to Categories/Albums/Artists on tap',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Initial state: Search icon is visible, back arrow is NOT visible
      expect(find.byIcon(Icons.search_rounded), findsWidgets);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('Recent Searches'), findsOneWidget);

      // Enter a search query in the search bar
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Devara');
      await tester.pumpAndSettle();

      // Back arrow icon is now visible with 'Back to browse' tooltip
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byTooltip('Back to browse'), findsOneWidget);

      // Tap the back arrow button in the search bar
      final backButton = find.byTooltip('Back to browse');
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Verify search was cancelled and screen returned to Browse tabs & Recent Searches
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);

      // Search field text is empty
      final textFieldWidget = tester.widget<TextField>(searchField);
      expect(textFieldWidget.controller?.text, isEmpty);
    },
  );

  testWidgets(
    'Search bar clear suffix icon X also cancels search and redirects to Categories/Albums/Artists',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Pushpa');
      await tester.pumpAndSettle();

      // Clear icon X is visible
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

      // Tap clear icon X
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Back arrow and clear icon are gone; browse tabs are back
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
    },
  );
}
