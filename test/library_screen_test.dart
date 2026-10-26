import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/library_screen.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    SharedPreferences.setMockInitialValues({
      'listeningHistoryJson': '[]',
      'searchHistory': <String>[],
    });
    await PreferencesService().init();
  });

  testWidgets(
    'LibraryScreen renders mobile layout with tabs and without green import button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Your Library'), findsOneWidget);

      // Verify green AppBar action button is gone
      expect(find.text('Import / Exportify'), findsNothing);

      // Verify Add/Create playlist control is available
      expect(find.byTooltip('Create New Playlist'), findsOneWidget);

      // Verify mobile filter chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('My Playlists'), findsOneWidget);
      expect(find.text('Imported'), findsOneWidget);
      expect(find.text('Saved Albums'), findsOneWidget);
    },
  );

  testWidgets('LibraryScreen switches sections smoothly in mobile layout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    // Tap on Saved Albums filter chip
    await tester.scrollUntilVisible(find.text('Saved Albums'), 100);
    await tester.tap(find.text('Saved Albums'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Tap on Imported filter chip
    await tester.tap(find.text('Imported'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Tap on My Playlists filter chip
    await tester.tap(find.text('My Playlists'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'LibraryScreen renders desktop layout with sidebar and panel architecture',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Your Library'), findsOneWidget);

      // Verify desktop sidebar navigation items
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Spotify Imports'), findsOneWidget);
      expect(find.text('Listening History'), findsOneWidget);

      // Verify Add/Create playlist button in sidebar header
      expect(find.byTooltip('Create New Playlist'), findsOneWidget);

      // Tap Albums in sidebar
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap Spotify Imports in sidebar
      await tester.tap(find.text('Spotify Imports'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Import from Spotify / CSV'), findsOneWidget);

      // Tap Liked Songs in sidebar
      await tester.tap(find.text('Liked Songs'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Create New Playlist dialog opens when Add button is pressed', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    final addBtn = find.byTooltip('Create New Playlist');
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(find.text('Create New Playlist'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets(
    'Playlist row contains artwork, name, track count, play button, and more button without separate edit/trash buttons',
    (WidgetTester tester) async {
      final musicService = MusicService();
      final pid = musicService.createPlaylist('Late Night Vibes');
      addTearDown(() async {
        await musicService.deletePlaylist(pid);
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      // Playlist name and track count are displayed
      expect(find.text('Late Night Vibes'), findsOneWidget);
      expect(find.textContaining('0 tracks'), findsWidgets);

      // Artwork / queue icon is displayed
      expect(find.byIcon(Icons.queue_music_rounded), findsWidgets);

      // Single Play button is displayed
      expect(find.byKey(ValueKey('playlist_play_$pid')), findsOneWidget);

      // Single Three-dot More button is displayed
      expect(find.byKey(ValueKey('playlist_more_$pid')), findsOneWidget);

      // Verify separate edit/pencil and delete/trash icons do NOT exist in the row
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byTooltip('Rename playlist'), findsNothing);
      expect(find.byTooltip('Delete playlist'), findsNothing);
    },
  );

  testWidgets(
    'Playlist More menu opens and exposes Rename and Delete options',
    (WidgetTester tester) async {
      final musicService = MusicService();
      final pid = musicService.createPlaylist('Workout Beats');
      addTearDown(() async {
        await musicService.deletePlaylist(pid);
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Workout Beats'), findsOneWidget);

      // Tap on the More options button
      final moreBtn = find.byKey(ValueKey('playlist_more_$pid'));
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Verify Rename and Delete options are visible in the opened menu
      expect(find.text('Rename playlist'), findsOneWidget);
      expect(find.text('Delete playlist'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // Tap Rename to verify it triggers rename dialog
      await tester.tap(find.text('Rename playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Playlist'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Playlist More menu Delete option triggers confirmation dialog', (
    WidgetTester tester,
  ) async {
    final musicService = MusicService();
    final pid = musicService.createPlaylist('Chill Acoustic');
    addTearDown(() async {
      await musicService.deletePlaylist(pid);
    });

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Chill Acoustic'), findsOneWidget);

    // Tap More options button
    final moreBtn = find.byKey(ValueKey('playlist_more_$pid'));
    await tester.tap(moreBtn);
    await tester.pumpAndSettle();

    // Tap Delete
    await tester.tap(find.text('Delete playlist'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Delete Playlist'), findsOneWidget);
    expect(
      find.text('Are you sure you want to delete "Chill Acoustic"?'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsWidgets);

    // Cancel deletion
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.text('Are you sure you want to delete "Chill Acoustic"?'),
      findsNothing,
    );
  });

  testWidgets(
    'Playlist segregation: filter pills switch between All, Created by You, and Spotify Imports',
    (WidgetTester tester) async {
      final musicService = MusicService();
      final prefs = PreferencesService();

      final personalPid = musicService.createPlaylist(
        'My Indie Faves',
        isSpotify: false,
        source: 'custom',
      );
      await prefs.registerManualPlaylistId(personalPid);

      final spotifyPid = musicService.createPlaylist(
        'Spotify Top Hits',
        isSpotify: true,
        source: 'spotify',
      );
      await prefs.registerSpotifyPlaylistId(spotifyPid);

      addTearDown(() async {
        await musicService.deletePlaylist(personalPid);
        await musicService.deletePlaylist(spotifyPid);
        await prefs.unregisterManualPlaylistId(personalPid);
        await prefs.unregisterSpotifyPlaylistId(spotifyPid);
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      // Verify filter pills exist
      expect(find.text('All'), findsOneWidget);
      expect(find.text('My Playlists'), findsOneWidget);
      expect(find.text('Imported'), findsWidgets);

      // In "All" tab: both playlists are visible
      expect(find.text('My Indie Faves'), findsOneWidget);
      expect(find.text('Spotify Top Hits'), findsOneWidget);
      expect(find.text('Spotify'), findsWidgets); // badge

      // Tap "My Playlists" filter pill
      await tester.tap(find.byKey(const ValueKey('filter_pill_personal')));
      await tester.pumpAndSettle();

      expect(find.text('My Indie Faves'), findsOneWidget);
      expect(find.text('Spotify Top Hits'), findsNothing);

      // Tap "Imported" filter pill
      await tester.tap(find.byKey(const ValueKey('filter_pill_spotify')));
      await tester.pumpAndSettle();

      expect(find.text('My Indie Faves'), findsNothing);
      expect(find.text('Spotify Top Hits'), findsOneWidget);
    },
  );

  testWidgets(
    'Existing imported playlist with tracks and no manual tag automatically resolves to Spotify Imports',
    (WidgetTester tester) async {
      final musicService = MusicService();
      final prefs = PreferencesService();

      // Seed a legacy imported playlist that only has tracks, no explicit manual tag
      final importedPid = musicService.createPlaylist('Late Night Lo-Fi');
      final pl = musicService.customPlaylists.firstWhere(
        (p) => p['id'] == importedPid,
      );
      pl['songs'] = [
        {'id': 'track1', 'title': 'Midnight Walk', 'author': 'Chilled'},
      ];

      addTearDown(() async {
        await musicService.deletePlaylist(importedPid);
        await prefs.unregisterSpotifyPlaylistId(importedPid);
        await prefs.unregisterManualPlaylistId(importedPid);
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await tester.pumpAndSettle();

      // Tap "Spotify Imports" filter pill
      await tester.tap(find.byKey(const ValueKey('filter_pill_spotify')));
      await tester.pumpAndSettle();

      expect(find.text('Late Night Lo-Fi'), findsOneWidget);

      // Tap "Created by You" filter pill
      await tester.tap(find.byKey(const ValueKey('filter_pill_personal')));
      await tester.pumpAndSettle();

      expect(find.text('Late Night Lo-Fi'), findsNothing);
    },
  );

  testWidgets('LibraryScreen renders Device Audio section properly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    await tester.pumpAndSettle();

    // Tap on Device section in sidebar
    await tester.tap(find.text('Device Audio'));
    await tester.pumpAndSettle();

    expect(find.text('No on-device music found'), findsOneWidget);
    expect(find.text('Scan Storage'), findsOneWidget);
    expect(find.text('Pick Folder'), findsOneWidget);
    expect(find.text('Add Files'), findsOneWidget);
  });
}
