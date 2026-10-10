import 'dart:async';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'music_service.dart';

DilSeAudioHandler? audioHandler;

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => DilSeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.example.music_app.channel.audio_playback_v3',
      androidNotificationChannelName: 'DilSe Music Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'drawable/ic_stat_music',
      notificationColor: Color(0xFFFA2D48),
    ),
  );
}

class DilSeAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer _player = MusicService().audioPlayer;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<Duration?>? _durationSub;

  DilSeAudioHandler() {
    bindPlayer(_player);
  }

  void changeMediaItem(MediaItem item) {
    mediaItem.add(item);
  }

  /// Proactively keeps Android Foreground Service alive during screen-off song transitions.
  void notifyLoading({bool isLoading = true}) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: isLoading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: true,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
      ),
    );
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    changeMediaItem(mediaItem);
  }

  AudioPlayer get boundPlayer => _player;

  void bindPlayer(AudioPlayer player) {
    _playbackEventSub?.cancel();
    _durationSub?.cancel();
    _player = player;

    _playbackEventSub = _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.stop,
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            androidCompactActionIndices: const [0, 1, 3],
            processingState: const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
            queueIndex: event.currentIndex,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        // Stream errors are centrally managed by MusicService recovery pipeline
      },
    );

    _durationSub = _player.durationStream.listen(
      (Duration? duration) {
        if (mediaItem.value != null && duration != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: duration));
        }
      },
      onError: (Object error) {
        // Guard against duration stream error disruptions
      },
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    final dur = _player.duration ?? mediaItem.value?.duration;
    Duration target = position;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (dur != null && dur > Duration.zero) {
      final maxSeek = dur - const Duration(milliseconds: 500);
      if (target > maxSeek) {
        target = maxSeek > Duration.zero ? maxSeek : Duration.zero;
      }
    }
    await _player.seek(target);
  }

  @override
  Future<void> stop() async {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // When app is swiped away from Android recent tasks, dismiss ghost notification if paused
    if (!_player.playing) {
      await stop();
    }
    await super.onTaskRemoved();
  }

  @override
  Future<void> skipToNext() async {
    await MusicService().nextSong();
  }

  @override
  Future<void> skipToPrevious() async {
    await MusicService().previousSong();
  }

  @override
  Future<void> fastForward() async {
    final pos = _player.position;
    final dur = _player.duration ?? mediaItem.value?.duration;
    if (dur != null && dur > Duration.zero) {
      final maxSeek = dur - const Duration(milliseconds: 500);
      final target = pos + const Duration(seconds: 10);
      await seek(target > maxSeek ? maxSeek : target);
    } else {
      await seek(pos + const Duration(seconds: 10));
    }
  }

  @override
  Future<void> rewind() async {
    final target = _player.position - const Duration(seconds: 10);
    await seek(target < Duration.zero ? Duration.zero : target);
  }
}
