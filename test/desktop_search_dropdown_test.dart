import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/layouts/desktop_layout_state.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/desktop/desktop_search_dropdown.dart';
import 'package:music_app/widgets/desktop/desktop_top_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopSearchDropdown & TopNavBar Integration Tests', () {
    late PreferencesService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService();
      prefs.resetForTesting();
      await prefs.init();

      DesktopLayoutState.activeNavTab.value = DesktopNavTab.home;
      DesktopLayoutState.globalSearchQuery.value = '';
      DesktopLayoutState.activePlaylistId.value = null;
      DesktopLayoutState.activeArtistName.value = null;
      DesktopLayoutState.activeAlbumData.value = null;
    });

    testWidgets('Focusing empty search pill opens Recent Searches dropdown', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await prefs.addRecentSearch({
        'id': 'artist-1',
        'title': 'Anuv Jain',
        'type': 'artist',
        'subtitle': 'Artist',
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopTopNavBar())),
      );

      // Initially, dropdown is not visible
      expect(find.byType(DesktopSearchDropdown), findsNothing);

      // Tap on search TextField to focus
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Dropdown should now be presented
      expect(find.byType(DesktopSearchDropdown), findsOneWidget);
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Anuv Jain'), findsOneWidget);
      expect(find.text('Artist • Artist'), findsOneWidget);
    });

    testWidgets(
      'Clicking item in dropdown routes in-place and closes overlay',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await prefs.addRecentSearch({
          'id': 'artist-arijit',
          'title': 'Arijit Singh',
          'type': 'artist',
          'subtitle': 'Playback Singer',
        });

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: DesktopTopNavBar())),
        );

        // Focus search bar
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        expect(find.byType(DesktopSearchDropdown), findsOneWidget);

        // Tap on Arijit Singh item
        await tester.tap(find.text('Arijit Singh'));
        await tester.pumpAndSettle();

        // Should update DesktopLayoutState in-place to artist profile
        expect(DesktopLayoutState.activeArtistName.value, 'Arijit Singh');
        expect(
          DesktopLayoutState.activeNavTab.value,
          DesktopNavTab.artistProfile,
        );

        // Dropdown should be dismissed
        expect(find.byType(DesktopSearchDropdown), findsNothing);
      },
    );

    testWidgets('Clicking remove icon deletes item from recent searches', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await prefs.addRecentSearch({
        'id': 'song-1',
        'title': 'Husn',
        'type': 'song',
        'subtitle': 'Anuv Jain',
      });
      await prefs.addRecentSearch({
        'id': 'album-1',
        'title': 'Rockstar',
        'type': 'album',
        'subtitle': 'A.R. Rahman',
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopTopNavBar())),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Husn'), findsOneWidget);
      expect(find.text('Rockstar'), findsOneWidget);

      // Find remove buttons (icons.close)
      final removeButtons = find.byIcon(Icons.close);
      expect(removeButtons, findsNWidgets(2));

      // Remove top item (Rockstar)
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Rockstar'), findsNothing);
      expect(find.text('Husn'), findsOneWidget);
      expect(prefs.getRecentSearches().length, 1);
    });

    testWidgets('Clear all button clears all recent searches', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await prefs.addRecentSearch({
        'id': 'song-1',
        'title': 'Tum Hi Ho',
        'type': 'song',
        'subtitle': 'Arijit Singh',
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopTopNavBar())),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Clear all'), findsOneWidget);
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('No recent searches'), findsOneWidget);
      expect(prefs.getRecentSearches(), isEmpty);
    });

    testWidgets('Pressing Escape dismisses the dropdown', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopTopNavBar())),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopSearchDropdown), findsOneWidget);

      // Send Escape key event
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopSearchDropdown), findsNothing);
    });
  });
}
