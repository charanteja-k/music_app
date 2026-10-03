import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/jio_album.dart';
import 'package:music_app/screens/album_screen.dart';
import 'package:music_app/services/api_config.dart';
import 'package:music_app/services/canonical_song_dedup.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  group('JioAlbum and ApiConfig tests', () {
    test('ApiConfig respects customServerUrl for album endpoints', () async {
      await PreferencesService().setCustomServerUrl(
        'https://custom-edge.example.com',
      );

      final searchUri = ApiConfig.jioAlbumSearchUri('Devara');
      expect(
        searchUri.toString(),
        startsWith('https://custom-edge.example.com/jio/albums'),
      );

      final detailUri = ApiConfig.jioAlbumDetailUri('album_123');
      expect(
        detailUri.toString(),
        startsWith('https://custom-edge.example.com/jio/album'),
      );
    });

    test(
      'isLikelyYouTubeId correctly distinguishes genuine vs synthetic IDs',
      () {
        // Genuine 11-char YouTube IDs
        expect(CanonicalSongDedup.isLikelyYouTubeId('dQw4w9WgXcQ'), isTrue);
        expect(CanonicalSongDedup.isLikelyYouTubeId('M7lc1UVf-VE'), isTrue);
        expect(CanonicalSongDedup.isLikelyYouTubeId('9bZkp7q19f0'), isTrue);

        // Synthetic JioSaavn numeric IDs
        expect(CanonicalSongDedup.isLikelyYouTubeId('12345678901'), isFalse);

        // Synthetic padded JioSaavn IDs ending with 000 or 00
        expect(CanonicalSongDedup.isLikelyYouTubeId('UxmV2H70000'), isFalse);
        expect(CanonicalSongDedup.isLikelyYouTubeId('c-u74lK0000'), isFalse);
        expect(CanonicalSongDedup.isLikelyYouTubeId('bX87aKs9000'), isFalse);
        expect(CanonicalSongDedup.isLikelyYouTubeId('bX87aKs9100'), isFalse);

        // Non-11 length IDs
        expect(CanonicalSongDedup.isLikelyYouTubeId('short'), isFalse);
        expect(
          CanonicalSongDedup.isLikelyYouTubeId('toolongidentifier123'),
          isFalse,
        );
      },
    );
  });

  group('AlbumScreen Widget Tests', () {
    final testAlbum = JioAlbum(
      id: 'album_456',
      title: 'Devara Part 1',
      artist: 'Anirudh Ravichander',
      artwork: 'https://example.com/devara.jpg',
      year: '2024',
      songCount: 3,
      language: 'Telugu',
      songs: [
        {
          'id': 's1_0000000',
          'title': 'Fear Song',
          'author': 'Anirudh Ravichander',
          'duration': 195,
          'trackNumber': 0, // Edge endpoint returns 0
          'streamUrl': 'https://example.com/fear.mp4',
        },
        {
          'id': 's2_0000000',
          'title': 'Chuttamalle',
          'author': 'Shilpa Rao, Anirudh',
          'duration': 210,
          'trackNumber': 0, // Edge endpoint returns 0
          'streamUrl': 'https://example.com/chuttamalle.mp4',
        },
        {
          'id': 's3_0000000',
          'title': 'Daavudi',
          'author': 'Nakash Aziz, Akasa',
          'duration': 180,
          'trackNumber': 0, // Edge endpoint returns 0
          'streamUrl': 'https://example.com/daavudi.mp4',
        },
      ],
    );

    testWidgets(
      'AlbumScreen renders track numbers 1, 2, 3 instead of 0 for unindexed tracks',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: AlbumScreen(
              album: testAlbum,
              albumId: testAlbum.id,
              albumTitle: testAlbum.title,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Header info
        expect(find.text('Devara Part 1'), findsWidgets);
        expect(find.text('Anirudh Ravichander'), findsWidgets);
        expect(find.text('Play All'), findsOneWidget);
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

        // Songs are listed
        expect(find.text('Fear Song'), findsOneWidget);
        expect(find.text('Chuttamalle'), findsOneWidget);
        expect(find.text('Daavudi'), findsOneWidget);

        // Track numbers must be 1, 2, 3 (not 0)
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('0'), findsNothing);

        // 3-dots button should have tooltip 'Song options'
        final moreButtons = find.byTooltip('Song options');
        expect(moreButtons, findsNWidgets(3));

        // Hero widget on cover art matches 'album-art-album_456'
        final heroFinder = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == 'album-art-album_456',
        );
        expect(heroFinder, findsOneWidget);
      },
    );
  });
}
