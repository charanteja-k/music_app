import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/library_screen.dart';
import 'package:music_app/services/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.just_audio.methods'),
    (call) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map?)?['id'] as String?;
        if (id != null) {
          messenger.setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (subCall) async {
              if (subCall.method == 'load') {
                return {'duration': 180000000};
              }
              return {};
            },
          );
        }
      }
      return {};
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '.',
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('home_widget'),
    (call) async => null,
  );

  group('LibraryScreen Playlist Three Dots & Options Redesign Tests', () {
    late MusicService musicService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      musicService = MusicService();
      musicService.customPlaylists.clear();
      musicService.customPlaylists.add({
        'id': 'my_party_playlist',
        'name': 'Party Vibes',
        'songs': [
          {
            'id': 'song_1111111',
            'title': 'Chuttamalle',
            'author': 'Anirudh',
            'thumbnail': '',
          },
        ],
      });
    });

    testWidgets(
      'Playlist item displays Play button followed by Three Dots button, and no pencil or bin icons',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: ThemeData.dark(), home: const LibraryScreen()),
        );
        await tester.pumpAndSettle();

        // Switch to Playlists tab (Tab index 2: Liked Songs, Downloads, Playlists, History)
        final playlistsTabFinder = find.text('Playlists');
        expect(playlistsTabFinder, findsOneWidget);
        await tester.tap(playlistsTabFinder);
        await tester.pumpAndSettle();

        // Verify playlist item is present
        expect(find.text('Party Vibes'), findsOneWidget);

        // Verify top-right Import / Exportify button remains present
        expect(find.text('Import / Exportify'), findsOneWidget);

        // Verify New Playlist button is present in the header
        expect(find.byTooltip('New Playlist'), findsOneWidget);

        // Verify the old 'Import from Spotify' icon beside New Playlist is REMOVED
        expect(find.byTooltip('Import from Spotify'), findsNothing);

        // Verify pencil (Icons.edit_outlined) and bin (Icons.delete_outline) are REMOVED from the row
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        // Verify Play button is present
        final playButtonFinder = find.byKey(
          const ValueKey('playlist_play_my_party_playlist'),
        );
        expect(playButtonFinder, findsOneWidget);

        // Verify Three Dots button is present
        final optionsButtonFinder = find.byKey(
          const ValueKey('playlist_options_my_party_playlist'),
        );
        expect(optionsButtonFinder, findsOneWidget);

        // Verify Three Dots icon is positioned AFTER Play button horizontally
        final playCenter = tester.getCenter(playButtonFinder);
        final optionsCenter = tester.getCenter(optionsButtonFinder);
        expect(
          optionsCenter.dx > playCenter.dx,
          isTrue,
          reason: 'Three dots icon must appear after the play button',
        );

        // Tap the Three Dots button to open the bottom sheet
        await tester.tap(optionsButtonFinder);
        await tester.pumpAndSettle();

        // Verify bottom sheet header and named options appear
        expect(
          find.byKey(const ValueKey('option_play_playlist')),
          findsOneWidget,
        );
        expect(find.text('Play Playlist'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('option_shuffle_playlist')),
          findsOneWidget,
        );
        expect(find.text('Shuffle Playlist'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('option_rename_playlist')),
          findsOneWidget,
        );
        expect(find.text('Rename Playlist'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('option_delete_playlist')),
          findsOneWidget,
        );
        expect(find.text('Delete Playlist'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Rename Playlist in options sheet opens rename dialog',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: ThemeData.dark(), home: const LibraryScreen()),
        );
        await tester.pumpAndSettle();

        // Switch to Playlists tab
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();

        // Tap 3-dots button
        await tester.tap(
          find.byKey(const ValueKey('playlist_options_my_party_playlist')),
        );
        await tester.pumpAndSettle();

        // Tap Rename Playlist named option
        await tester.tap(find.byKey(const ValueKey('option_rename_playlist')));
        await tester.pumpAndSettle();

        // Verify rename dialog opened
        expect(find.text('Rename Playlist'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Delete Playlist in options sheet opens delete dialog',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: ThemeData.dark(), home: const LibraryScreen()),
        );
        await tester.pumpAndSettle();

        // Switch to Playlists tab
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();

        // Tap 3-dots button
        await tester.tap(
          find.byKey(const ValueKey('playlist_options_my_party_playlist')),
        );
        await tester.pumpAndSettle();

        // Tap Delete Playlist named option
        await tester.tap(find.byKey(const ValueKey('option_delete_playlist')));
        await tester.pumpAndSettle();

        // Verify delete confirmation dialog opened
        expect(find.text('Delete Playlist'), findsOneWidget);
        expect(
          find.text('Are you sure you want to delete "Party Vibes"?'),
          findsOneWidget,
        );
        expect(find.text('Delete'), findsOneWidget);
      },
    );
  });
}
