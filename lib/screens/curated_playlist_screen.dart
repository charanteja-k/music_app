import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/jio_album.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/music_service.dart';
import '../services/canonical_song_dedup.dart';
import '../services/studio_search_service.dart';
import '../services/youtube_library_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/shimmer_loading.dart';
import '../layouts/desktop_layout_state.dart';
import '../widgets/desktop/desktop_context_menu.dart';
import '../widgets/desktop/desktop_playlist_enrichment.dart';
import 'album_screen.dart';

class CuratedPlaylistScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? query;
  final List<Video>? initialSongs;
  final Future<List<Video>> Function()? fetchSongs;
  final List<Color>? gradientColors;
  final IconData? icon;
  final String? imageUrl;

  const CuratedPlaylistScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.query,
    this.initialSongs,
    this.fetchSongs,
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

  bool get _isSavedToLibrary => _musicService.customPlaylists.any(
    (p) =>
        (p['name']?.toString().toLowerCase().trim() ?? '') ==
        widget.title.toLowerCase().trim(),
  );

  void _toggleSavePlaylistToLibrary() {
    HapticFeedback.mediumImpact();
    final existing = _musicService.customPlaylists.firstWhere(
      (p) =>
          (p['name']?.toString().toLowerCase().trim() ?? '') ==
          widget.title.toLowerCase().trim(),
      orElse: () => <String, dynamic>{},
    );

    if (existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.title}" is already in your library.'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF222230),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final newId = _musicService.createPlaylist(widget.title);
    _musicService.setPlaylistSongs(newId, _tracks, commit: true);
    if (AuthService().isAuthenticated) {
      unawaited(CloudSyncService().sync());
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "${widget.title}" to your library!'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1DB954),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    setState(() {});
  }

  Future<void> _loadTracks() async {
    final query = widget.query ?? widget.title;
    DesktopLayoutState.prioritizeDoor(query);

    if (widget.fetchSongs != null) {
      try {
        final songs = await widget.fetchSongs!().timeout(
          const Duration(seconds: 12),
          onTimeout: () => <Video>[],
        );
        if (mounted) {
          setState(() {
            _tracks = CanonicalSongDedup.deduplicateList(songs);
            _isLoading = false;
            if (_tracks.isEmpty) {
              _errorMessage = 'No tracks found in this playlist.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load tracks: $e';
          });
        }
      }
      return;
    }

    if (widget.initialSongs != null && widget.initialSongs!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = CanonicalSongDedup.deduplicateList(
            List<Video>.from(widget.initialSongs!),
          );
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

    final qLower = query.toLowerCase().trim();
    if (qLower == 'supermix' || qLower == 'my supermix') {
      try {
        final songs = await YouTubeLibraryService().fetchSupermix().timeout(
          const Duration(seconds: 10),
          onTimeout: () => <Video>[],
        );
        if (mounted) {
          setState(() {
            _tracks = CanonicalSongDedup.deduplicateList(songs);
            _isLoading = false;
            if (_tracks.isEmpty) {
              _errorMessage = 'No tracks found for this playlist.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load tracks: $e';
          });
        }
      }
      return;
    } else if (qLower == 'discover mix' || qLower == 'discover') {
      try {
        final songs = await YouTubeLibraryService().fetchDiscoverMix().timeout(
          const Duration(seconds: 10),
          onTimeout: () => <Video>[],
        );
        if (mounted) {
          setState(() {
            _tracks = CanonicalSongDedup.deduplicateList(songs);
            _isLoading = false;
            if (_tracks.isEmpty) {
              _errorMessage = 'No tracks found for this playlist.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load tracks: $e';
          });
        }
      }
      return;
    } else if (qLower == 'new release mix') {
      try {
        final songs = await YouTubeLibraryService()
            .fetchNewReleaseMix()
            .timeout(const Duration(seconds: 10), onTimeout: () => <Video>[]);
        if (mounted) {
          setState(() {
            _tracks = CanonicalSongDedup.deduplicateList(songs);
            _isLoading = false;
            if (_tracks.isEmpty) {
              _errorMessage = 'No tracks found for this playlist.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load tracks: $e';
          });
        }
      }
      return;
    } else if (qLower == 'forgotten tracks' ||
        qLower == 'forgotten favorites') {
      try {
        final songs = await YouTubeLibraryService()
            .fetchForgottenTracks()
            .timeout(const Duration(seconds: 10), onTimeout: () => <Video>[]);
        if (mounted) {
          setState(() {
            _tracks = CanonicalSongDedup.deduplicateList(songs);
            _isLoading = false;
            if (_tracks.isEmpty) {
              _errorMessage = 'No tracks found for this playlist.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Failed to load tracks: $e';
          });
        }
      }
      return;
    }

    try {
      final resultsFuture = StudioSearchService()
          .searchSongs(query)
          .timeout(const Duration(seconds: 10), onTimeout: () => <Video>[]);
      final albumsFuture = _musicService
          .searchAlbums(query, limit: 10)
          .timeout(const Duration(seconds: 8), onTimeout: () => <JioAlbum>[]);
      List<Video> results = await resultsFuture;
      if (results.isEmpty) {
        results = await _musicService
            .searchSongs(query)
            .timeout(const Duration(seconds: 8), onTimeout: () => <Video>[]);
      }
      if (results.isEmpty) {
        final fallbackQuery = query.toLowerCase().contains('late night')
            ? 'Slow Melodies'
            : (query.toLowerCase().contains('morning')
                  ? 'Morning Melodies'
                  : '$query Songs');
        results = await _musicService
            .searchSongs(fallbackQuery)
            .timeout(const Duration(seconds: 8), onTimeout: () => <Video>[]);
      }
      final albums = await albumsFuture;
      if (mounted) {
        setState(() {
          _tracks = CanonicalSongDedup.deduplicateList(results);
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
      if (widget.gradientColors!.length == 1) {
        final c = widget.gradientColors!.first;
        return [c, const Color(0xFF121217)];
      }
      return widget.gradientColors!;
    }
    return [const Color(0xFF4D727A), const Color(0xFF121217)];
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
                              onPressed: () {
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                } else {
                                  DesktopLayoutState.closeDetailView();
                                }
                              },
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
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onSecondaryTapDown: (details) {
                              showUnifiedPlaylistMenu(
                                context: context,
                                globalPosition: details.globalPosition,
                                playlist: {
                                  'id':
                                      'curated_${widget.title.toLowerCase().replaceAll(' ', '_')}',
                                  'title': widget.title,
                                  'isCurated': true,
                                  'songs': _tracks,
                                },
                              );
                            },
                            child: Container(
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
                                child: _buildHeroImage(),
                              ),
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
                              const SizedBox(width: 14),

                              // Save to Library Button
                              OutlinedButton.icon(
                                onPressed: _tracks.isEmpty
                                    ? null
                                    : _toggleSavePlaylistToLibrary,
                                icon: Icon(
                                  _isSavedToLibrary
                                      ? Icons.bookmark_added_rounded
                                      : Icons.bookmark_add_outlined,
                                  color: _isSavedToLibrary
                                      ? primaryColor
                                      : Colors.white,
                                  size: 20,
                                ),
                                label: Text(
                                  _isSavedToLibrary ? 'Saved' : 'Save',
                                  style: TextStyle(
                                    color: _isSavedToLibrary
                                        ? primaryColor
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: _isSavedToLibrary
                                        ? primaryColor.withValues(alpha: 0.6)
                                        : Colors.white.withValues(alpha: 0.20),
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Header 3-Dot More Options Menu (DEFECT 2)
                              Builder(
                                builder: (btnCtx) => IconButton(
                                  tooltip: 'Playlist options',
                                  icon: Container(
                                    width: 42,
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.more_vert_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                  onPressed: () {
                                    final renderBox =
                                        btnCtx.findRenderObject() as RenderBox?;
                                    final offset =
                                        renderBox?.localToGlobal(Offset.zero) ??
                                        Offset.zero;
                                    final buttonSize =
                                        renderBox?.size ?? Size.zero;
                                    final menuPosition = Offset(
                                      offset.dx,
                                      offset.dy + buttonSize.height,
                                    );
                                    showUnifiedPlaylistMenu(
                                      context: context,
                                      globalPosition: menuPosition,
                                      playlist: {
                                        'id':
                                            'curated_${widget.title.toLowerCase().replaceAll(' ', '_')}',
                                        'title': widget.title,
                                        'isCurated': true,
                                        'songs': _tracks,
                                      },
                                    );
                                  },
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
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: ShimmerSongRow(),
                      ),
                    )
                  else if (_errorMessage != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _errorMessage!.contains('No tracks')
                                  ? Icons.music_off_rounded
                                  : Icons.wifi_off_rounded,
                              size: 48,
                              color: Colors.white38,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _isLoading = true;
                                  _errorMessage = null;
                                });
                                _loadTracks();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
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

                          return GestureDetector(
                            onSecondaryTapDown: (details) {
                              DesktopContextMenu.showSongMenu(
                                context: context,
                                globalPosition: details.globalPosition,
                                song: video,
                              );
                            },
                            child: ListTile(
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
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
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
                                              CanonicalSongDedup.isLikelyYouTubeId(
                                                video.id.value,
                                              )
                                              ? Image.network(
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
                                                          Icons
                                                              .music_note_rounded,
                                                          size: 20,
                                                          color: Colors.white38,
                                                        ),
                                                      ),
                                                )
                                              : Container(
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
                                  ],
                                ),
                              ),
                              title: Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? primaryColor
                                      : Colors.white,
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
                                    tooltip:
                                        _musicService.isLiked(video.id.value)
                                        ? 'Remove from Liked'
                                        : 'Like Song',
                                    icon: Icon(
                                      _musicService.isLiked(video.id.value)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color:
                                          _musicService.isLiked(video.id.value)
                                          ? const Color(0xFFFA2D48)
                                          : Colors.white38,
                                      size: 19,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _musicService.toggleLike(video);
                                      if (AuthService().isAuthenticated) {
                                        unawaited(CloudSyncService().sync());
                                      }
                                    },
                                  ),
                                  Builder(
                                    builder: (btnCtx) => IconButton(
                                      icon: const Icon(
                                        Icons.more_vert_rounded,
                                        color: Colors.white38,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        final isDesktop =
                                            kIsWeb ||
                                            MediaQuery.of(context).size.width >=
                                                640;
                                        if (isDesktop) {
                                          final box =
                                              btnCtx.findRenderObject()
                                                  as RenderBox?;
                                          final pos = box != null
                                              ? box.localToGlobal(
                                                  box.size.bottomLeft(
                                                    Offset.zero,
                                                  ),
                                                )
                                              : Offset.zero;
                                          showUnifiedTrackMenu(
                                            context: context,
                                            globalPosition: pos,
                                            song: video,
                                          );
                                        } else {
                                          showSongOptionsBottomSheet(
                                            context,
                                            video,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _musicService.playPlaylist(_tracks, index);
                              },
                            ),
                          );
                        }, childCount: _tracks.length),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: DesktopPlaylistEnrichment(
                        playlistId: null,
                        existingSongs: _tracks,
                        onAddTrack: (song) {
                          setState(() {
                            _tracks.add(song);
                          });
                          if (AuthService().isAuthenticated) {
                            unawaited(CloudSyncService().sync());
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Mini Player
          if (MediaQuery.of(context).size.width < 640)
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
        if (MediaQuery.of(context).size.width >= 640) {
          DesktopLayoutState.openAlbum(
            album: album,
            albumId: album.id,
            albumTitle: album.title,
            albumArtwork: album.artwork,
            albumArtist: album.artist,
          );
        } else {
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
        }
      },
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        showUnifiedAlbumMenu(
          context: context,
          globalPosition: details.globalPosition,
          album: album,
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
          colors: [Color(0xFF1A1A24), Color(0xFF121217)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.album_rounded, size: 36, color: Colors.white38),
      ),
    );
  }

  Widget _buildHeroImage() {
    final primaryUrl = _resolveHeroImageUrl();
    if (primaryUrl == null || primaryUrl.isEmpty) {
      return _buildFallbackHeroArt();
    }

    final String? albumArtwork =
        _relatedAlbums.isNotEmpty &&
            _relatedAlbums.first.artwork.trim().isNotEmpty &&
            _relatedAlbums.first.artwork.trim() != primaryUrl
        ? _relatedAlbums.first.artwork.trim()
        : null;

    final String? firstSongThumb = _tracks.isNotEmpty
        ? MusicService.getHdThumbnail(_tracks.first.id.value)
        : null;
    final String genreFallback = _getCuratedGenreFallback(widget.title);

    return Image.network(
      primaryUrl,
      fit: BoxFit.cover,
      cacheWidth: 320,
      cacheHeight: 320,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFF16161E),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) {
        // Priority 1: High-res JioSaavn Album Artwork
        if (albumArtwork != null && albumArtwork.isNotEmpty) {
          return Image.network(
            albumArtwork,
            fit: BoxFit.cover,
            cacheWidth: 320,
            cacheHeight: 320,
            errorBuilder: (_, _, _) => _buildFirstSongOrGenreFallback(
              firstSongThumb,
              genreFallback,
              primaryUrl,
            ),
          );
        }
        return _buildFirstSongOrGenreFallback(
          firstSongThumb,
          genreFallback,
          primaryUrl,
        );
      },
    );
  }

  Widget _buildFirstSongOrGenreFallback(
    String? firstSongThumb,
    String genreFallback,
    String primaryUrl,
  ) {
    if (firstSongThumb != null &&
        firstSongThumb.isNotEmpty &&
        firstSongThumb != primaryUrl) {
      return Image.network(
        firstSongThumb,
        fit: BoxFit.cover,
        cacheWidth: 320,
        cacheHeight: 320,
        errorBuilder: (_, _, _) =>
            _buildGenreOrFallback(genreFallback, primaryUrl),
      );
    }
    return _buildGenreOrFallback(genreFallback, primaryUrl);
  }

  Widget _buildGenreOrFallback(String genreFallback, String originalUrl) {
    if (genreFallback != originalUrl) {
      return Image.network(
        genreFallback,
        fit: BoxFit.cover,
        cacheWidth: 320,
        cacheHeight: 320,
        errorBuilder: (_, _, _) => _buildFallbackHeroArt(),
      );
    }
    return _buildFallbackHeroArt();
  }

  String? _resolveHeroImageUrl() {
    // a) Explicit category.thumbnailUrl if present and non-empty
    if (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty) {
      return widget.imageUrl!.trim();
    }
    // b) Related albums artwork (JioSaavn CDN 500x500 authentic high-res album cover)
    if (_relatedAlbums.isNotEmpty &&
        _relatedAlbums.first.artwork.trim().isNotEmpty) {
      return _relatedAlbums.first.artwork.trim();
    }
    // c) Artwork URL of the first song in the category tracklist (songs.first.artworkUrl)
    if (_tracks.isNotEmpty) {
      final hd = MusicService.getHdThumbnail(_tracks.first.id.value);
      if (hd.isNotEmpty) return hd;
      if (_tracks.first.thumbnails.highResUrl.isNotEmpty) {
        return _tracks.first.thumbnails.highResUrl;
      }
    }
    // d) A curated high-resolution genre fallback cover
    return _getCuratedGenreFallback(widget.title);
  }

  static String _getCuratedGenreFallback(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('bollywood') || lower.contains('hindi')) {
      return 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&q=80';
    } else if (lower.contains('supermix') || lower.contains('my supermix')) {
      return 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80';
    } else if (lower.contains('discover')) {
      return 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=500&q=80';
    } else if (lower.contains('new release') || lower.contains('release mix')) {
      return 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&q=80';
    } else if (lower.contains('forgotten')) {
      return 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=500&q=80';
    } else if (lower.contains('daily mix') || lower.contains('mix')) {
      return 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=500&q=80';
    } else if (lower.contains('telugu')) {
      return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&q=80';
    } else if (lower.contains('pop') || lower.contains('global')) {
      return 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80';
    } else if (lower.contains('punjabi')) {
      return 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=500&q=80';
    } else if (lower.contains('lo-fi') ||
        lower.contains('chill') ||
        lower.contains('relax')) {
      return 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=500&q=80';
    } else if (lower.contains('workout') || lower.contains('energy')) {
      return 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=500&q=80';
    } else if (lower.contains('romance') || lower.contains('love')) {
      return 'https://images.unsplash.com/photo-1518199266791-5375a83190b7?w=500&q=80';
    } else if (lower.contains('hip-hop') || lower.contains('rap')) {
      return 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=500&q=80';
    } else if (lower.contains('party') ||
        lower.contains('dance') ||
        lower.contains('club')) {
      return 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=500&q=80';
    } else if (lower.contains('indie') || lower.contains('acoustic')) {
      return 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=500&q=80';
    } else if (lower.contains('tamil')) {
      return 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=500&q=80';
    } else if (lower.contains('malayalam')) {
      return 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80';
    } else if (lower.contains('kannada')) {
      return 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=500&q=80';
    } else if (lower.contains('devotional') || lower.contains('bhakti')) {
      return 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=500&q=80';
    } else if (lower.contains('ghazal') || lower.contains('sufi')) {
      return 'https://images.unsplash.com/photo-1447752875215-b2761acb3c5d?w=500&q=80';
    } else if (lower.contains('rock') || lower.contains('metal')) {
      return 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=500&q=80';
    } else if (lower.contains('sleep')) {
      return 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500&q=80';
    } else if (lower.contains('classical') || lower.contains('carnatic')) {
      return 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500&q=80';
    } else if (lower.contains('late night') || lower.contains('midnight')) {
      return 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=500&q=80';
    }
    return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&q=80';
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
