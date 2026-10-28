import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../screens/artist_profile_screen.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/web_player_bridge.dart';
import '../../layouts/desktop_layout_state.dart';
import '../animated_lyrics.dart';
import '../vinyl_record_player.dart';
import '../../utils/artist_utils.dart';

enum DesktopPlayerTab { nowPlaying, lyrics, queue }

/// Spotify & Apple Music-grade Desktop Full-Screen Cinema Music Player.
///
/// Designed specifically for PC, Mac, Laptop, and Desktop Web screens (width >= 800px).
/// Features:
/// 1. GPU-accelerated 3-stop adaptive ambient background with zero expensive blur passes.
/// 2. Top bar with Exit Full-Screen, HQ Audio badge, Like button, and tab switcher.
/// 3. Hero stage with dynamic 360px-440px album artwork, multi-layer glow, and vinyl support.
/// 4. Integrated desktop volume slider, precision scrubber, and full command deck.
/// 5. Edge-to-edge Cinema Lyrics split view and interactive Up Next Queue manager.
/// 6. Ergonomic desktop keyboard shortcuts (Space, Arrow keys, Esc).
class DesktopFullScreenPlayer extends StatefulWidget {
  final Video song;
  final bool isPlaying;
  final bool isLoading;
  final bool isLiked;
  final Color dominantColor;
  final Color vibrantColor;
  final Color darkVibrantColor;
  final ArtworkStyle artworkStyle;
  final VoidCallback onClose;

  const DesktopFullScreenPlayer({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.isLoading,
    required this.isLiked,
    required this.dominantColor,
    required this.vibrantColor,
    required this.darkVibrantColor,
    required this.artworkStyle,
    required this.onClose,
  });

  @override
  State<DesktopFullScreenPlayer> createState() =>
      _DesktopFullScreenPlayerState();
}

class _DesktopFullScreenPlayerState extends State<DesktopFullScreenPlayer> {
  final MusicService _musicService = MusicService();
  final FocusNode _focusNode = FocusNode();
  DesktopPlayerTab _activeTab = DesktopPlayerTab.nowPlaying;
  double _lastVolume = 1.0;
  double _currentVolume = 1.0;
  bool _isDraggingVolume = false;
  StreamSubscription<double>? _volumeSubscription;

  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    _focusNode.dispose();
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

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      _musicService.togglePlayPause();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _musicService.seekRelative(const Duration(seconds: 5));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _musicService.seekRelative(const Duration(seconds: -5));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _applyVolume(_currentVolume + 0.05);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _applyVolume(_currentVolume - 0.05);
    } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
      setState(() {
        _activeTab = _activeTab == DesktopPlayerTab.lyrics
            ? DesktopPlayerTab.nowPlaying
            : DesktopPlayerTab.lyrics;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF09090D),
        body: Stack(
          children: [
            // 1. Dynamic Ambient Background Gradient
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        widget.vibrantColor.withValues(alpha: 0.28),
                        const Color(0xFF0C0C14),
                      ),
                      Color.alphaBlend(
                        widget.dominantColor.withValues(alpha: 0.16),
                        const Color(0xFF08080E),
                      ),
                      Color.alphaBlend(
                        widget.darkVibrantColor.withValues(alpha: 0.18),
                        const Color(0xFF06060A),
                      ),
                    ],
                    stops: const [0.0, 0.48, 1.0],
                  ),
                ),
              ),
            ),

            // 2. Main Content Canvas
            SafeArea(
              child: Column(
                children: [
                  // Top Navigation Header
                  _buildTopBar(context),

                  // Center Stage (Switches by Tab)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36.0,
                        vertical: 12.0,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildStageContent(context),
                      ),
                    ),
                  ),

                  // Bottom Tab Switcher Dock
                  _buildBottomDock(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Exit Full Screen Button with tooltip
          Tooltip(
            message: 'Exit Full Screen (Esc)',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onClose,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Minimize',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Center: Context title
          Text(
            'NOW PLAYING',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),

          // Right: Audio Quality Badge + Like Button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: widget.vibrantColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.vibrantColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 13,
                      color: widget.vibrantColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '320 KBPS • HQ',
                      style: TextStyle(
                        color: widget.vibrantColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: widget.isLiked
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                icon: Icon(
                  widget.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: widget.isLiked
                      ? const Color(0xFFFA2D48)
                      : Colors.white70,
                  size: 24,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _musicService.toggleLike(widget.song);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageContent(BuildContext context) {
    switch (_activeTab) {
      case DesktopPlayerTab.nowPlaying:
        return _buildHeroNowPlayingStage(context);
      case DesktopPlayerTab.lyrics:
        return _buildCinemaLyricsStage(context);
      case DesktopPlayerTab.queue:
        return _buildSplitQueueStage(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Stage 1: Hero Now Playing View (Balanced 2-Column Cinema Mode)
  // ---------------------------------------------------------------------------
  Widget _buildHeroNowPlayingStage(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('stage_now_playing'),
      builder: (context, constraints) {
        final double maxCoverSize = (constraints.maxHeight * 0.68).clamp(
          300.0,
          440.0,
        );
        final hdThumbnail = MusicService.getHdThumbnail(widget.song.id.value);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Hero Artwork with multi-layer ambient glow
                Hero(
                  tag: 'artwork_${widget.song.id.value}',
                  child: widget.artworkStyle == ArtworkStyle.vinyl
                      ? SizedBox(
                          width: maxCoverSize + 48,
                          height: maxCoverSize,
                          child: VinylRecordPlayer(
                            isPlaying: widget.isPlaying,
                            imageUrl: hdThumbnail,
                            dominantColor: widget.dominantColor,
                            vibrantColor: widget.vibrantColor,
                            size: maxCoverSize,
                          ),
                        )
                      : Container(
                          width: maxCoverSize,
                          height: maxCoverSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.dominantColor.withValues(
                                  alpha: 0.50,
                                ),
                                blurRadius: 40,
                                spreadRadius: 4,
                                offset: const Offset(0, 14),
                              ),
                              BoxShadow(
                                color: widget.vibrantColor.withValues(
                                  alpha: 0.32,
                                ),
                                blurRadius: 54,
                                spreadRadius: 6,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: Image.network(
                              hdThumbnail,
                              fit: BoxFit.cover,
                              cacheWidth: 800,
                              cacheHeight: 800,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFF1E1E2A),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.white54,
                                  size: 72,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),

                const SizedBox(width: 56),

                // Right: Metadata, Controls, Scrubber, Volume & Actions
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Song Title
                      SelectableText(
                        widget.song.title,
                        maxLines: 2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Artist Name (Clickable with hover underline)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtistProfileScreen(
                                  artistName: widget.song.author,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            ArtistUtils.formatArtistName(widget.song.author),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Live Synced Lyrics Preview Banner (Tap to expand full lyrics)
                      _buildLiveLyricsSnippet(widget.vibrantColor),

                      const SizedBox(height: 24),

                      // Desktop High-Precision Scrubber
                      _buildDesktopScrubber(widget.vibrantColor),

                      const SizedBox(height: 16),

                      // Desktop Command Deck: Shuffle, Prev10, Prev, Play/Pause, Next, Next10, Repeat
                      _buildDesktopControlsRow(widget.vibrantColor),

                      const SizedBox(height: 20),

                      // Bottom Utilities: Desktop Volume Deck & Quick Navigation Actions
                      _buildDesktopBottomUtilities(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Stage 2: Cinema Lyrics Mode (Apple Music Large Karaoke Split)
  // ---------------------------------------------------------------------------
  Widget _buildCinemaLyricsStage(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('stage_lyrics'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Column (Compact Artwork + Playback Deck)
          SizedBox(
            width: 320,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    MusicService.getHdThumbnail(widget.song.id.value),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 200,
                      height: 200,
                      color: const Color(0xFF1E1E2A),
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                        size: 54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ArtistUtils.formatArtistName(widget.song.author),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                _buildDesktopScrubber(widget.vibrantColor),
                const SizedBox(height: 10),
                _buildDesktopControlsRow(widget.vibrantColor, compact: true),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // Right Column (Expanded Synchronized Karaoke Lyrics Stream)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111119).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: AnimatedLyrics(
                    key: ValueKey('lyrics_${widget.song.id.value}'),
                    rawLyrics: _musicService.cachedLyrics ?? '',
                    pronunciationLyrics:
                        _musicService.cachedPronunciationLyrics,
                    songLanguage: _musicService.currentSongLanguage,
                    songTitle: widget.song.title,
                    songArtist: widget.song.author,
                    positionStream: _musicService.positionStream,
                    onSeek: (pos) => _musicService.seek(pos),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Stage 3: Split Queue Mode (Full Playlist & Reorder Manager)
  // ---------------------------------------------------------------------------
  Widget _buildSplitQueueStage(BuildContext context) {
    final playlist = _musicService.playlist;
    final currentIndex = _musicService.currentIndex;

    return KeyedSubtree(
      key: const ValueKey('stage_queue'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Column (Now Playing Card)
          SizedBox(
            width: 320,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    MusicService.getHdThumbnail(widget.song.id.value),
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 220,
                      height: 220,
                      color: const Color(0xFF1E1E2A),
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                        size: 54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ArtistUtils.formatArtistName(widget.song.author),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                _buildDesktopScrubber(widget.vibrantColor),
                const SizedBox(height: 10),
                _buildDesktopControlsRow(widget.vibrantColor, compact: true),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // Right Column (Tracklist Queue Drawer)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111119).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Up Next in Queue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${playlist.length} Tracks',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: playlist.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final track = playlist[index];
                        final isCurrent = index == currentIndex;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              MusicService.getHdThumbnail(track.id.value),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 44,
                                height: 44,
                                color: const Color(0xFF1E1E2A),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? widget.vibrantColor
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            track.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                          trailing: isCurrent
                              ? Icon(
                                  Icons.graphic_eq_rounded,
                                  color: widget.vibrantColor,
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            _musicService.playPlaylist(playlist, index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Component: Live Lyrics Preview Snippet
  // ---------------------------------------------------------------------------
  Widget _buildLiveLyricsSnippet(Color accentColor) {
    final cached = _musicService.cachedLyrics;
    if (cached == null || cached.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Duration>(
      stream: _musicService.positionStream,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final previewLine = _extractActiveLine(cached, pos);
        if (previewLine.isEmpty) return const SizedBox.shrink();

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _activeTab = DesktopPlayerTab.lyrics;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Icon(Icons.lyrics_rounded, color: accentColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    previewLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withValues(alpha: 0.40),
                  size: 13,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _extractActiveLine(String lrc, Duration pos) {
    final lines = lrc.split('\n');
    final tagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    String lastMatch = '';

    for (final raw in lines) {
      final line = raw.trim();
      final m = tagRegex.firstMatch(line);
      if (m != null) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final lineDuration = Duration(minutes: min, seconds: sec);
        if (lineDuration <= pos) {
          final text = line.replaceAll(tagRegex, '').trim();
          if (text.isNotEmpty) lastMatch = text;
        } else {
          break;
        }
      }
    }
    return lastMatch;
  }

  // ---------------------------------------------------------------------------
  // Component: Desktop High-Precision Scrubber
  // ---------------------------------------------------------------------------
  Widget _buildDesktopScrubber(Color accentColor) {
    return StreamBuilder<Duration>(
      stream: _musicService.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: _musicService.durationStream,
          builder: (context, durSnap) {
            final duration =
                durSnap.data ??
                widget.song.duration ??
                const Duration(seconds: 1);
            final double progress = duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  )
                : 0.0;

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6.5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14.0,
                    ),
                    activeTrackColor: accentColor,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                    thumbColor: Colors.white,
                    overlayColor: accentColor.withValues(alpha: 0.25),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (val) {
                      final target = Duration(
                        milliseconds: (val * duration.inMilliseconds).toInt(),
                      );
                      _musicService.seek(target);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Component: Playback Command Deck
  // ---------------------------------------------------------------------------
  Widget _buildDesktopControlsRow(Color accentColor, {bool compact = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        IconButton(
          tooltip: 'Shuffle',
          icon: Icon(
            Icons.shuffle_rounded,
            color: _musicService.isShuffle
                ? const Color(0xFF1DB954)
                : Colors.white54,
            size: compact ? 20 : 24,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            _musicService.toggleShuffle();
            setState(() {});
          },
        ),
        const SizedBox(width: 8),

        // 10s Rewind
        if (!compact) ...[
          IconButton(
            tooltip: 'Replay 10 seconds',
            icon: const Icon(
              Icons.replay_10_rounded,
              color: Colors.white70,
              size: 24,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              _musicService.seekRelative(const Duration(seconds: -10));
            },
          ),
          const SizedBox(width: 8),
        ],

        // Previous
        IconButton(
          tooltip: 'Previous track',
          icon: Icon(
            Icons.skip_previous_rounded,
            color: Colors.white,
            size: compact ? 30 : 36,
          ),
          onPressed: () {
            HapticFeedback.mediumImpact();
            _musicService.previousSong();
          },
        ),
        const SizedBox(width: 14),

        // Master Play/Pause with vibrant glow
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            _musicService.togglePlayPause();
          },
          child: Container(
            width: compact ? 52 : 66,
            height: compact ? 52 : 66,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.isLoading
                ? Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF0C0C14),
                      ),
                    ),
                  )
                : Icon(
                    widget.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: const Color(0xFF0C0C14),
                    size: compact ? 30 : 40,
                  ),
          ),
        ),
        const SizedBox(width: 14),

        // Next
        IconButton(
          tooltip: 'Next track',
          icon: Icon(
            Icons.skip_next_rounded,
            color: Colors.white,
            size: compact ? 30 : 36,
          ),
          onPressed: () {
            HapticFeedback.mediumImpact();
            _musicService.nextSong();
          },
        ),
        const SizedBox(width: 8),

        // 10s Forward
        if (!compact) ...[
          IconButton(
            tooltip: 'Forward 10 seconds',
            icon: const Icon(
              Icons.forward_10_rounded,
              color: Colors.white70,
              size: 24,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              _musicService.seekRelative(const Duration(seconds: 10));
            },
          ),
          const SizedBox(width: 8),
        ],

        // Repeat
        IconButton(
          tooltip: 'Repeat Mode',
          icon: Icon(
            _musicService.loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: _musicService.loopMode != LoopMode.off
                ? const Color(0xFF1DB954)
                : Colors.white54,
            size: compact ? 20 : 24,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            _musicService.toggleRepeat();
            setState(() {});
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Component: Desktop Volume Slider & Contextual Actions
  // ---------------------------------------------------------------------------
  Widget _buildDesktopBottomUtilities(BuildContext context) {
    final volume = _currentVolume;
    final isMuted = volume <= 0.001;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Volume Controller Deck
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isMuted ? 'Unmute' : 'Mute',
              icon: Icon(
                isMuted
                    ? Icons.volume_off_rounded
                    : (volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded),
                color: isMuted
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white70,
                size: 20,
              ),
              onPressed: _toggleMute,
            ),
            SizedBox(
              width: 120,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5.5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12.0,
                  ),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  key: const Key('desktop_fullscreen_volume_slider'),
                  value: volume.clamp(0.0, 1.0),
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
            const SizedBox(width: 4),
            SizedBox(
              width: 38,
              child: Text(
                '${(volume * 100).toInt()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        // Quick Navigation Pills: "View Artist" & "Go to Album"
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.person_rounded, size: 15),
              label: const Text(
                'View Artist',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                widget.onClose();
                DesktopLayoutState.openArtist(widget.song.author);
              },
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.album_rounded, size: 15),
              label: const Text(
                'Go to Album',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                final cachedId = MusicService.getCachedAlbumId(
                  widget.song.id.value,
                );
                final cachedTitle =
                    MusicService.getCachedAlbumTitle(widget.song.id.value) ??
                    MusicService.extractMovieOrAlbumTitle(widget.song.title);
                widget.onClose();
                DesktopLayoutState.openAlbum(
                  albumId: cachedId ?? '',
                  albumTitle: cachedTitle ?? widget.song.title,
                  albumArtwork: MusicService.getHdThumbnail(
                    widget.song.id.value,
                  ),
                  albumArtist: widget.song.author,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Component: Bottom Dock View Switcher
  // ---------------------------------------------------------------------------
  Widget _buildBottomDock() {
    final playlist = _musicService.playlist;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDockTabButton(
                tab: DesktopPlayerTab.nowPlaying,
                icon: Icons.music_note_rounded,
                label: 'Now Playing',
              ),
              const SizedBox(width: 4),
              _buildDockTabButton(
                tab: DesktopPlayerTab.lyrics,
                icon: Icons.lyrics_rounded,
                label: 'Lyrics',
              ),
              const SizedBox(width: 4),
              _buildDockTabButton(
                tab: DesktopPlayerTab.queue,
                icon: Icons.queue_music_rounded,
                label: 'Queue (${playlist.length})',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockTabButton({
    required DesktopPlayerTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _activeTab == tab;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _activeTab = tab;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? widget.vibrantColor : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: widget.vibrantColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
