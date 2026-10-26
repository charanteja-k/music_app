import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/jio_album.dart';
import 'package:music_app/screens/curated_playlist_screen.dart';
import 'package:music_app/services/trending_catalog_service.dart';
import 'package:music_app/services/youtube_music_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SEO Spam & Junk Negative Regex Filter Tests', () {
    test('Identifies and drops keyword-stuffed and marketing spam cuts', () {
      final spamTitles = [
        'Kesariya (Trending Version)',
        'Chuttamalle (1 Min Mix)',
        'Tauba Tauba - Reels Version',
        'Pushpa 2 Theme (Viral Version)',
        'Illuminati (Sped Up)',
        'Aasa Kooda (Slowed + Reverb)',
        'Classic Bollywood Soundtrack Vol. 1',
        'Kishore Kumar Greatest Hits',
        'Best of Lata Mangeshkar',
        'Telugu Non-Stop Party Mix 2024',
        'Ilaiyaraaja Jukebox All Songs',
        'Retro Romantic Compilation',
        'Golden Era Classics',
        '80s Hindi Film Archive',
      ];

      for (final title in spamTitles) {
        expect(
          TrendingCatalogService.isSpamOrJunk(title),
          isTrue,
          reason: 'Expected "$title" to be caught by spam filter',
        );
      }
    });

    test('Allows genuine song and soundtrack titles to pass through clean', () {
      final genuineTitles = [
        'Kesariya',
        'Tauba Tauba',
        'Chuttamalle',
        'Devara Part 1 (Original Motion Picture Soundtrack)',
        'Kalki 2898 AD',
        'Pushpa 2 The Rule',
        'Hukum - Thalaivar Alappara',
        'Naa Ready',
        'Fear Song',
        'Animal',
      ];

      for (final title in genuineTitles) {
        expect(
          TrendingCatalogService.isSpamOrJunk(title),
          isFalse,
          reason: 'Expected genuine title "$title" to NOT be flagged as spam',
        );
      }
    });
  });

  group('Modern Album Filter & Governance Tests', () {
    test(
      'Enforces release date >= 2018 for blockbuster soundtracks & albums',
      () {
        const modernAlbum = JioAlbum(
          id: '101',
          title: 'Devara Part 1',
          artist: 'Anirudh Ravichander',
          artwork: 'https://c.saavncdn.com/devara-500x500.jpg',
          year: '2024',
          songCount: 6,
          language: 'telugu',
        );

        const retroCompilation = JioAlbum(
          id: '102',
          title: 'Superhit Old Songs',
          artist: 'K. J. Yesudas',
          artwork: 'https://c.saavncdn.com/retro-500x500.jpg',
          year: '1978',
          songCount: 15,
          language: 'malayalam',
        );

        const spamCutAlbum = JioAlbum(
          id: '103',
          title: 'Bollywood Greatest Hits Compilation',
          artist: 'Various Artists',
          artwork: 'https://c.saavncdn.com/hits-500x500.jpg',
          year: '2022',
          songCount: 20,
          language: 'hindi',
        );

        expect(
          TrendingCatalogService.isGenuineModernAlbum(modernAlbum),
          isTrue,
        );
        expect(
          TrendingCatalogService.isGenuineModernAlbum(retroCompilation),
          isFalse,
        );
        expect(
          TrendingCatalogService.isGenuineModernAlbum(spamCutAlbum),
          isFalse,
        );
      },
    );

    test('Allows archive albums only when explicitly permitted', () {
      const vintageSoundtrack = JioAlbum(
        id: '104',
        title: 'Sholay (Original Soundtrack)',
        artist: 'R. D. Burman',
        artwork: 'https://c.saavncdn.com/sholay-500x500.jpg',
        year: '1975',
        songCount: 5,
        language: 'hindi',
      );

      expect(
        TrendingCatalogService.isGenuineModernAlbum(
          vintageSoundtrack,
          allowArchive: false,
        ),
        isFalse,
      );
      expect(
        TrendingCatalogService.isGenuineModernAlbum(
          vintageSoundtrack,
          allowArchive: true,
        ),
        isTrue,
      );
    });
  });

  group('Album Subtitle Formatting Tests', () {
    test('Formats primary artist/composer and release year cleanly', () {
      const album1 = JioAlbum(
        id: '201',
        title: 'Jailer',
        artist: 'Anirudh Ravichander, Rajinikanth',
        artwork: '',
        year: '2023',
        songCount: 8,
        language: 'tamil',
      );

      const album2 = JioAlbum(
        id: '202',
        title: 'Guntur Kaaram',
        artist: 'Thaman S; Mahesh Babu',
        artwork: '',
        year: '2024-01-12',
        songCount: 6,
        language: 'telugu',
      );

      const albumWithoutYear = JioAlbum(
        id: '203',
        title: 'Unknown OST',
        artist: 'Pritam',
        artwork: '',
        year: '',
        songCount: 4,
        language: 'hindi',
      );

      expect(
        TrendingCatalogService.formatAlbumSubtitle(album1),
        equals('Anirudh Ravichander • 2023'),
      );
      expect(
        TrendingCatalogService.formatAlbumSubtitle(album2),
        equals('Thaman S • 2024'),
      );
      expect(
        TrendingCatalogService.formatAlbumSubtitle(albumWithoutYear),
        equals('Pritam'),
      );
    });
  });

  group('In-Memory Catalog Caching Tests', () {
    test(
      'Caches and retrieves albums instantaneously without network calls',
      () {
        final service = TrendingCatalogService();
        service.clearCache();

        expect(service.getCachedAlbums('telugu'), isNull);

        const testAlbum = JioAlbum(
          id: '301',
          title: 'Pushpa 2',
          artist: 'Devi Sri Prasad',
          artwork: '',
          year: '2024',
          songCount: 6,
          language: 'telugu',
        );

        service.setCachedAlbums('telugu', [testAlbum]);
        final cached = service.getCachedAlbums('telugu');
        expect(cached, isNotNull);
        expect(cached!.first.title, equals('Pushpa 2'));
        expect(service.getCachedAlbums('unknown_lang_test'), isNull);
      },
    );
  });

  group('YouTube Music Charts InnerTube Integration Tests', () {
    test('fetchCharts runs safely without unhandled exceptions', () async {
      final client = YouTubeMusicClient();
      final tracks = await client.fetchCharts(language: 'hindi', limit: 10);
      expect(tracks, isA<List<Video>>());
    });
  });

  group('Trending Curated Playlist UI Wiring Tests', () {
    testWidgets(
      'Trending CuratedPlaylistScreen renders cleanly without keyword search trap',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CuratedPlaylistScreen(
              title: 'Trending Now',
              subtitle: 'Global Velocity Hits',
              gradientColors: [Color(0xFF38222A), Color(0xFF24141A)],
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Trending Now'), findsAtLeastNWidgets(1));
        expect(find.textContaining('Global Velocity Hits'), findsOneWidget);
      },
    );
  });
}
