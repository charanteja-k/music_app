import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../widgets/vinyl_record_player.dart';
import '../widgets/waveform_scrubber.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();

  late AnimationController _ambientController;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    _musicService.addListener(_onStateChanged);
    _prefs.addListener(_onStateChanged);

    // Continuous slow rotation for living ambient aura
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _musicService.removeListener(_onStateChanged);
    _prefs.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _cleanLyrics(String? raw) {
    if (raw == null) return 'No lyrics available.';
    final cleaned = raw.replaceAll(RegExp(r'\[\d+:\d+(\.\d+)?\]'), '').trim();
    return cleaned.isEmpty ? 'No lyrics available.' : cleaned;
  }

  void _toggleLyrics(Video song) {
    HapticFeedback.lightImpact();
    setState(() {
      _showLyrics = !_showLyrics;
    });
    if (_showLyrics) {
      _musicService.fetchLyrics(song);
    }
  }

  void _showQueueSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final playlist = _musicService.playlist;
        final currentIndex = _musicService.currentIndex;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: const Color(0xFF16161E).withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Up Next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${playlist.length} Tracks',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: playlist.isEmpty
                      ? const Center(
                          child: Text('Queue is empty', style: TextStyle(color: Colors.white54)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: playlist.length,
                          itemBuilder: (context, index) {
                            final song = playlist[index];
                            final isCurrent = index == currentIndex;
                            final hdThumbnail = MusicService.getHdThumbnail(song.id.value);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  hdThumbnail,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Image.network(
                                    song.thumbnails.lowResUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent ? Theme.of(context).primaryColor : Colors.white,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                song.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? Theme.of(context).primaryColor.withValues(alpha: 0.8)
                                      : Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: isCurrent
                                  ? Icon(Icons.equalizer, color: Theme.of(context).primaryColor, size: 24)
                                  : Text(
                                      _formatDuration(song.duration),
                                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                                    ),
                              onTap: () {
                                Navigator.pop(context);
                                _musicService.playPlaylist(playlist, index);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSleepTimerSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161E).withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sleep Timer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_musicService.isSleepTimerActive)
                      TextButton(
                        onPressed: () {
                          _musicService.cancelSleepTimer();
                          Navigator.pop(context);
                        },
                        child: const Text('Turn Off', style: TextStyle(color: Colors.redAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSleepOption(context, '15 minutes', const Duration(minutes: 15)),
                _buildSleepOption(context, '30 minutes', const Duration(minutes: 30)),
                _buildSleepOption(context, '45 minutes', const Duration(minutes: 45)),
                _buildSleepOption(context, '1 hour', const Duration(hours: 1)),
                ListTile(
                  leading: const Icon(Icons.music_off_outlined, color: Colors.white70),
                  title: const Text('End of current track', style: TextStyle(color: Colors.white)),
                  trailing: _musicService.stopAtEndOfTrack
                      ? const Icon(Icons.check, color: Color(0xFF1DB954))
                      : null,
                  onTap: () {
                    _musicService.setStopAtEndOfTrack(true);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSleepOption(BuildContext context, String label, Duration duration) {
    final isSelected = _musicService.sleepRemaining != null &&
        (_musicService.sleepRemaining!.inMinutes - duration.inMinutes).abs() < 1;

    return ListTile(
      leading: const Icon(Icons.timer_outlined, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF1DB954)) : null,
      onTap: () {
        _musicService.startSleepTimer(duration);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _musicService.currentSong;
    final isPlaying = _musicService.isPlaying;
    final processingState = _musicService.audioPlayer.processingState;
    final isBuffering = !kIsWeb && (processingState == ProcessingState.buffering || processingState == ProcessingState.loading);
    final isLoading = !isPlaying && (_musicService.isLoading || isBuffering);
    final isLiked = song != null && _musicService.likedSongs.any((s) => s['id'] == song.id.value);
    final hdThumbnail = song != null ? MusicService.getHdThumbnail(song.id.value) : '';
    final artworkStyle = _prefs.artworkStyle;

    if (song == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B0F),
        body: Center(child: Text('No song active', style: TextStyle(color: Colors.white))),
      );
    }

    final dominantColor = _musicService.dominantColor;
    final vibrantColor = _musicService.vibrantColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta != null && details.primaryDelta! > 18) {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }
        },
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -300) {
              HapticFeedback.mediumImpact();
              _musicService.nextSong();
            } else if (details.primaryVelocity! > 300) {
              HapticFeedback.mediumImpact();
              _musicService.previousSong();
            }
          }
        },
        child: Stack(
          children: [
            // 1. Dynamic Living Ambient Gradient Mesh Aura
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ambientController,
                builder: (context, child) {
                  final progress = _ambientController.value;
                  final angle = progress * 2 * math.pi;

                  return Stack(
                    children: [
                      // Deep base color
                      Container(color: const Color(0xFF09090D)),

                      // Blob 1 (Top Left, rotating)
                      Positioned(
                        top: -100 + (math.sin(angle) * 40),
                        left: -100 + (math.cos(angle) * 40),
                        width: 420,
                        height: 420,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dominantColor.withValues(alpha: 0.70),
                          ),
                        ),
                      ),

                      // Blob 2 (Mid Right, reverse rotating)
                      Positioned(
                        top: 180 + (math.cos(angle) * 50),
                        right: -120 + (math.sin(angle) * 50),
                        width: 380,
                        height: 380,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: vibrantColor.withValues(alpha: 0.55),
                          ),
                        ),
                      ),

                      // Blob 3 (Bottom Center, breathing)
                      Positioned(
                        bottom: -80 + (math.sin(angle * 1.5) * 30),
                        left: 40 + (math.cos(angle * 1.5) * 30),
                        width: 340,
                        height: 340,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dominantColor.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Frost blur overlay
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.42),
                ),
              ),
            ),

            // 2. Main Player Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Column(
                  children: [
                    // Top Grabber & Header Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 34),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                          },
                        ),
                        Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Row(
                          children: [
                            // Lyrics Toggle
                            IconButton(
                              icon: Icon(
                                _showLyrics ? Icons.music_note_rounded : Icons.lyrics_outlined,
                                color: _showLyrics ? Theme.of(context).primaryColor : Colors.white70,
                                size: 24,
                              ),
                            onPressed: () => _toggleLyrics(song),
                          ),
                          // Sleep Timer
                          IconButton(
                            icon: Icon(
                              Icons.bedtime_outlined,
                              color: _musicService.isSleepTimerActive
                                  ? Theme.of(context).primaryColor
                                  : Colors.white70,
                              size: 24,
                            ),
                            onPressed: () => _showSleepTimerSheet(context),
                          ),
                          // Queue Sheet
                          IconButton(
                            icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24),
                            onPressed: () => _showQueueSheet(context),
                          ),
                          // Offline Download
                          IconButton(
                            icon: _musicService.isDownloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(
                                    _musicService.downloadedSongs.any((s) => s['id'] == song.id.value)
                                        ? Icons.download_done_rounded
                                        : Icons.arrow_circle_down_outlined,
                                    color: _musicService.downloadedSongs.any((s) => s['id'] == song.id.value)
                                        ? const Color(0xFF1DB954)
                                        : Colors.white70,
                                    size: 26,
                                  ),
                            onPressed: _musicService.isDownloading
                                ? null
                                : () async {
                                    final success = await _musicService.downloadSong(song);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success ? 'Saved to Offline Library!' : 'Download failed.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Center Content: Artwork Switcher OR Synced Lyrics
                  if (!_showLyrics)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: artworkStyle == ArtworkStyle.vinyl
                          ? VinylRecordPlayer(
                              key: const ValueKey('vinyl_style'),
                              imageUrl: hdThumbnail,
                              isPlaying: isPlaying,
                              dominantColor: dominantColor,
                              vibrantColor: vibrantColor,
                              size: MediaQuery.of(context).size.width * 0.78,
                            )
                          : Center(
                              key: const ValueKey('card_style'),
                              child: Hero(
                                tag: 'player_artwork_${song.id.value}',
                                child: Container(
                                  width: MediaQuery.of(context).size.width * 0.82,
                                  height: MediaQuery.of(context).size.width * 0.82,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: dominantColor.withValues(alpha: 0.60),
                                        blurRadius: 36,
                                        spreadRadius: 6,
                                        offset: const Offset(0, 16),
                                      ),
                                      BoxShadow(
                                        color: vibrantColor.withValues(alpha: 0.40),
                                        blurRadius: 50,
                                        spreadRadius: 10,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Image.network(
                                      hdThumbnail,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Image.network(
                                        song.thumbnails.highResUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    )
                  else
                    Expanded(
                      flex: 8,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: _musicService.isFetchingLyrics
                            ? Center(
                                child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
                              )
                            : SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Text(
                                  _cleanLyrics(_musicService.cachedLyrics),
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    height: 1.8,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                      ),
                    ),

                  const Spacer(),

                  // Track Info & Like Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.author,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isLiked ? const Color(0xFFFA2D48) : Colors.white70,
                          size: 30,
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _musicService.toggleLike(song);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Tactile Waveform Scrubber or Classic Progress Bar
                  StreamBuilder<Duration>(
                    stream: _musicService.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = _musicService.duration ??
                          (song.duration ?? Duration.zero);

                      if (_prefs.scrubberStyle == ScrubberStyle.classic) {
                        return _buildClassicScrubber(context, position, duration, vibrantColor);
                      }

                      return WaveformScrubber(
                        position: position,
                        duration: duration,
                        songId: song.id.value,
                        accentColor: vibrantColor,
                        onSeek: (newPos) {
                          _musicService.seek(newPos);
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Secondary Controls (Shuffle, -10s, +10s, Repeat)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: _musicService.isShuffle ? const Color(0xFF1DB954) : Colors.white54,
                          size: 24,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _musicService.toggleShuffle();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 28),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _musicService.seekRelative(const Duration(seconds: -10));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 28),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _musicService.seekRelative(const Duration(seconds: 10));
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _musicService.loopMode == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: _musicService.loopMode != LoopMode.off
                              ? const Color(0xFF1DB954)
                              : Colors.white54,
                          size: 24,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _musicService.toggleRepeat();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Main Playback Controls (Prev, Play/Pause, Next)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 46),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _musicService.previousSong();
                        },
                      ),
                      // Elevated Play/Pause Button with Ambient Glow
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: vibrantColor.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(22.0),
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                              )
                            : IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 46,
                                ),
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  _musicService.togglePlayPause();
                                },
                              ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 46),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _musicService.nextSong();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildClassicScrubber(
    BuildContext context,
    Duration position,
    Duration duration,
    Color accentColor,
  ) {
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final curMs = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final remaining = duration > position ? duration - position : Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: accentColor,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: accentColor.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 3),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: curMs,
              min: 0,
              max: maxMs,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                _musicService.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '-${_formatDuration(remaining)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
