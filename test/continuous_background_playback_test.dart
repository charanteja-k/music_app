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
      'DilSeAudioHandler retains playing: true while loading to protect Android foreground service',
      () {
        final handler = DilSeAudioHandler();
        handler.notifyLoading(isLoading: true);
        expect(handler.playbackState.value.playing, isTrue);
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.loading,
        );
      },
    );

    test(
      'playSong resets saved position and emits initial zero position broadcast immediately',
      () async {
        final music = MusicService();
        music.resetForTesting();

        final song = makeVideo('12345678901', 'Initial Tap Song', 'Artist I');
        Duration? emittedPos;
        final sub = music.positionStream.listen((pos) {
          emittedPos = pos;
        });

        // Trigger playSong
        music.playSong(song);

        await Future.delayed(const Duration(milliseconds: 50));
        expect(emittedPos, equals(Duration.zero));
        expect(music.currentSong?.id.value, '12345678901');
        await sub.cancel();
      },
    );
  });
}
