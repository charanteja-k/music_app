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
          (call) async {
            if (call.method == 'init') {
              final id = (call.arguments as Map?)?['id'] as String?;
              if (id != null) {
                TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger
                    .setMockMethodCallHandler(
                      MethodChannel('com.ryanheise.just_audio.methods.$id'),
                      (subCall) async => {},
                    );
              }
            }
            return {};
          },
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
    await prefs.init();
  });

  Video makeVideo(String id, String title, String author) {
    MusicService.cacheWebStreamUrl(id, 'https://example.com/$id.mp3');
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
    test('3-Tier Queue initialization and getters', () async {
      final service = MusicService();
      final songs = List.generate(
        10,
        (i) => makeVideo(
          'vid_${i.toString().padLeft(7, '0')}',
          'Title $i',
          'Artist $i',
        ),
      );

      await service.playPlaylist(songs, 2);

      expect(service.isShuffle, isFalse);
      expect(service.currentIndex, 2);
      expect(service.currentSong?.id.value, 'vid_0000002');
      expect(service.playbackQueue.length, 10);
      expect(service.upcomingQueue.length, 7);
      expect(service.upcomingQueue.first.id.value, 'vid_0000003');
    });

    test(
      'toggleShuffle ON randomizes upcoming tracks while retaining current song',
      () async {
        final service = MusicService();
        final songs = List.generate(
          20,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        await service.playPlaylist(songs, 3);
        final currentBefore = service.currentSong;
        expect(currentBefore?.id.value, 'vid_0000003');

        service.toggleShuffle();

        expect(service.isShuffle, isTrue);
        expect(service.currentSong?.id.value, 'vid_0000003');
        expect(service.currentIndex, 3);
        expect(service.playbackQueue.length, 20);
        expect(service.upcomingQueue.length, 16);

        // Verify that all 20 songs are still present (no data loss)
        final allIds = service.playbackQueue.map((s) => s.id.value).toSet();
        expect(allIds.length, 20);
        for (int i = 0; i < 20; i++) {
          expect(allIds.contains('vid_${i.toString().padLeft(7, '0')}'), isTrue);
        }
      },
    );

    test(
      'toggleShuffle OFF restores exact original playlist sequence',
      () async {
        final service = MusicService();
        final songs = List.generate(
          20,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        await service.playPlaylist(songs, 5);
        service.toggleShuffle();
        expect(service.isShuffle, isTrue);

        service.toggleShuffle();
        expect(service.isShuffle, isFalse);
        expect(service.currentIndex, 5);
        expect(service.currentSong?.id.value, 'vid_0000005');

        // Verify exact original order is restored
        for (int i = 0; i < 20; i++) {
          expect(
            service.playbackQueue[i].id.value,
            'vid_${i.toString().padLeft(7, '0')}',
          );
        }
        expect(service.upcomingQueue.first.id.value, 'vid_0000006');
      },
    );

    test(
      'playShuffledPlaylist sets shuffle mode and places chosen track at index 0',
      () async {
        final service = MusicService();
        final songs = List.generate(
          15,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        await service.playShuffledPlaylist(songs, initialIndex: 4);

        expect(service.isShuffle, isTrue);
        expect(service.currentIndex, 0);
        expect(service.currentSong?.id.value, 'vid_0000004');
        expect(service.playbackQueue.length, 15);
        expect(service.playbackQueue.first.id.value, 'vid_0000004');
        expect(service.upcomingQueue.length, 14);
      },
    );

    test(
      'nextSong advances linearly through upcomingQueue and updates playedHistory',
      () async {
        final service = MusicService();
        final songs = List.generate(
          10,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        await service.playPlaylist(songs, 0);
        final expectedNextTrack = service.upcomingQueue.first;

        await service.nextSong();

        expect(service.currentSong?.id.value, expectedNextTrack.id.value);
        expect(service.currentIndex, 1);
        expect(service.playedHistory.isNotEmpty, isTrue);
        expect(service.playedHistory.last.id.value, 'vid_0000000');
      },
    );

    test(
      'previousSong returns to previously played song from playedHistory',
      () async {
        final service = MusicService();
        final songs = List.generate(
          10,
          (i) => makeVideo(
            'vid_${i.toString().padLeft(7, '0')}',
            'Title $i',
            'Artist $i',
          ),
        );

        await service.playPlaylist(songs, 0);
        await service.nextSong(); // Moves to vid_0000001, pushes vid_0000000 to playedHistory
        expect(service.currentSong?.id.value, 'vid_0000001');

        await service.previousSong(); // Pops vid_0000000 from playedHistory
        expect(service.currentSong?.id.value, 'vid_0000000');
        expect(service.currentIndex, 0);
      },
    );
  });
}
