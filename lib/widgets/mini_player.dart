import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../screens/player_screen.dart';
import '../constants/app_theme_tokens.dart';
import 'dilse_image.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  /// Screen-level visibility policy. When false, the mini-player hides itself.
  static final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);

  /// Temporarily hides the mini-player while a specific screen is active.
  static void hide() {
    isVisible.value = false;
  }

  /// Restores mini-player visibility when leaving a screen.
  static void show() {
    isVisible.value = true;
  }

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final MusicService _musicService = MusicService();
  String? _lastEnrichedSongId;

  @override
  void initState() {
    super.initState();
    _musicService.addListener(_onMusicStateChanged);
    MiniPlayer.isVisible.addListener(_onVisibilityChanged);
    PreferencesService().addListener(_onPreferencesChanged);
    _maybeEnrichArtwork();
  }

  void _onPreferencesChanged() {
    if (mounted) setState(() {});
  }

  void _maybeEnrichArtwork() {
    final isTesting = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (isTesting) return;

    final song = _musicService.currentSong;
    if (song != null && song.id.value != _lastEnrichedSongId) {
      _lastEnrichedSongId = song.id.value;
      final hdThumbnail = MusicService.getHdThumbnail(song.id.value);
      if (hdThumbnail.isEmpty ||
          hdThumbnail.startsWith('https://i.ytimg.com/')) {
        _musicService.enrichArtworkForSongs([song]);
      }
    }
  }

  @override
  void dispose() {
    _musicService.removeListener(_onMusicStateChanged);
    MiniPlayer.isVisible.removeListener(_onVisibilityChanged);
    PreferencesService().removeListener(_onPreferencesChanged);
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      setState(() {});
    }
  }

  void _onMusicStateChanged() {
    _maybeEnrichArtwork();
    if (mounted) setState(() {});
  }

  void _openPlayerScreen() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 440),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );

          final scale = Tween<double>(begin: 0.88, end: 1.0).animate(curve);
          final slide = Tween<Offset>(
            begin: const Offset(0.0, 0.88),
            end: Offset.zero,
          ).animate(curve);
          final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curve);

          return SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: FadeTransition(opacity: fade, child: child),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!MiniPlayer.isVisible.value) {
      return const SizedBox.shrink();
    }

    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      return const SizedBox.shrink();
    }

    final song = _musicService.currentSong;
    final isPlaying = _musicService.isPlaying;
    final processingState = _musicService.audioPlayer.processingState;
    final isBuffering =
        !kIsWeb &&
        (processingState == ProcessingState.buffering ||
            processingState == ProcessingState.loading);
    final isLoading = !isPlaying && (_musicService.isLoading || isBuffering);
    final hdThumbnail = song != null
        ? MusicService.getHdThumbnail(song.id.value)
        : '';
    final thumbUrl = hdThumbnail.isNotEmpty
        ? hdThumbnail
        : (song?.thumbnails.highResUrl ?? '');

    final accentColor = PreferencesService().legibleThemeColor;

    if (song == null && !isLoading) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _openPlayerScreen,
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -120) {
          _openPlayerScreen();
        }
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -200) {
            HapticFeedback.mediumImpact();
            _musicService.nextSong();
          } else if (details.primaryVelocity! > 200) {
            HapticFeedback.mediumImpact();
            _musicService.previousSong();
          }
        }
      },
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
          height: 60,
          decoration: BoxDecoration(
            color: AppThemeTokens.floatingDockSurface,
            borderRadius: BorderRadius.circular(
              AppThemeTokens.radiusFloatingDock,
            ),
            border: Border.all(
              color: isPlaying
                  ? accentColor.withValues(alpha: 0.28)
                  : AppThemeTokens.floatingDockBorder,
              width: 1,
            ),
            boxShadow: AppThemeTokens.dockShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              AppThemeTokens.radiusFloatingDock,
            ),
            child: Stack(
              children: [
                // Main Player Content Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      // Album Thumbnail (44x44dp)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppThemeTokens.radiusSmall,
                        ),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: thumbUrl.isNotEmpty
                              ? Transform.scale(
                                  // YouTube audio uploads often have letterbox/pillarbox margins; crop flush to fill the 44x44 square
                                  scale:
                                      thumbUrl.startsWith(
                                        'https://i.ytimg.com/',
                                      )
                                      ? 1.35
                                      : 1.0,
                                  child: DilSeImage(
                                    key: ValueKey(thumbUrl),
                                    imageUrl: thumbUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorWidget: Container(
                                      color: const Color(0xFF1E1E28),
                                      child: const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white38,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: const Color(0xFF1E1E28),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Song Title and Artist
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              song?.title ?? 'Loading...',
                              style: const TextStyle(
                                color: AppThemeTokens.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song?.author ?? '',
                              style: const TextStyle(
                                color: AppThemeTokens.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Control Buttons: Like, Play/Pause, Next
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (song != null)
                            IconButton(
                              icon: Icon(
                                _musicService.isLiked(song.id.value)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: _musicService.isLiked(song.id.value)
                                    ? accentColor
                                    : Colors.white60,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _musicService.toggleLike(song);
                                setState(() {});
                              },
                            ),
                          const SizedBox(width: 2),
                          isLoading
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6.0,
                                  ),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentColor,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    _musicService.togglePlayPause();
                                  },
                                ),
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _musicService.nextSong();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Razor-Thin Progress Bar along bottom edge
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: StreamBuilder<Duration?>(
                    stream: _musicService.durationStream,
                    initialData: _musicService.duration,
                    builder: (context, durSnapshot) {
                      return StreamBuilder<Duration>(
                        stream: _musicService.positionStream,
                        initialData: _musicService.position,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration =
                              durSnapshot.data ??
                              _musicService.duration ??
                              Duration.zero;
                          double progress = 0.0;
                          if (duration.inMilliseconds > 0) {
                            progress =
                                (position.inMilliseconds /
                                        duration.inMilliseconds)
                                    .clamp(0.0, 1.0);
                          }

                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: Container(
                              height: 2.0,
                              decoration: BoxDecoration(color: accentColor),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
