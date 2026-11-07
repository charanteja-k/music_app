import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/jio_album.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/taste_recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
    TasteRecommendationService().clearMemoryCache();
  });

  group('TasteRecommendationService Tests', () {
    test(
      'Calculates top listened artists accurately from listening signals',
      () async {
        final prefs = PreferencesService();
        final service = TasteRecommendationService();

        // Simulate listening history with Swedish House Mafia and Sid Sriram
        await prefs.addToListeningHistory({
          'id': 'v_shm_1',
          'title': 'Moth To A Flame',
          'author': 'Swedish House Mafia, The Weeknd',
        });
        await prefs.addToListeningHistory({
          'id': 'v_shm_2',
          'title': 'Don\'t You Worry Child',
          'author': 'Swedish House Mafia',
        });
        await prefs.addToListeningHistory({
          'id': 'v_sid_1',
          'title': 'Samajavaragamana',
          'author': 'Sid Sriram',
        });

        final topArtists = service.getMostListenedArtists(limit: 3);
        expect(topArtists, isNotEmpty);
        expect(topArtists.contains('Swedish House Mafia'), isTrue);
        expect(topArtists.contains('Sid Sriram'), isTrue);
      },
    );

    test('Filters studio/label channels from artist recommendations', () async {
      final prefs = PreferencesService();
      final service = TasteRecommendationService();

      await prefs.addToListeningHistory({
        'id': 'v_noise_1',
        'title': 'Random Track',
        'author': 'T-Series Regional',
      });
      await prefs.addToListeningHistory({
        'id': 'v_noise_2',
        'title': 'Movie Promo',
        'author': 'Aditya Music',
      });
      await prefs.addToListeningHistory({
        'id': 'v_artist_1',
        'title': 'Starboy',
        'author': 'The Weeknd',
      });

      final topArtists = service.getMostListenedArtists(limit: 5);
      expect(topArtists.contains('The Weeknd'), isTrue);
      expect(
        topArtists.any((a) => a.toLowerCase().contains('t-series')),
        isFalse,
      );
      expect(
        topArtists.any((a) => a.toLowerCase().contains('aditya music')),
        isFalse,
      );
    });

    test('Generates user-friendly, dynamic subtitles', () {
      final service = TasteRecommendationService();

      expect(
        service.getRecommendedSongsSubtitle([]),
        equals('Popular hits and trending tracks curated for your taste'),
      );
      expect(
        service.getRecommendedSongsSubtitle(['Swedish House Mafia']),
        equals('Popular hits from Swedish House Mafia and similar artists'),
      );
      expect(
        service.getRecommendedSongsSubtitle([
          'Swedish House Mafia',
          'The Weeknd',
        ]),
        equals('Popular tracks from Swedish House Mafia & The Weeknd'),
      );

      expect(
        service.getRecommendedAlbumsSubtitle([]),
        equals('Soundtracks and studio albums curated for your taste'),
      );
      expect(
        service.getRecommendedAlbumsSubtitle(['Swedish House Mafia']),
        equals('Popular albums and soundtracks from Swedish House Mafia'),
      );
    });

    test('Detects shifts in user top artists dynamically', () {
      final service = TasteRecommendationService();

      final current = ['Swedish House Mafia', 'The Weeknd'];
      expect(
        service.hasTopArtistsChanged(current),
        isTrue,
      ); // Empty history != current
    });

    test('Serializes and deserializes videos and albums flawlessly', () {
      final video = Video(
        VideoId('d_dummy_123'),
        'Test Song',
        'Test Artist',
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        const Duration(minutes: 3),
        ThumbnailSet('d_dummy_123'),
        null,
        Engagement(0, null, null),
        false,
      );

      final serializedVideos = TasteRecommendationService.serializeVideos([
        video,
      ]);
      final deserializedVideos = TasteRecommendationService.deserializeVideos(
        serializedVideos,
      );
      expect(deserializedVideos.length, equals(1));
      expect(deserializedVideos.first.title, equals('Test Song'));
      expect(deserializedVideos.first.author, equals('Test Artist'));

      final album = JioAlbum(
        id: 'alb_1',
        title: 'Paradise Again',
        artist: 'Swedish House Mafia',
        artwork: 'https://example.com/art.jpg',
        year: '2022',
        language: 'English',
        songCount: 17,
      );

      final serializedAlbums = TasteRecommendationService.serializeAlbums([
        album,
      ]);
      final deserializedAlbums = TasteRecommendationService.deserializeAlbums(
        serializedAlbums,
      );
      expect(deserializedAlbums.length, equals(1));
      expect(deserializedAlbums.first.id, equals('alb_1'));
      expect(deserializedAlbums.first.title, equals('Paradise Again'));
      expect(deserializedAlbums.first.artist, equals('Swedish House Mafia'));
    });
  });
}
