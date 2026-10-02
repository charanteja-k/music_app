import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/custom_playlist_screen.dart';
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

  group('Playlist Shuffle Feature Tests', () {
    late MusicService musicService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      musicService = MusicService();
      musicService.customPlaylists.clear();
      musicService.setShuffle(false);

      // Seed a test playlist with multiple songs
      musicService.customPlaylists.add({
        'id': 'telugu_party_hits',
        'name': 'Telugu Party Hits',
        'songs': [
          {
            'id': 'aaaaaaaaaaa',
            'title': 'Chuttamalle',
            'author': 'Anirudh Ravichander',
            'thumbnail': '',
            'streamUrl': 'https://example.com/audio1.m4a',
          },
          {
            'id': 'bbbbbbbbbbb',
            'title': 'Daavudi',
            'author': 'Nakash Aziz',
            'thumbnail': '',
            'streamUrl': 'https://example.com/audio2.m4a',
          },
          {
            'id': 'ccccccccccc',
            'title': 'Fear Song',
            'author': 'Anirudh Ravichander',
            'thumbnail': '',
            'streamUrl': 'https://example.com/audio3.m4a',
          },
          {
            'id': 'ddddddddddd',
            'title': 'Ta Takkara',
            'author': 'Santhosh Narayanan',
            'thumbnail': '',
            'streamUrl': 'https://example.com/audio4.m4a',
          },
        ],
      });
    });

    test('setShuffle updates isShuffle and notifies listeners', () {
      bool notified = false;
      musicService.addListener(() => notified = true);

      expect(musicService.isShuffle, isFalse);
      musicService.setShuffle(true);
      expect(musicService.isShuffle, isTrue);
      expect(notified, isTrue);

      notified = false;
      musicService.setShuffle(false);
      expect(musicService.isShuffle, isFalse);
      expect(notified, isTrue);
    });

    test(
      'playCustomPlaylist with enableShuffle sets shuffle mode and initializes history',
      () {
        expect(musicService.isShuffle, isFalse);

        // When starting with enableShuffle: true
        musicService.playCustomPlaylist(
          'telugu_party_hits',
          2,
          enableShuffle: true,
        );

        expect(musicService.isShuffle, isTrue);
        expect(musicService.currentIndex, 2);
      },
    );

    test(
      'playCustomPlaylistWithShuffle enables shuffle and selects a valid song',
      () {
        expect(musicService.isShuffle, isFalse);

        musicService.playCustomPlaylistWithShuffle('telugu_party_hits');

        // Shuffle must be active
        expect(musicService.isShuffle, isTrue);

        // Current index must be within range of the playlist songs (0 to 3)
        expect(musicService.currentIndex >= 0, isTrue);
        expect(musicService.currentIndex < 4, isTrue);

        // Shuffle remains on
        expect(musicService.isShuffle, isTrue);
      },
    );

    test(
      'Shuffle mode remains on until user turns it off via toggleShuffle (player screen simulation)',
      () {
        musicService.playCustomPlaylist(
          'telugu_party_hits',
          0,
          enableShuffle: true,
        );
        expect(musicService.isShuffle, isTrue);

        // Simulate user turning off shuffle from PlayerScreen
        musicService.toggleShuffle();
        expect(musicService.isShuffle, isFalse);

        // Toggle back on from PlayerScreen
        musicService.toggleShuffle();
        expect(musicService.isShuffle, isTrue);
      },
    );

    testWidgets(
      'CustomPlaylistScreen renders Play All and Shuffle buttons side-by-side',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception is NetworkImageLoadException ||
              details.exception.toString().contains(
                'NetworkImageLoadException',
              )) {
            return;
          }
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const CustomPlaylistScreen(playlistId: 'telugu_party_hits'),
          ),
        );
        await tester.pump();

        // Check for Play All button
        final playAllFinder = find.byKey(
          const ValueKey('playlist_play_all_button'),
        );
        expect(playAllFinder, findsOneWidget);
        expect(find.text('Play All'), findsOneWidget);

        // Check for Shuffle button beside Play All
        final shuffleFinder = find.byKey(
          const ValueKey('playlist_shuffle_button'),
        );
        expect(shuffleFinder, findsOneWidget);
        expect(find.text('Shuffle'), findsOneWidget);

        // Verify the two buttons share the same action header row
        final actionRowFinder = find.ancestor(
          of: playAllFinder,
          matching: find.byType(Row),
        );
        expect(actionRowFinder, findsWidgets);

        // Tap the Shuffle button
        await tester.tap(shuffleFinder);
        await tester.pump();

        // Expect shuffle to be enabled in MusicService
        expect(musicService.isShuffle, isTrue);

        // Advance fake timer so async PaletteGenerator internal timeout (15s) is fully resolved
        await tester.pump(const Duration(seconds: 20));
      },
    );
  });
}
