import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/dynamic_artist_service.dart';
import '../../screens/player_screen.dart';
import '../animated_lyrics.dart';
import '../animated_equalizer.dart';
import 'desktop_context_menu.dart';

/// Spotify-grade 280px Adaptive Desktop Right Context Panel (#Desktop_PanelContainer_Id).
///
/// Supports 3 switchable views controlled by [DesktopLayoutState.contextTab]:
/// 1. Now Playing: 248x248 Hero Art, Like/Share actions, Live Synced Lyrics preview,
///    About the Artist card, and Next in Queue card.
/// 2. Full Synced Lyrics: Auto-scrolling karaoke lyrics stream.
/// 3. Queue: Active and upcoming tracklist with drag-to-reorder support.
class DesktopRightPanel extends StatelessWidget {
  const DesktopRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0.0, 8.0, 8.0, 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Sticky Header Strip
            const _DesktopPanelHeader(),

            // 2. Contextual Content Body
            Expanded(
              child: ValueListenableBuilder<DesktopContextTab>(
                valueListenable: DesktopLayoutState.contextTab,
                builder: (context, activeTab, _) {
                  switch (activeTab) {
                    case DesktopContextTab.lyrics:
                      return const _DesktopLyricsTab();
                    case DesktopContextTab.queue:
                      return const _DesktopQueueTab();
                    case DesktopContextTab.nowPlaying:
                    case DesktopContextTab.chords:
                      return const _DesktopNowPlayingTab();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sticky Header Strip for Desktop Right Panel
class _DesktopPanelHeader extends StatelessWidget {
  const _DesktopPanelHeader();

  String _getTitle(DesktopContextTab tab) {
    switch (tab) {
      case DesktopContextTab.nowPlaying:
        return 'Now Playing';
      case DesktopContextTab.lyrics:
        return 'Lyrics';
      case DesktopContextTab.queue:
        return 'Queue';
      case DesktopContextTab.chords:
        return 'Chords';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DesktopContextTab>(
      valueListenable: DesktopLayoutState.contextTab,
      builder: (context, tab, _) {
        return Container(
          height: 52.0,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF1E1E1E), width: 1.0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _getTitle(tab),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab != DesktopContextTab.nowPlaying)
                    IconButton(
                      tooltip: 'Back to Now Playing',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white70,
                        size: 18.0,
                      ),
                      onPressed: () => DesktopLayoutState.setContextTab(
                        DesktopContextTab.nowPlaying,
                      ),
                    ),
                  const SizedBox(width: 4.0),
                  IconButton(
                    tooltip: 'Open Full Player Screen',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white70,
                      size: 15.0,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PlayerScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 4.0),
                  IconButton(
                    tooltip: 'Close panel',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 18.0,
                    ),
                    onPressed: () =>
                        DesktopLayoutState.isRightPanelVisible.value = false,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// TAB A — NOW PLAYING VIEW
// =============================================================================
class _DesktopNowPlayingTab extends StatelessWidget {
  const _DesktopNowPlayingTab();

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();

    return AnimatedBuilder(
      animation: musicService,
      builder: (context, _) {
        final song = musicService.currentSong;

        if (song == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72.0,
                  height: 72.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white24,
                    size: 36.0,
                  ),
                ),
                const SizedBox(height: 12.0),
                const Text(
                  'No track playing',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Choose a song from your library',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          );
        }

        final artworkUrl = MusicService.resolveArtworkUrl(song);
        final isLiked = musicService.isLiked(song.id.value);

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          children: [
            // 1. 248x248 Hero Cover Art (Clickable to open Full Player Screen)
            Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    );
                  },
                  onSecondaryTapDown: (details) {
                    showUnifiedTrackMenu(
                      context: context,
                      globalPosition: details.globalPosition,
                      song: song,
                      isNowPlaying: true,
                    );
                  },
                  child: Tooltip(
                    message: 'Open Full Player Screen',
                    child: Container(
                      width: 248.0,
                      height: 248.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 18.0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.network(
                          artworkUrl,
                          width: 248.0,
                          height: 248.0,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFF1F1F2B),
                            child: const Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                color: Colors.white38,
                                size: 48.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14.0),

            // 2. Track Title & Artist with Like and Share Actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) {
                      showUnifiedTrackMenu(
                        context: context,
                        globalPosition: details.globalPosition,
                        song: song,
                        isNowPlaying: true,
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        GestureDetector(
                          onTap: () {
                            DesktopLayoutState.openArtist(song.author);
                          },
                          child: Text(
                            song.author,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13.0,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isLiked
                      ? 'Remove from Liked Songs'
                      : 'Save to Liked Songs',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isLiked
                        ? PreferencesService().themeColor
                        : Colors.white70,
                    size: 20.0,
                  ),
                  onPressed: () => musicService.toggleLike(song),
                ),
                IconButton(
                  tooltip: 'Share track',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.share_rounded,
                    color: Colors.white70,
                    size: 19.0,
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: '${song.title} - ${song.author}\n${song.url}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Song link copied to clipboard!',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: const Color(0xFF1E1E28),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16.0),

            // 3. Live Synced Lyrics Preview Box
            _DesktopLyricsPreviewBox(song: song),

            const SizedBox(height: 16.0),

            // 4. About the Artist Card
            _DesktopAboutArtistCard(artistName: song.author),

            const SizedBox(height: 16.0),

            // 5. Next in Queue Card
            const _DesktopNextInQueueCard(),
          ],
        );
      },
    );
  }
}

/// Live Synced Lyrics Preview Box
class _DesktopLyricsPreviewBox extends StatefulWidget {
  final Video song;

  const _DesktopLyricsPreviewBox({required this.song});

  @override
  State<_DesktopLyricsPreviewBox> createState() =>
      _DesktopLyricsPreviewBoxState();
}

class _DesktopLyricsPreviewBoxState extends State<_DesktopLyricsPreviewBox> {
  final MusicService _musicService = MusicService();
  StreamSubscription<Duration>? _sub;
  List<LyricLine> _parsedLines = [];
  int _activeLyricIndex = 0;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _sub = _musicService.positionStream.listen(_onPosition);
  }

  @override
  void didUpdateWidget(covariant _DesktopLyricsPreviewBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id.value != widget.song.id.value) {
      _parseLyrics();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _parseLyrics() {
    final raw = _musicService.cachedLyrics ?? '';
    if (raw.isEmpty) {
      _parsedLines = [];
      return;
    }

    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');

    for (final rawLine in raw.split('\n')) {
      final match = regex.firstMatch(rawLine.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = double.tryParse(match.group(2) ?? '0') ?? 0.0;
        final text = match.group(3)?.trim() ?? '';
        final time = Duration(
          milliseconds: (min * 60 * 1000 + sec * 1000).toInt(),
        );
        if (text.isNotEmpty) {
          lines.add(LyricLine(time, text));
        }
      }
    }
    _parsedLines = lines;
  }

  void _onPosition(Duration pos) {
    if (!mounted || _parsedLines.isEmpty) return;
    int idx = 0;
    for (int i = 0; i < _parsedLines.length; i++) {
      if (_parsedLines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _activeLyricIndex) {
      setState(() => _activeLyricIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10.0),
      onTap: () => DesktopLayoutState.setContextTab(DesktopContextTab.lyrics),
      child: Container(
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lyrics_rounded,
                      color: PreferencesService().themeColor,
                      size: 16.0,
                    ),
                    SizedBox(width: 6.0),
                    Text(
                      'Lyrics preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Show more',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            if (_parsedLines.isEmpty)
              Text(
                _musicService.isFetchingLyrics
                    ? 'Loading synchronized lyrics...'
                    : 'Tap to view full lyrics canvas',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              if (_activeLyricIndex > 0)
                Text(
                  _parsedLines[_activeLyricIndex - 1].text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 12.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4.0),
              Text(
                _parsedLines[_activeLyricIndex].text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4.0,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_activeLyricIndex + 1 < _parsedLines.length) ...[
                const SizedBox(height: 4.0),
                Text(
                  _parsedLines[_activeLyricIndex + 1].text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 12.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// About the Artist Card
class _DesktopAboutArtistCard extends StatelessWidget {
  final String artistName;

  const _DesktopAboutArtistCard({required this.artistName});

  @override
  Widget build(BuildContext context) {
    final artistService = DynamicArtistService();
    final artistItem = artistService.findArtist(artistName);
    final imageUrl = artistItem?.imageUrl ?? '';
    final genre = artistItem?.genre ?? 'Featured Artist';

    return InkWell(
      borderRadius: BorderRadius.circular(10.0),
      onTap: () {
        DesktopLayoutState.openArtist(artistName);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner image
            if (imageUrl.isNotEmpty)
              Stack(
                children: [
                  Image.network(
                    imageUrl,
                    height: 110.0,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  Container(
                    height: 110.0,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF161622).withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                artistName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4.0),
                            const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF3D91F4),
                              size: 16.0,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 4.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Text(
                          'Follow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    genre,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    'Explore popular tracks, verified albums, and latest discography for $artistName.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Next in Queue Card
class _DesktopNextInQueueCard extends StatelessWidget {
  const _DesktopNextInQueueCard();

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();
    final playlist = musicService.playlist;
    final nextIndex = musicService.currentIndex + 1;
    final hasNext = nextIndex < playlist.length;
    final nextTrack = hasNext ? playlist[nextIndex] : null;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: Color(0xFF4A90E2),
                    size: 16.0,
                  ),
                  SizedBox(width: 6.0),
                  Text(
                    'Next in queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () =>
                    DesktopLayoutState.setContextTab(DesktopContextTab.queue),
                child: Text(
                  'Open queue',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10.0),
          if (nextTrack == null)
            Text(
              'No upcoming tracks in queue',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12.0,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                showUnifiedTrackMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  song: nextTrack,
                  queueIndex: nextIndex,
                );
              },
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6.0),
                    child: Builder(
                      builder: (context) {
                        final art = MusicService.resolveArtworkUrl(nextTrack);
                        return art.isNotEmpty
                            ? Image.network(
                                art,
                                width: 44.0,
                                height: 44.0,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 44.0,
                                  height: 44.0,
                                  color: const Color(0xFF282836),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white30,
                                    size: 20,
                                  ),
                                ),
                              )
                            : Container(
                                width: 44.0,
                                height: 44.0,
                                color: const Color(0xFF282836),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white30,
                                  size: 20,
                                ),
                              );
                      },
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nextTrack.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          nextTrack.author,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
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
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// TAB B — FULL SYNCED LYRICS VIEW
// =============================================================================
class _DesktopLyricsTab extends StatelessWidget {
  const _DesktopLyricsTab();

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();

    return AnimatedBuilder(
      animation: musicService,
      builder: (context, _) {
        final song = musicService.currentSong;

        if (song == null) {
          return const Center(
            child: Text(
              'No track playing',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        if (musicService.isFetchingLyrics) {
          return Center(
            child: CircularProgressIndicator(
              color: PreferencesService().themeColor,
              strokeWidth: 2.5,
            ),
          );
        }

        final rawLyrics = musicService.cachedLyrics ?? '';

        if (rawLyrics.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lyrics_outlined,
                  color: Colors.white24,
                  size: 48.0,
                ),
                const SizedBox(height: 12.0),
                const Text(
                  'No lyrics available',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  song.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: AnimatedLyrics(
            key: ValueKey('desktop_lyrics_${song.id.value}'),
            rawLyrics: rawLyrics,
            pronunciationLyrics: musicService.cachedPronunciationLyrics,
            songLanguage: musicService.currentSongLanguage,
            songTitle: song.title,
            songArtist: song.author,
            positionStream: musicService.positionStream,
            onSeek: (target) => musicService.seek(target),
          ),
        );
      },
    );
  }
}

// =============================================================================
// TAB C — ACTIVE QUEUE VIEW
// =============================================================================
class _DesktopQueueTab extends StatefulWidget {
  const _DesktopQueueTab();

  @override
  State<_DesktopQueueTab> createState() => _DesktopQueueTabState();
}

class _DesktopQueueTabState extends State<_DesktopQueueTab> {
  final MusicService _musicService = MusicService();

  void _openTrackContextMenu(
    BuildContext context,
    Offset globalPosition,
    Video song, {
    int? queueIndex,
    bool isNowPlaying = false,
  }) {
    showUnifiedTrackMenu(
      context: context,
      globalPosition: globalPosition,
      song: song,
      queueIndex: queueIndex,
      isNowPlaying: isNowPlaying,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _musicService,
      builder: (context, _) {
        final playlist = _musicService.playlist;
        final currentIndex = _musicService.currentIndex;
        final currentSong = _musicService.currentSong;

        if (playlist.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.queue_music_rounded,
                    color: Colors.white30,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Queue is empty',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Play a song or playlist to start queueing tracks',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        final currentTrack =
            (currentIndex >= 0 && currentIndex < playlist.length)
            ? playlist[currentIndex]
            : (currentSong ?? playlist.first);
        final hdThumb = MusicService.getHdThumbnail(currentTrack.id.value);
        final currentArtwork = hdThumb.isNotEmpty
            ? hdThumb
            : currentTrack.thumbnails.lowResUrl;

        final upcomingOffset = currentIndex >= 0 ? currentIndex + 1 : 0;
        final upcoming = upcomingOffset < playlist.length
            ? playlist.sublist(upcomingOffset)
            : <Video>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Section: "Now Playing" Header & Card
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: PreferencesService().themeColor.withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Live',
                      style: TextStyle(
                        color: PreferencesService().themeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 4.0,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) => _openTrackContextMenu(
                  context,
                  details.globalPosition,
                  currentTrack,
                  isNowPlaying: true,
                ),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF161622),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.network(
                        currentArtwork,
                        width: 48.0,
                        height: 48.0,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 48.0,
                          height: 48.0,
                          color: const Color(0xFF282836),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white24,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentTrack.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3.0),
                          Text(
                            currentTrack.author,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.60),
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    AnimatedEqualizer(
                      isPlaying: _musicService.isPlaying,
                      color: PreferencesService().themeColor,
                      size: 20.0,
                    ),
                  ],
                ),
              ),
            ),
          ),

            const SizedBox(height: 10.0),

            // 2. Bottom Section: "Next In Queue" Header & List
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 4.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'NEXT IN QUEUE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    '${upcoming.length} Tracks',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1.0),

            Expanded(
              child: upcoming.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'No upcoming tracks in queue',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.40),
                            fontSize: 12.0,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      itemCount: upcoming.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.selectionClick();
                        _musicService.reorderQueue(
                          oldIndex + upcomingOffset,
                          newIndex + upcomingOffset,
                        );
                        setState(() {});
                      },
                      itemBuilder: (context, index) {
                        final track = upcoming[index];
                        final absoluteIndex = upcomingOffset + index;
                        final hdThumbnail = MusicService.getHdThumbnail(
                          track.id.value,
                        );
                        final artwork = hdThumbnail.isNotEmpty
                            ? hdThumbnail
                            : track.thumbnails.lowResUrl;

                        return Material(
                          key: ValueKey('queue_next_${track.id.value}_$index'),
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onSecondaryTapDown: (details) =>
                                _openTrackContextMenu(
                                  context,
                                  details.globalPosition,
                                  track,
                                  queueIndex: absoluteIndex,
                                ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _musicService.playPlaylist(
                                  playlist,
                                  absoluteIndex,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 6.0,
                                ),
                                child: Row(
                                  children: [
                                    // Index Badge
                                    Container(
                                      width: 22.0,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.45,
                                          ),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    // Squircle Artwork
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8.0),
                                      child: Image.network(
                                        artwork,
                                        width: 40.0,
                                        height: 40.0,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 40.0,
                                          height: 40.0,
                                          color: const Color(0xFF282836),
                                          child: const Icon(
                                            Icons.music_note_rounded,
                                            color: Colors.white24,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10.0),
                                    // Track Title & Artist
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2.0),
                                          Text(
                                            track.author,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11.0,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Trailing Drag Handle
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 8.0,
                                        ),
                                        child: const Icon(
                                          Icons.drag_handle_rounded,
                                          color: Colors.white38,
                                          size: 20.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
