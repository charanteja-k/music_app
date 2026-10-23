import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'crossfade': false,
      'audioQuality': 'studioMaster',
      'audioFormat': 'aac',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
          (call) async => {},
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.music_app/widget'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    final prefs = PreferencesService();
    prefs.resetForTesting();
    await prefs.init();

    final musicService = MusicService();
    musicService.resetForTesting();
  });

  Video makeVideo(String id, String title, String author) {
    return Video(
      VideoId(id),
      title,
      author,
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      null,
      ThumbnailSet(id),
      null,
      Engagement(0, null, null),
      false,
    );
  }

  group('Spotify Shuffle & Dynamic Queue Synchronization Tests', () {
    test('3-Tier Queue initialization and getters', () {
      final service = MusicService();
      final songs = List.generate(
        10,
        (i) => makeVideo(
          'vid_${i.toString().padLeft(7, '0')}',
          'Title $i',
          'Artist $i',
        ),
      );

      service.setPlaylistForTesting(songs, initialIndex: 2);

      expect(service.isShuffle, isFalse);
      expect(service.currentIndex, 2);
      expect(service.currentSong?.id.value, 'vid_0000002');
      expect(service.playbackQueue.length, 10);
      expect(service.upcomingQueue.length, 7);
      expect(service.upcomingQueue.first.id.value, 'vid_0000003');
      expect(service.playedHistory.isEmpty, isTrue);
    });

    test(
      'toggleShuffle ON randomizes upcoming tracks while retaining current song',
      () {
        final service = MusicService();
        final songs = List.generate(
          20,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        service.setPlaylistForTesting(songs, initialIndex: 3);
        final currentBefore = service.currentSong;
        expect(currentBefore?.id.value, 'vid_0000003');

        service.toggleShuffle();

        expect(service.isShuffle, isTrue);
        expect(service.currentSong?.id.value, 'vid_0000003');
        expect(service.currentIndex, 3);
        expect(service.playbackQueue.length, 20);
        expect(service.upcomingQueue.length, 16);

        // Verify that all 20 songs are still present (zero data loss)
        final allIds = service.playbackQueue.map((s) => s.id.value).toSet();
        expect(allIds.length, 20);
        for (int i = 0; i < 20; i++) {
          expect(
            allIds.contains('vid_${i.toString().padLeft(7, '0')}'),
            isTrue,
          );
        }
      },
    );

    test('toggleShuffle OFF restores exact original playlist sequence', () {
      final service = MusicService();
      final songs = List.generate(
        20,
        (i) => makeVideo(
          'vid_${i.toString().padLeft(7, '0')}',
          'Title $i',
          'Artist $i',
        ),
      );

      service.setPlaylistForTesting(songs, initialIndex: 5);
      service.toggleShuffle();
      expect(service.isShuffle, isTrue);

      service.toggleShuffle();
      expect(service.isShuffle, isFalse);
      expect(service.currentIndex, 5);
      expect(service.currentSong?.id.value, 'vid_0000005');

      // Verify exact original sequence is restored
      for (int i = 0; i < 20; i++) {
        expect(
          service.playbackQueue[i].id.value,
          'vid_${i.toString().padLeft(7, '0')}',
        );
      }
      expect(service.upcomingQueue.first.id.value, 'vid_0000006');
    });

    test('reorderQueue modifies active queue and updates upcoming tracks', () {
      final service = MusicService();
      final songs = List.generate(
        10,
        (i) => makeVideo(
          'vid_${i.toString().padLeft(7, '0')}',
          'Title $i',
          'Artist $i',
        ),
      );

      service.setPlaylistForTesting(songs, initialIndex: 0);
      expect(service.upcomingQueue.first.id.value, 'vid_0000001');

      // Move track at index 3 to index 1 (next position)
      service.reorderQueue(3, 1);
      expect(service.upcomingQueue.first.id.value, 'vid_0000003');
      expect(service.playbackQueue[1].id.value, 'vid_0000003');
    });

    test('toggleShuffle on empty queue is safe and does not throw', () {
      final service = MusicService();
      service.resetForTesting();
      expect(service.playbackQueue.isEmpty, isTrue);

      expect(() => service.toggleShuffle(), returnsNormally);
      expect(service.isShuffle, isTrue);

      expect(() => service.toggleShuffle(), returnsNormally);
      expect(service.isShuffle, isFalse);
    });

    test('playedHistory stack tracks played songs', () {
      final service = MusicService();
      final song1 = makeVideo('vid_0000001', 'Track 1', 'Artist 1');
      final song2 = makeVideo('vid_0000002', 'Track 2', 'Artist 2');

      service.setPlayedHistoryForTesting([song1, song2]);
      expect(service.playedHistory.length, 2);
      expect(service.playedHistory.first.id.value, 'vid_0000001');
      expect(service.playedHistory.last.id.value, 'vid_0000002');
    });
  });
}
