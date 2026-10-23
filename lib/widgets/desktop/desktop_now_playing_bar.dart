import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/web_player_bridge.dart';
import '../../screens/player_screen.dart';
import 'desktop_fullscreen_helper.dart';
import '../waveform_scrubber.dart';

/// Spotify-grade 90px Edge-to-Edge Bottom Now Playing Deck (#now-playing-bar).
///
/// Features:
/// 1. Left (Flex 3): Track Artwork squircle, title/artist, interactive Like button, and Jump Back In preview.
/// 2. Center (Flex 5): Shuffle, Prev, Master Play/Pause, Next, Repeat + Isolated Scrubber.
/// 3. Right (Flex 3): Synced Lyrics, Queue, Volume slider with mute toggle, Side panel dock.
///
/// PERFORMANCE GUARANTEE: High-frequency position stream ticks are strictly isolated to
/// the [_DesktopTimelineScrubber] micro-widget to ensure zero full-deck or shell repaints.
class DesktopNowPlayingBar extends StatelessWidget {
  const DesktopNowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E), width: 1.0)),
      ),
      child: const Row(
        children: [
          // Region 1: Left Track Info + Like Button (Flex: 3, Min-width: 180px)
          Expanded(flex: 3, child: _DesktopTrackInfoSection()),

          // Region 2: Center Controls + Scrubber (Flex: 5, Max-width: 722px)
          Expanded(flex: 5, child: _DesktopCenterPlaybackSection()),

          // Region 3: Right System Utilities + Volume (Flex: 3)
          Expanded(flex: 3, child: _DesktopUtilitiesSection()),
        ],
      ),
    );
  }
}

/// Region 1: Left Track Info Section (Listens only to track metadata & like changes).
class _DesktopTrackInfoSection extends StatelessWidget {
  const _DesktopTrackInfoSection();

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();
    final prefs = PreferencesService();

    return AnimatedBuilder(
      animation: Listenable.merge([musicService, prefs]),
      builder: (context, _) {
        final song = musicService.currentSong;
        if (song == null) {
          final history = prefs.listeningHistory;
          final lastPlayed = history.isNotEmpty ? history.first : null;

          if (lastPlayed != null) {
            final title = lastPlayed['title'] ?? 'Unknown Track';
            final author = lastPlayed['author'] ?? 'Unknown Artist';
            final thumbnail = lastPlayed['thumbnail'] ?? '';
            final id = lastPlayed['id'] ?? '';
            final isLiked = id.isNotEmpty && musicService.isLiked(id);

            return Row(
              children: [
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        musicService.playMostPlayedSong(lastPlayed);
                      },
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6.0),
                            child: Container(
                              width: 56.0,
                              height: 56.0,
                              color: const Color(0xFF181818),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: thumbnail.isNotEmpty
                                        ? Image.network(
                                            thumbnail,
                                            fit: BoxFit.cover,
                                            cacheWidth: 120,
                                            cacheHeight: 120,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.music_note_rounded,
                                                  color: Colors.white38,
                                                  size: 24.0,
                                                ),
                                          )
                                        : const Icon(
                                            Icons.music_note_rounded,
                                            color: Colors.white38,
                                            size: 24.0,
                                          ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    height: 3.0,
                                    child: Container(color: prefs.themeColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.history_rounded,
                                        size: 11.0,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        'JUMP BACK IN',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 10.0,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  author,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  tooltip: isLiked ? 'Remove from Liked' : 'Save to Liked',
                  icon: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isLiked
                        ? prefs.themeColor
                        : Colors.white.withValues(alpha: 0.5),
                    size: 19.0,
                  ),
                  onPressed: () => musicService.toggleLikeMap(lastPlayed),
                ),
              ],
            );
          }

          return Row(
            children: [
              Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white24,
                  size: 24.0,
                ),
              ),
              const SizedBox(width: 12.0),
              const Expanded(
                child: Text(
                  'No track playing',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        final artworkUrl = MusicService.resolveArtworkUrl(song);
        final isLiked = musicService.isLiked(song.id.value);

        return Row(
          children: [
            // Clickable 56x56 Squircle Album Artwork & Title
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    );
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6.0),
                        child: Container(
                          width: 56.0,
                          height: 56.0,
                          color: const Color(0xFF181818),
                          child: artworkUrl.isNotEmpty
                              ? Image.network(
                                  artworkUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 120,
                                  cacheHeight: 120,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white38,
                                    size: 24.0,
                                  ),
                                )
                              : const Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white38,
                                  size: 24.0,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3.0),
                            Text(
                              song.author,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12.0,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Interactive Like Button
            IconButton(
              tooltip: isLiked
                  ? 'Remove from Liked Songs'
                  : 'Save to Liked Songs',
              icon: Icon(
                isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isLiked
                    ? prefs.themeColor
                    : Colors.white.withValues(alpha: 0.6),
                size: 20.0,
              ),
              onPressed: () => musicService.toggleLike(song),
            ),
          ],
        );
      },
    );
  }
}

/// Region 2: Center Controls and Timeline Scrubber.
class _DesktopCenterPlaybackSection extends StatelessWidget {
  const _DesktopCenterPlaybackSection();

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();
    final prefs = PreferencesService();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 722.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top Controls Row
            AnimatedBuilder(
              animation: Listenable.merge([musicService, prefs]),
              builder: (context, _) {
                final isShuffle = musicService.isShuffle;
                final isPlaying = musicService.isPlaying;
                final isLoading = musicService.isLoading;
                final accentColor = prefs.themeColor;

                return StreamBuilder<LoopMode>(
                  stream: musicService.audioPlayer.loopModeStream,
                  initialData: musicService.loopMode,
                  builder: (context, loopSnapshot) {
                    final loopMode = musicService.loopMode != LoopMode.off
                        ? musicService.loopMode
                        : (loopSnapshot.data ?? musicService.loopMode);
                    final isRepeat = loopMode != LoopMode.off;
                    final isRepeatOne = loopMode == LoopMode.one;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Shuffle Button
                        IconButton(
                          tooltip: isShuffle
                              ? 'Disable Shuffle'
                              : 'Enable Shuffle',
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: isShuffle
                                ? accentColor
                                : Colors.white.withValues(alpha: 0.6),
                            size: 19.0,
                          ),
                          onPressed: () => musicService.toggleShuffle(),
                        ),

                        // Previous Track Button
                        IconButton(
                          tooltip: 'Previous Track',
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                            size: 24.0,
                          ),
                          onPressed: () => musicService.previousSong(),
                        ),
                        const SizedBox(width: 6.0),

                        // Master Play/Pause Button (36x36 Circular White Pill)
                        GestureDetector(
                          onTap: () {
                            if (musicService.currentSong == null) {
                              final history =
                                  PreferencesService().listeningHistory;
                              if (history.isNotEmpty) {
                                musicService.playMostPlayedSong(history.first);
                                return;
                              }
                            }
                            musicService.togglePlayPause();
                          },
                          child: Container(
                            width: 36.0,
                            height: 36.0,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isLoading
                                  ? const SizedBox(
                                      width: 18.0,
                                      height: 18.0,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 22.0,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6.0),

                        // Next Track Button
                        IconButton(
                          tooltip: 'Next Track',
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 24.0,
                          ),
                          onPressed: () => musicService.nextSong(),
                        ),

                        // Repeat Mode Button
                        IconButton(
                          tooltip: isRepeatOne
                              ? 'Repeat One'
                              : (isRepeat ? 'Repeat All' : 'Enable Repeat'),
                          icon: Icon(
                            isRepeatOne
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: isRepeat
                                ? accentColor
                                : Colors.white.withValues(alpha: 0.6),
                            size: 19.0,
                          ),
                          onPressed: () => musicService.toggleRepeat(),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 2.0),

            // Bottom Timeline Scrubber Row (Isolated Micro-Widget)
            const _DesktopTimelineScrubber(),
          ],
        ),
      ),
    );
  }
}

/// Isolated Micro-Subtree for high-frequency scrubber updates.
/// Rebuilds ONLY this widget when playback position ticks.
class _DesktopTimelineScrubber extends StatefulWidget {
  const _DesktopTimelineScrubber();

  @override
  State<_DesktopTimelineScrubber> createState() =>
      _DesktopTimelineScrubberState();
}

class _DesktopTimelineScrubberState extends State<_DesktopTimelineScrubber> {
  final MusicService _musicService = MusicService();
  double? _dragPositionSeconds;

  String _formatDuration(Duration? d) {
    if (d == null || d.inSeconds <= 0) return '0:00';
    final nonNegative = d.isNegative ? Duration.zero : d;
    final minutes = nonNegative.inMinutes;
    final seconds = nonNegative.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService();
    final accentColor = prefs.themeColor;
    final isWave =
        prefs.progressLineStyle == ProgressLineStyle.wave ||
        prefs.scrubberStyle == ScrubberStyle.waveform;

    return StreamBuilder<Duration?>(
      stream: _musicService.durationStream,
      initialData: _musicService.duration,
      builder: (context, durSnapshot) {
        final totalDuration =
            durSnapshot.data ??
            _musicService.duration ??
            _musicService.currentSong?.duration ??
            Duration.zero;

        return StreamBuilder<Duration>(
          stream: _musicService.positionStream,
          initialData: _musicService.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? _musicService.position;
            final durSec = totalDuration.inMilliseconds / 1000.0;
            final posSec = position.inMilliseconds / 1000.0;

            final isScrubbable = durSec > 0;
            final maxVal = isScrubbable ? durSec : 1.0;
            final currentVal = (_dragPositionSeconds ?? posSec).clamp(
              0.0,
              maxVal,
            );

            return Row(
              children: [
                // Elapsed Timestamp
                SizedBox(
                  width: 42.0,
                  child: Text(
                    _formatDuration(
                      Duration(milliseconds: (currentVal * 1000).toInt()),
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8.0),

                // Interactive Progress Slider / Waveform Scrubber
                Expanded(
                  child: RepaintBoundary(
                    child: (isWave && _musicService.currentSong != null)
                        ? WaveformScrubber(
                            position: position,
                            duration: totalDuration,
                            songId: _musicService.currentSong!.id.value,
                            accentColor: accentColor,
                            showTimestamps: false,
                            height: 24.0,
                            onSeek: (target) => _musicService.seek(target),
                          )
                        : MouseRegion(
                            onExit: (_) {
                              if (_dragPositionSeconds != null) {
                                setState(() => _dragPositionSeconds = null);
                              }
                            },
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: isScrubbable
                                    ? const RoundSliderThumbShape(
                                        enabledThumbRadius: 5.5,
                                      )
                                    : const RoundSliderThumbShape(
                                        enabledThumbRadius: 0.0,
                                      ),
                                overlayShape: isScrubbable
                                    ? const RoundSliderOverlayShape(
                                        overlayRadius: 10.0,
                                      )
                                    : const RoundSliderOverlayShape(
                                        overlayRadius: 0.0,
                                      ),
                                activeTrackColor: accentColor,
                                inactiveTrackColor: Colors.white.withValues(
                                  alpha: 0.15,
                                ),
                                thumbColor: Colors.white,
                                overlayColor: accentColor.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              child: Slider(
                                value: isScrubbable ? currentVal : 0.0,
                                min: 0.0,
                                max: maxVal,
                                onChangeStart: isScrubbable
                                    ? (val) {
                                        setState(
                                          () => _dragPositionSeconds = val,
                                        );
                                      }
                                    : null,
                                onChanged: isScrubbable
                                    ? (val) {
                                        setState(
                                          () => _dragPositionSeconds = val,
                                        );
                                      }
                                    : null,
                                onChangeEnd: isScrubbable
                                    ? (val) {
                                        final target = Duration(
                                          milliseconds: (val * 1000).toInt(),
                                        );
                                        _musicService.seek(target);
                                        setState(
                                          () => _dragPositionSeconds = null,
                                        );
                                      }
                                    : null,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8.0),

                // Total Duration Timestamp
                SizedBox(
                  width: 42.0,
                  child: Text(
                    _formatDuration(totalDuration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Region 3: Right System Utilities and Volume Controls.
class _DesktopUtilitiesSection extends StatefulWidget {
  const _DesktopUtilitiesSection();

  @override
  State<_DesktopUtilitiesSection> createState() =>
      _DesktopUtilitiesSectionState();
}

class _DesktopUtilitiesSectionState extends State<_DesktopUtilitiesSection> {
  final MusicService _musicService = MusicService();
  double _lastVolume = 1.0;
  double _currentVolume = 1.0;
  StreamSubscription<double>? _volumeSubscription;
  bool _isDraggingVolume = false;

  @override
  void initState() {
    super.initState();
    DesktopFullscreenHelper.init();
    _currentVolume = _musicService.audioPlayer.volume;
    if (_currentVolume > 0.001) {
      _lastVolume = _currentVolume;
    }
    _volumeSubscription = _musicService.audioPlayer.volumeStream.listen((vol) {
      if (!_isDraggingVolume &&
          mounted &&
          (vol - _currentVolume).abs() > 0.001) {
        setState(() {
          _currentVolume = vol;
          if (vol > 0.001) {
            _lastVolume = vol;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    super.dispose();
  }

  void _applyVolume(double val) {
    final clamped = val.clamp(0.0, 1.0);
    setState(() {
      _currentVolume = clamped;
    });
    _musicService.audioPlayer.setVolume(clamped);
    if (kIsWeb) {
      WebPlayerBridge.setVolume(clamped);
    }
  }

  void _toggleMute() {
    final current = _currentVolume;
    final isMuted = current <= 0.001;
    if (isMuted) {
      final restoreVol = _lastVolume > 0.05 ? _lastVolume : 1.0;
      _applyVolume(restoreVol);
    } else {
      _lastVolume = current > 0.001 ? current : 1.0;
      _applyVolume(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService();

    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final accentColor = prefs.themeColor;

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Synced Lyrics Toggle
              ValueListenableBuilder<DesktopContextTab>(
                valueListenable: DesktopLayoutState.contextTab,
                builder: (context, tab, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: DesktopLayoutState.isRightPanelVisible,
                    builder: (context, isVisible, _) {
                      final active =
                          isVisible && tab == DesktopContextTab.lyrics;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4.0),
                        constraints: const BoxConstraints(
                          minWidth: 28.0,
                          minHeight: 28.0,
                        ),
                        tooltip: 'Lyrics',
                        icon: Icon(
                          Icons.lyrics_rounded,
                          color: active
                              ? accentColor
                              : Colors.white.withValues(alpha: 0.6),
                          size: 19.0,
                        ),
                        onPressed: () {
                          if (active) {
                            DesktopLayoutState.toggleRightPanel();
                          } else {
                            DesktopLayoutState.setContextTab(
                              DesktopContextTab.lyrics,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),

              // Queue Toggle
              ValueListenableBuilder<DesktopContextTab>(
                valueListenable: DesktopLayoutState.contextTab,
                builder: (context, tab, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: DesktopLayoutState.isRightPanelVisible,
                    builder: (context, isVisible, _) {
                      final active =
                          isVisible && tab == DesktopContextTab.queue;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4.0),
                        constraints: const BoxConstraints(
                          minWidth: 28.0,
                          minHeight: 28.0,
                        ),
                        tooltip: 'Queue',
                        icon: Icon(
                          Icons.queue_music_rounded,
                          color: active
                              ? accentColor
                              : Colors.white.withValues(alpha: 0.6),
                          size: 19.0,
                        ),
                        onPressed: () {
                          if (active) {
                            DesktopLayoutState.toggleRightPanel();
                          } else {
                            DesktopLayoutState.setContextTab(
                              DesktopContextTab.queue,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),

              const SizedBox(width: 2.0),

              // Volume Mute / Unmute Button & Slider
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4.0),
                    constraints: const BoxConstraints(
                      minWidth: 28.0,
                      minHeight: 28.0,
                    ),
                    tooltip: _currentVolume <= 0.001 ? 'Unmute' : 'Mute',
                    icon: Icon(
                      _currentVolume <= 0.001
                          ? Icons.volume_off_rounded
                          : (_currentVolume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded),
                      color: _currentVolume <= 0.001
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.75),
                      size: 19.0,
                    ),
                    onPressed: _toggleMute,
                  ),

                  // Sleek 72px Volume Slider
                  SizedBox(
                    width: 72.0,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 4.5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 8.0,
                        ),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.15,
                        ),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: _currentVolume.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        onChangeStart: (_) {
                          _isDraggingVolume = true;
                        },
                        onChangeEnd: (val) {
                          _isDraggingVolume = false;
                          if (val > 0.001) {
                            _lastVolume = val;
                          }
                          _applyVolume(val);
                        },
                        onChanged: (val) {
                          if (val > 0.001) {
                            _lastVolume = val;
                          }
                          _applyVolume(val);
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 2.0),

              // Right Panel Visibility Toggle
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4.0),
                constraints: const BoxConstraints(
                  minWidth: 28.0,
                  minHeight: 28.0,
                ),
                tooltip: 'Toggle Now Playing Panel',
                icon: Icon(
                  Icons.dock_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 19.0,
                ),
                onPressed: () => DesktopLayoutState.toggleRightPanel(),
              ),

              const SizedBox(width: 2.0),

              // Browser Fullscreen Toggle
              ValueListenableBuilder<bool>(
                valueListenable: DesktopFullscreenHelper.isFullscreenNotifier,
                builder: (context, isFullscreen, _) {
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4.0),
                    constraints: const BoxConstraints(
                      minWidth: 28.0,
                      minHeight: 28.0,
                    ),
                    tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                    icon: Icon(
                      isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: isFullscreen
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.6),
                      size: 20.0,
                    ),
                    onPressed: () => DesktopFullscreenHelper.toggleFullscreen(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
