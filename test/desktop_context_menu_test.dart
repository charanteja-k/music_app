import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/desktop/desktop_context_menu.dart';
import 'package:music_app/widgets/song_options_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    PreferencesService().resetForTesting();
  });

  group('Pinning Persistence Tests (PreferencesService)', () {
    test('Default pinnedPlaylistIds is empty', () {
      final prefs = PreferencesService();
      expect(prefs.pinnedPlaylistIds, isEmpty);
      expect(prefs.isPlaylistPinned('pl_1'), isFalse);
    });

    test('togglePinPlaylist pins and unpins playlist', () async {
      final prefs = PreferencesService();
      await prefs.togglePinPlaylist('pl_1');
      expect(prefs.isPlaylistPinned('pl_1'), isTrue);
      expect(prefs.pinnedPlaylistIds, contains('pl_1'));

      await prefs.togglePinPlaylist('pl_1');
      expect(prefs.isPlaylistPinned('pl_1'), isFalse);
      expect(prefs.pinnedPlaylistIds, isEmpty);
    });
  });

  group('DesktopContextMenu Specifications & Permanent Guards', () {
    testWidgets(
      'Permanent Liked Songs Guard: strictly omits Delete and Unpin',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  capturedContext = ctx;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        final items = DesktopContextMenu.playlistItems(
          context: capturedContext,
          playlistId: 'liked_songs',
          playlistName: 'Liked Songs',
        );

        final titles = items.map((i) => i.title).whereType<String>().toList();
        expect(titles, contains('Add to queue'));
        expect(titles, contains('Play next'));
        expect(titles, contains('Share playlist'));

        // Permanent Liked Songs Guard: Must never contain Delete or Pin/Unpin
        expect(titles.any((t) => t.toLowerCase().contains('delete')), isFalse);
        expect(titles.any((t) => t.toLowerCase().contains('remove')), isFalse);
        expect(titles.any((t) => t.toLowerCase().contains('pin')), isFalse);
      },
    );

    testWidgets('Custom playlist generates Pin/Unpin and Delete actions', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final items = DesktopContextMenu.playlistItems(
        context: capturedContext,
        playlistId: 'custom_123',
        playlistName: 'Rock Classics',
      );

      final titles = items.map((i) => i.title).whereType<String>().toList();
      expect(titles, contains('Add to queue'));
      expect(titles, contains('Play next'));
      expect(titles, contains('Pin playlist'));
      expect(titles, contains('Delete playlist'));
      expect(titles, contains('Create playlist'));
      expect(titles, contains('Share playlist'));
    });

    testWidgets('Song menu generates full track actions', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final video = songMapToVideo({
        'id': 'abc123xyz00',
        'title': 'Tum Hi Ho',
        'author': 'Arijit Singh',
      });

      final items = DesktopContextMenu.songItems(
        context: capturedContext,
        song: video,
        currentPlaylistId: 'custom_pl_1',
      );

      final titles = items.map((i) => i.title).whereType<String>().toList();
      expect(titles, contains('Add to queue'));
      expect(titles, contains('Play next'));
      expect(titles, contains('Save to your Liked Songs'));
      expect(titles, contains('Add to playlist'));
      expect(titles, contains('Remove from this playlist'));
      expect(titles, contains('Go to artist'));
      expect(titles, contains('Go to album'));
      expect(titles, contains('Share song'));
    });

    testWidgets(
      'Song menu with queueIndex generates contextual queue actions',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  capturedContext = ctx;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        final video = songMapToVideo({
          'id': 'queue_song_1',
          'title': 'Kesariya',
          'author': 'Arijit Singh',
        });

        final items = DesktopContextMenu.songItems(
          context: capturedContext,
          song: video,
          queueIndex: 2,
        );

        final titles = items.map((i) => i.title).whereType<String>().toList();
        expect(titles, contains('Play Now'));
        expect(titles, contains('Move to Top'));
        expect(titles, contains('Remove from Queue'));
        expect(titles, contains('Save to Liked Songs'));
        expect(titles, contains('Add to Playlist'));
        expect(titles, contains('Go to Album'));
        expect(titles, contains('View Artist Profile'));
        expect(titles, contains('Share Song'));
        expect(titles.contains('Add to queue'), isFalse);
      },
    );

    testWidgets(
      'Song menu with isNowPlaying generates playback-appropriate actions',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  capturedContext = ctx;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        final video = songMapToVideo({
          'id': 'playing_song_1',
          'title': 'Channa Mereya',
          'author': 'Arijit Singh',
        });

        final items = DesktopContextMenu.songItems(
          context: capturedContext,
          song: video,
          isNowPlaying: true,
        );

        final titles = items.map((i) => i.title).whereType<String>().toList();
        expect(titles, contains('Save to Liked Songs'));
        expect(titles, contains('Add to Playlist'));
        expect(titles, contains('Start Song Radio'));
        expect(titles, contains('Go to Album'));
        expect(titles, contains('View Artist Profile'));
        expect(titles, contains('Share Song'));
        expect(titles.contains('Play Next'), isFalse);
        expect(titles.contains('Play next'), isFalse);
        expect(titles.contains('Add to queue'), isFalse);
      },
    );

    testWidgets('Album menu generates album actions', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final items = DesktopContextMenu.albumItems(
        context: capturedContext,
        albumTitle: 'Aashiqui 2',
        albumArtist: 'Mithoon, Ankit Tiwari',
        albumId: 'album_123',
      );

      final titles = items.map((i) => i.title).whereType<String>().toList();
      expect(titles, contains('Save to Your Library'));
      expect(titles, contains('Go to artist'));
      expect(titles, contains('Share album'));
    });

    testWidgets(
      'DesktopContextMenu.show renders popup menu at cursor position',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return GestureDetector(
                    onSecondaryTapDown: (details) {
                      DesktopContextMenu.show(
                        context: context,
                        globalPosition: details.globalPosition,
                        items: [
                          DesktopContextMenuItem(
                            title: 'Test Option 1',
                            icon: Icons.check,
                            onTap: () {},
                          ),
                          const DesktopContextMenuItem.divider(),
                          DesktopContextMenuItem(
                            title: 'Test Option 2',
                            icon: Icons.star,
                            onTap: () {},
                          ),
                        ],
                      );
                    },
                    child: Container(
                      width: 300,
                      height: 300,
                      color: Colors.blue,
                    ),
                  );
                },
              ),
            ),
          ),
        );

        // Trigger secondary tap (right-click) at (100, 100)
        final gesture = await tester.startGesture(
          const Offset(100, 100),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('Test Option 1'), findsOneWidget);
        expect(find.text('Test Option 2'), findsOneWidget);
      },
    );
  });
}
