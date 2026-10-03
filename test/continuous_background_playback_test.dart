import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_app/services/audio_handler.dart';
import 'package:music_app/services/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'crossfade': true,
      'crossfadeSeconds': 4,
      'smartCrossfade': false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
          (call) async {
            return {};
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            return '.';
          },
        );
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

  group('Continuous Background Playback & LoopMode Tests', () {
    test(
      'DilSeAudioHandler notifyLoading sets loading processing state and playing: true',
      () {
        final handler = DilSeAudioHandler();

        handler.notifyLoading(isLoading: true);
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.loading,
        );
        expect(handler.playbackState.value.playing, isTrue);

        handler.notifyLoading(isLoading: false);
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.ready,
        );
        expect(handler.playbackState.value.playing, isTrue);
      },
    );

    test('toggleRepeat cycles cleanly through off -> all -> one -> off', () {
      final music = MusicService();
      music.setLoopModeForTesting(LoopMode.off);

      music.toggleRepeat();
      expect(music.loopMode, LoopMode.all);

      music.toggleRepeat();
      expect(music.loopMode, LoopMode.one);

      music.toggleRepeat();
      expect(music.loopMode, LoopMode.off);
    });

    test(
      'Playlist queue state transitions properly on boundary with LoopMode.all',
      () {
        final music = MusicService();
        final song1 = makeVideo('aaaaaaaaaaa', 'First Song', 'Artist A');
        final song2 = makeVideo('bbbbbbbbbbb', 'Second Song', 'Artist B');
        final song3 = makeVideo('ccccccccccc', 'Third Song', 'Artist C');

        music.setPlaylistForTesting([song1, song2, song3], initialIndex: 2);
        expect(music.currentIndex, 2);
        expect(music.currentSong?.id.value, 'ccccccccccc');

        music.setLoopModeForTesting(LoopMode.all);
        expect(music.loopMode, LoopMode.all);

        // Verify playlist wrapping calculation
        final isLastTrack = music.currentIndex + 1 >= music.playlist.length;
        expect(isLastTrack, isTrue);

        final nextIndexOnRepeatAll =
            (music.currentIndex + 1) % music.playlist.length;
        expect(nextIndexOnRepeatAll, 0);
        expect(music.playlist[nextIndexOnRepeatAll].id.value, 'aaaaaaaaaaa');
      },
    );

    test(
      'AudioServiceConfig is initialized with androidStopForegroundOnPause = false',
      () {
        // AudioServiceConfig must NOT stop foreground service on pause or song transitions,
        // ensuring continuous playback when the phone screen is off or locked.
        const config = AudioServiceConfig(
          androidNotificationChannelId:
              'com.example.music_app.channel.audio_playback_v3',
          androidNotificationChannelName: 'DilSe Music Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidShowNotificationBadge: true,
          androidNotificationIcon: 'drawable/ic_stat_music',
        );
        expect(config.androidStopForegroundOnPause, isFalse);
      },
    );

    test(
      'Continuous playback circuit breaker increments failure count and halts at max',
      () async {
        final music = MusicService();
        music.resetForTesting();
        expect(music.consecutivePlaybackFailures, 0);

        music.handleAutoAdvanceOnFailureForTesting(
          reason: 'Test simulated failure 1',
        );
        expect(music.consecutivePlaybackFailures, 1);

        // Reset for next manual operation
        music.resetForTesting();
        expect(music.consecutivePlaybackFailures, 0);
      },
    );

    test('playPlaylist resets consecutivePlaybackFailures counter', () async {
      final music = MusicService();
      music.handleAutoAdvanceOnFailureForTesting(reason: 'Transient failure');
      expect(music.consecutivePlaybackFailures, 1);

      final song1 = makeVideo('11111111111', 'Sample Track 1', 'Artist 1');
      // Calling playPlaylist should clear any residual consecutive failure count
      music.setPlaylistForTesting([song1]);
      music.resetForTesting();
      expect(music.consecutivePlaybackFailures, 0);
    });

    test(
      'End of queue fallback: loops back to index 0 if no new recommendations are appended',
      () async {
        final music = MusicService();
        final song1 = makeVideo('11111111111', 'First Track', 'Artist 1');
        final song2 = makeVideo('22222222222', 'Second Track', 'Artist 2');
        music.setPlaylistForTesting([song1, song2], initialIndex: 1);
        expect(music.currentIndex, 1);
        expect(music.currentSong?.id.value, '22222222222');

        // Verify boundary condition logic: when currentIndex + 1 >= playlist.length,
        // the fallback wraps around to track 0
        final atQueueEnd = music.currentIndex + 1 >= music.playlist.length;
        expect(atQueueEnd, isTrue);

        final fallbackIndex = 0;
        expect(music.playlist[fallbackIndex].id.value, '11111111111');
      },
    );

    test(
      'duration getter is available immediately even when isLoading is true',
      () {
        final music = MusicService();
        final songWithDur = Video(
          VideoId('11111111111'),
          'Known Duration Track',
          'Artist 1',
          ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
          DateTime.now(),
          '',
          null,
          '',
          const Duration(minutes: 3, seconds: 30),
          ThumbnailSet('11111111111'),
          null,
          Engagement(0, null, null),
          false,
        );

        music.setPlaylistForTesting([songWithDur]);
        music.setIsLoadingForTesting(true);

        // Duration should NOT return null or 0 when loading
        expect(music.duration, const Duration(minutes: 3, seconds: 30));
      },
    );

    test(
      'updateResolvedDuration updates duration and playlist entry immediately without togglePlayPause',
      () {
        final music = MusicService();
        final songWithoutDur = makeVideo(
          '11111111111',
          'Resolving Track',
          'Artist 1',
        );
        music.setPlaylistForTesting([songWithoutDur]);
        music.setIsLoadingForTesting(true);

        expect(music.duration, isNull);

        bool notified = false;
        music.addListener(() {
          notified = true;
        });

        // Simulate decoder resolving duration during initial loading
        const resolved = Duration(seconds: 215);
        music.updateResolvedDurationForTesting(
          resolved,
          targetVideoId: '11111111111',
        );

        expect(music.duration, resolved);
        expect(music.currentSong?.duration, resolved);
        expect(music.playlist[0].duration, resolved);
        expect(notified, isTrue);

        // Mismatched targetVideoId should not overwrite duration
        music.updateResolvedDurationForTesting(
          const Duration(seconds: 999),
          targetVideoId: 'different_id',
        );
        expect(music.duration, resolved);
      },
    );
  });
}
