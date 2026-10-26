import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/custom_playlist_screen.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/utils/image_utils.dart';
import 'package:music_app/widgets/playlist_action_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageUtils High-Resolution Pipeline Tests', () {
    test('Converts JioSaavn low-res URLs to 500x500', () {
      const saavn50 = 'https://c.saavncdn.com/123/Song_50x50.jpg';
      const saavn150 = 'https://c.saavncdn.com/123/Song_150x150.jpg';

      expect(
        ImageUtils.toHighResUrl(saavn50),
        equals('https://c.saavncdn.com/123/Song_500x500.jpg'),
      );
      expect(
        ImageUtils.toHighResUrl(saavn150),
        equals('https://c.saavncdn.com/123/Song_500x500.jpg'),
      );
    });

    test('Converts YouTube low-res thumbnail URLs to hqdefault', () {
      const ytDefault = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg';
      const ytMq = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';

      expect(
        ImageUtils.toHighResUrl(ytDefault),
        equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      );
      expect(
        ImageUtils.toHighResUrl(ytMq),
        equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      );
    });

    test('Converts Spotify CDN URLs to 640x640 CDN hash', () {
      const spotify300 =
          'https://i.scdn.co/image/ab67616d00001e021234567890abcdef12345678';
      const spotify64 =
          'https://i.scdn.co/image/ab67616d000048511234567890abcdef12345678';

      expect(
        ImageUtils.toHighResUrl(spotify300),
        equals(
          'https://i.scdn.co/image/ab67616d0000b2731234567890abcdef12345678',
        ),
      );
      expect(
        ImageUtils.toHighResUrl(spotify64),
        equals(
          'https://i.scdn.co/image/ab67616d0000b2731234567890abcdef12345678',
        ),
      );
    });
  });

  group('Spotify Desktop Hero Banner & Controls Suite', () {
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
        'spotify_imported_playlist_ids': <String>['test_spotify_import'],
      });
      await PreferencesService().init();

      musicService = MusicService();
      musicService.customPlaylists.clear();
      musicService.customPlaylists.addAll([
        {
          'id': 'test_desktop_mosaic',
          'name': 'Tollywood Bangers',
          'description': 'The most energetic Telugu tracks of the decade.',
          'songs': [
            {
              'id': 's1',
              'title': 'Song One',
              'author': 'Artist A',
              'thumbnail': 'https://c.saavncdn.com/1/Song1_150x150.jpg',
              'durationMs': 215000,
            },
            {
              'id': 's2',
              'title': 'Song Two',
              'author': 'Artist B',
              'thumbnail': 'https://c.saavncdn.com/2/Song2_150x150.jpg',
              'durationMs': 180000,
            },
            {
              'id': 's3',
              'title': 'Song Three',
              'author': 'Artist C',
              'thumbnail': 'https://c.saavncdn.com/3/Song3_150x150.jpg',
              'durationMs': 240000,
            },
            {
              'id': 's4',
              'title': 'Song Four',
              'author': 'Artist D',
              'thumbnail': 'https://c.saavncdn.com/4/Song4_150x150.jpg',
              'durationMs': 200000,
            },
          ],
        },
        {
          'id': 'test_spotify_import',
          'name': 'My Spotify Favorites',
          'songs': [
            {
              'id': 'sp1',
              'title': 'Imported Track',
              'author': 'Imported Artist',
              'thumbnail': 'https://i.ytimg.com/vi/sample1/default.jpg',
              'durationMs': 195000,
            },
          ],
        },
      ]);
    });

    testWidgets(
      'Desktop horizontal hero banner renders with 4-track mosaic, metadata and control strip',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CustomPlaylistScreen(playlistId: 'test_desktop_mosaic'),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Tag and title
        expect(find.text('PUBLIC PLAYLIST'), findsOneWidget);
        expect(find.text('Tollywood Bangers'), findsWidgets);
        expect(
          find.text('The most energetic Telugu tracks of the decade.'),
          findsOneWidget,
        );

        // 2. Track count and duration chips
        expect(find.text('4 songs'), findsOneWidget);
        expect(find.textContaining('min'), findsWidgets);

        // 3. Spotify Green Play Button (52x52 circular button)
        final playButton = find.widgetWithText(ElevatedButton, 'Play');
        expect(playButton, findsOneWidget);

        // 4. Shuffle, Pin, and More buttons exist
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
        expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
        expect(find.byType(PlaylistActionMenu), findsOneWidget);

        // 5. Verify cover hover overlay is not visible when unhovered
        expect(find.text('Choose photo'), findsNothing);
      },
    );

    testWidgets(
      'Desktop hero banner identifies Spotify Import tag accurately',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CustomPlaylistScreen(playlistId: 'test_spotify_import'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SPOTIFY IMPORT'), findsOneWidget);
        expect(find.text('My Spotify Favorites'), findsWidgets);
        expect(find.text('1 song'), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile viewport (< 1024px) preserves compact vertical layout and SliverAppBar',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CustomPlaylistScreen(playlistId: 'test_desktop_mosaic'),
          ),
        );
        await tester.pumpAndSettle();

        // On mobile, the SliverAppBar is active
        expect(find.byType(SliverAppBar), findsOneWidget);
        expect(find.text('PUBLIC PLAYLIST'), findsNothing);
        expect(find.text('Tollywood Bangers'), findsWidgets);
      },
    );
  });
}
