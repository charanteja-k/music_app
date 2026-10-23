import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/search_screen.dart';
import 'package:music_app/layouts/desktop_layout_state.dart';
import 'package:music_app/layouts/desktop_main_viewport.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'searchHistory': ['Sid Sriram', 'A.R. Rahman'],
      'preferredLanguages': ['Telugu'],
    });
    await PreferencesService().init();
    DesktopLayoutState.globalSearchQuery.value = '';
    DesktopLayoutState.submittedSearchQuery.value = '';
    DesktopLayoutState.setNavTab(DesktopNavTab.home);
  });

  tearDown(() {
    DesktopLayoutState.globalSearchQuery.value = '';
    DesktopLayoutState.submittedSearchQuery.value = '';
    DesktopLayoutState.setNavTab(DesktopNavTab.home);
  });

  group('Desktop Search Bar Deduplication Directive', () {
    testWidgets(
      'On Desktop viewport (>= 1024px), secondary search input and mobile AppBar are suppressed',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
        await tester.pumpAndSettle();

        // Secondary search field must NOT exist on desktop
        expect(find.byKey(const ValueKey('search_text_field')), findsNothing);
        expect(find.text('Artists, Songs, Lyrics, and More'), findsNothing);

        // Mobile AppBar with 'Search' title must NOT exist on desktop
        expect(find.byType(AppBar), findsNothing);

        // Browse Categories grid must cleanly introduce the view
        expect(find.text('Browse Categories'), findsOneWidget);
        expect(
          find.text('Explore curated moods, genres & charts'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'When isDesktopView is true, secondary search input is suppressed regardless of size',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: SearchScreen(isDesktopView: true)),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('search_text_field')), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('Browse Categories'), findsOneWidget);
      },
    );

    testWidgets(
      'On Mobile viewport (< 1024px), inline mobile search bar and AppBar remain present',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
        await tester.pumpAndSettle();

        // Secondary/inline search field must exist on mobile
        expect(find.byKey(const ValueKey('search_text_field')), findsOneWidget);
        expect(find.text('Artists, Songs, Lyrics, and More'), findsOneWidget);

        // Mobile AppBar with 'Search' title must exist on mobile
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Search'), findsOneWidget);
      },
    );

    testWidgets(
      'Inside DesktopMainViewport, SearchScreen suppresses center search bar',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.setNavTab(DesktopNavTab.search);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: DesktopMainViewport())),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('search_text_field')), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('Browse Categories'), findsOneWidget);

        DesktopLayoutState.setNavTab(DesktopNavTab.home);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    testWidgets(
      'Top search query synchronization drives SearchScreen and clears to Browse Categories',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Browse Categories'), findsOneWidget);

        // Simulate typing into global top navigation bar
        DesktopLayoutState.globalSearchQuery.value = 'Anirudh';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Clearing global search query reverts to Browse Categories
        DesktopLayoutState.globalSearchQuery.value = '';
        await tester.pumpAndSettle();

        expect(find.text('Browse Categories'), findsOneWidget);
      },
    );
  });
}
