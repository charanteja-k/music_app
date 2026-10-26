import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/custom_playlist_screen.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/mini_player.dart';
import 'package:music_app/widgets/playlist_action_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MusicService musicService;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    SharedPreferences.setMockInitialValues({
      'listeningHistoryJson': '[]',
      'searchHistory': <String>[],
      'spotify_imported_playlist_ids': <String>[],
    });
    await PreferencesService().init();

    musicService = MusicService();
    musicService.customPlaylists.clear();
    musicService.customPlaylists.add({
      'id': 'test_playlist_opened',
      'name': 'Telugu Party Hits',
      'songs': [
        {
          'id': 'dQw4w9WgXcQ',
          'title': 'Samajavaragamana',
          'author': 'Sid Sriram',
          'thumbnail': 'https://example.com/1.jpg',
        },
        {
          'id': 'kJQP7kiw5Fk',
          'title': 'Butta Bomma',
          'author': 'Armaan Malik',
          'thumbnail': 'https://example.com/2.jpg',
        },
      ],
    });
  });

  testWidgets(
    'Opened playlist controls: Play button and More button exist, no mini-player',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomPlaylistScreen(playlistId: 'test_playlist_opened'),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Play button is present
      final playButtonFinder = find.widgetWithText(ElevatedButton, 'Play');
      expect(playButtonFinder, findsOneWidget);

      // 2. Verify PlaylistActionMenu (More button) is present immediately beside Play
      final moreMenuFinder = find.byType(PlaylistActionMenu);
      expect(moreMenuFinder, findsOneWidget);

      // 3. Verify No MiniPlayer is present on the screen
      expect(find.byType(MiniPlayer), findsNothing);

      // 4. Verify no separate pencil/edit or trash/delete icons beside Play button
      // Search for edit icon beside Play (should only appear inside the popup menu when opened)
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);

      // 5. Tap the More button to open options
      await tester.tap(moreMenuFinder);
      await tester.pumpAndSettle();

      // 6. Verify Rename and Delete options are accessible through the More menu
      expect(find.text('Rename playlist'), findsOneWidget);
      expect(find.text('Delete playlist'), findsOneWidget);

      // 7. Test Rename flow
      await tester.tap(find.text('Rename playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Playlist'), findsOneWidget);
      final dialogTextField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogTextField, 'Telugu Mega Hits');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        musicService.customPlaylists.first['name'],
        equals('Telugu Mega Hits'),
      );
    },
  );

  testWidgets(
    'Opened playlist controls: Delete playlist pops screen after confirmation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomPlaylistScreen(
                      playlistId: 'test_playlist_opened',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to CustomPlaylistScreen
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Telugu Party Hits'), findsWidgets);

      // Tap More button
      await tester.tap(find.byType(PlaylistActionMenu));
      await tester.pumpAndSettle();

      // Tap Delete
      await tester.tap(find.text('Delete playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Playlist'), findsOneWidget);

      // Confirm delete in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify playlist is removed from musicService
      expect(musicService.customPlaylists.isEmpty, isTrue);

      // Verify screen popped back to previous route
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets(
    'Playlist song rows expose three-dot More action and preserve presentation and reorder handle',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomPlaylistScreen(playlistId: 'test_playlist_opened'),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify song presentation intact
      expect(find.text('Samajavaragamana'), findsOneWidget);
      expect(find.text('Sid Sriram'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // 2. Verify drag handle exists
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));

      // 3. Verify song More button exists on each row
      final song1More = find.byKey(
        const ValueKey('playlist_song_more_dQw4w9WgXcQ'),
      );
      expect(song1More, findsOneWidget);

      // 4. Tap the song More button
      await tester.tap(song1More);
      await tester.pumpAndSettle();

      // 5. Verify song options bottom sheet is displayed with relevant actions
      expect(find.text('Play'), findsWidgets);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Like Song'), findsOneWidget);
      expect(find.text('Remove from Playlist'), findsOneWidget);

      // 6. Test Remove from Playlist action
      await tester.tap(find.text('Remove from Playlist'));
      await tester.pumpAndSettle();

      // 7. Verify song_1 was removed from the playlist
      final remainingSongs =
          musicService.customPlaylists.first['songs'] as List;
      expect(remainingSongs.length, equals(1));
      expect(remainingSongs.first['id'], equals('kJQP7kiw5Fk'));
    },
  );

  testWidgets(
    'Screen-level mini-player policy allows mini-player in opened playlist',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Initially, mini-player visibility is active
      expect(MiniPlayer.isVisible.value, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CustomPlaylistScreen(
                              playlistId: 'test_playlist_opened',
                            ),
                          ),
                        );
                      },
                      child: const Text('Open Playlist'),
                    ),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: MiniPlayer(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Open CustomPlaylistScreen
      await tester.tap(find.text('Open Playlist'));
      await tester.pumpAndSettle();

      // 3. MiniPlayer policy remains visible while playlist screen is active
      expect(MiniPlayer.isVisible.value, isTrue);

      // Verify opened playlist screen has play button intact
      expect(find.widgetWithText(ElevatedButton, 'Play'), findsOneWidget);

      // 4. Leaving playlist screen via back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      // 5. Leaving playlist screen preserves normal mini-player visibility
      expect(MiniPlayer.isVisible.value, isTrue);
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Open Playlist'), findsOneWidget);
    },
  );

  testWidgets(
    'MiniPlayer widget collapses to zero size when MiniPlayer.isVisible is false',
    (WidgetTester tester) async {
      MiniPlayer.isVisible.value = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MiniPlayer())),
      );
      await tester.pump();
      expect(find.byType(MiniPlayer), findsOneWidget);

      MiniPlayer.hide();
      await tester.pumpAndSettle();
      expect(MiniPlayer.isVisible.value, isFalse);
      expect(tester.getSize(find.byType(MiniPlayer)), equals(Size.zero));

      MiniPlayer.show();
      await tester.pumpAndSettle();
      expect(MiniPlayer.isVisible.value, isTrue);
    },
  );
}
