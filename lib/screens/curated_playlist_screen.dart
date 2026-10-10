import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/jio_album.dart';
import '../services/music_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/dilse_scrollbar.dart';
import 'album_screen.dart';

class CuratedPlaylistScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? query;
  final List<Video>? initialSongs;
  final List<Color>? gradientColors;
  final IconData? icon;
  final String? imageUrl;

  const CuratedPlaylistScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.query,
    this.initialSongs,
    this.gradientColors,
    this.icon,
    this.imageUrl,
  });

  @override
  State<CuratedPlaylistScreen> createState() => _CuratedPlaylistScreenState();
}

class _CuratedPlaylistScreenState extends State<CuratedPlaylistScreen> {
  final MusicService _musicService = MusicService();
  final ScrollController _scrollController = ScrollController();

  List<Video> _tracks = [];
  List<JioAlbum> _relatedAlbums = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _musicService.addListener(_onServiceChanged);
    _loadTracks();
  }

  @override
  void dispose() {
    _musicService.removeListener(_onServiceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTracks() async {
    final query = widget.query ?? widget.title;

    if (widget.initialSongs != null && widget.initialSongs!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = List<Video>.from(widget.initialSongs!);
          _isLoading = false;
        });
      }
      try {
        final albums = await _musicService.searchAlbums(query, limit: 10);
        if (mounted) {
          setState(() {
            _relatedAlbums = albums;
          });
        }
      } catch (_) {}
      return;
    }

    try {
      final resultsFuture = _musicService.searchSongs(query);
      final albumsFuture = _musicService.searchAlbums(query, limit: 10);
      final results = await resultsFuture;
      final albums = await albumsFuture;
      if (mounted) {
        setState(() {
          _tracks = results;
          _relatedAlbums = albums;
          _isLoading = false;
          if (_tracks.isEmpty && _relatedAlbums.isEmpty) {
            _errorMessage = 'No tracks found for this playlist.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load tracks. Please check connection.';
        });
      }
    }
  }

  List<Color> get _effectiveColors {
    if (widget.gradientColors != null && widget.gradientColors!.isNotEmpty) {
      return widget.gradientColors!;
    }
    return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)];
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final topGradientColor = _effectiveColors.first;

    return Scaffold(
      backgroundColor: const Color(0xFF09090C),
      body: Stack(
        children: [
          // Ambient Gradient Glow Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    topGradientColor.withValues(alpha: 0.35),
                    topGradientColor.withValues(alpha: 0.10),
                    const Color(0xFF09090C).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          SafeArea(
            bottom: false,
            child: DilSeScrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App Bar with Elevated Back Button
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 48), // Balance spacing
                        ],
                      ),
                    ),
                  ),

                  // Hero Artwork & Metadata
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          // Hero Album / Vinyl Card
                          Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                colors: _effectiveColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: topGradientColor.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child:
                                  widget.imageUrl != null &&
                                      widget.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      widget.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          _buildFallbackHeroArt(),
                                    )
                                  : _buildFallbackHeroArt(),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Title
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Subtitle & track count
                          Text(
                            _isLoading
                                ? widget.subtitle
                                : '${widget.subtitle} • ${_tracks.length} Tracks',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Action Buttons: Play All & Shuffle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Play All
                              ElevatedButton.icon(
                                onPressed: _tracks.isEmpty
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        _musicService.playPlaylist(_tracks, 0);
                                      },
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 24,
                                ),
                                label: const Text(
                                  'Play',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 4,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Shuffle Button
                              OutlinedButton.icon(
                                onPressed: _tracks.isEmpty
                                    ? null
                                    : () {
                                        HapticFeedback.lightImpact();
                                        final shuffled = List<Video>.from(
                                          _tracks,
                                        )..shuffle();
                                        _musicService.playPlaylist(shuffled, 0);
                                      },
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Shuffle',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.20),
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // Discovery Shelf (Row 1: Soundtracks & Albums)
                  if (_relatedAlbums.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSoundtracksShelf(context)),

                  // Tracklist or Loading state
                  if (_isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF1DB954),
                        ),
                      ),
                    )
                  else if (_errorMessage != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    // Popular Tracks Header (Row 2+)
                    if (_tracks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.music_note_rounded,
                                  size: 15,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Popular Tracks (${_tracks.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        bottom: 120,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final video = _tracks[index];
                          final isCurrent =
                              _musicService.currentSong?.id.value ==
                              video.id.value;
                          final hdThumb = MusicService.getHdThumbnail(
                            video.id.value,
                          );

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: SizedBox(
                              width: 76,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? primaryColor
                                            : Colors.white38,
                                        fontSize: 13,
                                        fontWeight: isCurrent
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 46,
                                      height: 46,
                                      child: Image.network(
                                        hdThumb,
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            Image.network(
                                              video.thumbnails.lowResUrl,
                                              width: 46,
                                              height: 46,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  Container(
                                                    width: 46,
                                                    height: 46,
                                                    color: const Color(
                                                      0xFF161622,
                                                    ),
                                                    child: const Icon(
                                                      Icons.music_note_rounded,
                                                      size: 20,
                                                      color: Colors.white38,
                                                    ),
                                                  ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? primaryColor : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              video.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? primaryColor.withValues(alpha: 0.8)
                                    : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (video.duration != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      _formatDuration(video.duration),
                                      style: TextStyle(
                                        color: isCurrent
                                            ? primaryColor
                                            : Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                if (isCurrent)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: AnimatedEqualizer(
                                      isPlaying: _musicService.isPlaying,
                                      barCount: 3,
                                      color: primaryColor,
                                      size: 15,
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                  onPressed: () => showSongOptionsBottomSheet(
                                    context,
                                    video,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _musicService.playPlaylist(_tracks, index);
                            },
                          );
                        }, childCount: _tracks.length),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Mini Player
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }

  Widget _buildSoundtracksShelf(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.album_rounded,
                  size: 15,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Soundtracks & Albums',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _relatedAlbums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, idx) {
              final album = _relatedAlbums[idx];
              return _buildAlbumShelfCard(context, album);
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAlbumShelfCard(BuildContext context, JioAlbum album) {
    final isSingle = album.songCount <= 1;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumScreen(
              album: album,
              albumId: album.id,
              albumTitle: album.title,
              albumArtwork: album.artwork,
              albumArtist: album.artist,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 125,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 125,
              height: 125,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: album.artwork.isNotEmpty
                          ? Image.network(
                              album.artwork,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _buildAlbumFallbackCover(album),
                            )
                          : _buildAlbumFallbackCover(album),
                    ),
                    if (album.songCount > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSingle
                                  ? Colors.white24
                                  : const Color(
                                      0xFF7C3AED,
                                    ).withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isSingle ? 'Single' : '${album.songCount}',
                            style: TextStyle(
                              color: isSingle
                                  ? Colors.white70
                                  : const Color(0xFFA78BFA),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              album.artist.isNotEmpty
                  ? album.artist
                  : (album.year.isNotEmpty ? album.year : 'Album'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumFallbackCover(JioAlbum album) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.album_rounded, size: 36, color: Colors.white38),
      ),
    );
  }

  Widget _buildFallbackHeroArt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.icon ?? Icons.album_rounded,
            color: Colors.white,
            size: 52,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
