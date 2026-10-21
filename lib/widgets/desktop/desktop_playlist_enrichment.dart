import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/auth_service.dart';
import '../../services/canonical_song_dedup.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/music_service.dart';
import 'desktop_context_menu.dart';

/// Spotify-grade Playlist Enrichment Suite for DilSe Music.
///
/// Anchored directly at the bottom of the playlist scroll view.
/// Features:
/// 1. "Let's find something for your playlist" with collapsible 'X' button & debounced search.
/// 2. Dynamic "Recommended" shelf based on playlist seeds with "Find more" refresh action.
/// 3. Instant "Add" pill button with green checkmark animation, live appending, and CloudSync.
/// 4. Secondary-click (right-click) context menu via [showUnifiedTrackMenu].
class DesktopPlaylistEnrichment extends StatefulWidget {
  final String? playlistId;
  final List<dynamic> existingSongs;
  final void Function(Video song)? onAddTrack;
  final VoidCallback? onSongAdded;

  const DesktopPlaylistEnrichment({
    super.key,
    this.playlistId,
    required this.existingSongs,
    this.onAddTrack,
    this.onSongAdded,
  });

  @override
  State<DesktopPlaylistEnrichment> createState() =>
      _DesktopPlaylistEnrichmentState();
}

class _DesktopPlaylistEnrichmentState extends State<DesktopPlaylistEnrichment> {
  final MusicService _musicService = MusicService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSectionVisible = true;
  Timer? _debounceTimer;
  bool _isSearching = false;
  List<Video> _searchResults = [];

  bool _isLoadingRecommendations = false;
  List<Video> _recommendedTracks = [];
  final Set<String> _addedSongIds = {};
  int _refreshCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  @override
  void didUpdateWidget(covariant DesktopPlaylistEnrichment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.existingSongs.length != oldWidget.existingSongs.length &&
        _recommendedTracks.isEmpty &&
        !_isLoadingRecommendations) {
      _fetchRecommendations();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _extractSongId(dynamic song) {
    if (song is Video) return song.id.value;
    if (song is Map<String, dynamic>) {
      return (song['id'] as String?) ?? '';
    }
    return '';
  }

  String _extractSongTitle(dynamic song) {
    if (song is Video) return song.title;
    if (song is Map<String, dynamic>) {
      return (song['title'] as String?) ?? '';
    }
    return '';
  }

  String _extractSongArtist(dynamic song) {
    if (song is Video) return song.author;
    if (song is Map<String, dynamic>) {
      return (song['author'] as String?) ?? '';
    }
    return '';
  }

  Set<String> _getExistingSongIds() {
    final ids = widget.existingSongs
        .map(_extractSongId)
        .where((id) => id.isNotEmpty)
        .toSet();
    ids.addAll(_addedSongIds);
    return ids;
  }

  Future<void> _fetchRecommendations({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingRecommendations = true;
    });

    try {
      final existingIds = _getExistingSongIds();
      final candidates = <Video>[];

      if (widget.existingSongs.isNotEmpty) {
        final reversedSongs = widget.existingSongs.reversed.toList();
        final seedCount = reversedSongs.length < 3 ? reversedSongs.length : 3;
        final offset = forceRefresh
            ? (_refreshCount * 2) % reversedSongs.length
            : 0;

        final seeds = <dynamic>[];
        for (int i = 0; i < seedCount; i++) {
          seeds.add(reversedSongs[(offset + i) % reversedSongs.length]);
        }

        for (final seed in seeds) {
          final seedId = _extractSongId(seed);
          final seedTitle = _extractSongTitle(seed);
          final seedArtist = _extractSongArtist(seed);

          if (seedId.isNotEmpty) {
            final res = await _musicService.fetchNextCandidates(
              seedId,
              limit: 15,
              title: seedTitle.isNotEmpty ? seedTitle : null,
              artist: seedArtist.isNotEmpty ? seedArtist : null,
            );
            if (res.isNotEmpty) {
              candidates.addAll(res);
            }
          }
          if (candidates.length < 10 && seedArtist.isNotEmpty) {
            final artistSongs = await _musicService.searchSongs(
              '$seedArtist hits',
            );
            candidates.addAll(artistSongs);
          }
        }
      }

      // Fallback seeds if playlist is empty or candidates pool is small
      if (candidates.length < 5) {
        final fallbackQueries = [
          'Top Bollywood Hits',
          'Trending Indian Songs',
          'Global Top Hits',
          'Acoustic Chill Hits',
        ];
        final q = fallbackQueries[_refreshCount % fallbackQueries.length];
        final fallbackSongs = await _musicService.searchSongs(q);
        candidates.addAll(fallbackSongs);
      }

      // Deduplication & filtering against existing tracks
      final genuine = candidates
          .where((s) => CanonicalSongDedup.isGenuineSong(s))
          .toList();
      final deduped = CanonicalSongDedup.deduplicateList(genuine);
      final fresh = deduped
          .where((s) => !existingIds.contains(s.id.value))
          .take(10)
          .toList();

      if (mounted) {
        setState(() {
          _recommendedTracks = fresh;
          _isLoadingRecommendations = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingRecommendations = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _searchController.text.trim() != trimmed) return;
      try {
        final results = await _musicService.searchSongs(trimmed);
        if (mounted && _searchController.text.trim() == trimmed) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  void _handleAddSong(Video song) {
    HapticFeedback.mediumImpact();
    setState(() {
      _addedSongIds.add(song.id.value);
    });

    if (widget.onAddTrack != null) {
      widget.onAddTrack!(song);
    } else if (widget.playlistId == 'liked_songs') {
      _musicService.toggleLike(song);
    } else if (widget.playlistId != null) {
      _musicService.addSongToPlaylist(widget.playlistId!, song);
    }

    widget.onSongAdded?.call();

    if (AuthService().isAuthenticated) {
      unawaited(CloudSyncService().sync());
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${song.title}" to playlist'),
        backgroundColor: const Color(0xFF1E1E24),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleSectionVisibility() {
    HapticFeedback.selectionClick();
    setState(() {
      _isSectionVisible = !_isSectionVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSectionVisible) {
      return Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(
            Icons.search_rounded,
            size: 16,
            color: Colors.white70,
          ),
          label: const Text(
            'Find more songs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
          ),
          onPressed: _toggleSectionVisibility,
        ),
      );
    }

    final hasSearchQuery = _searchController.text.trim().length >= 2;
    final existingIds = _getExistingSongIds();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Title & Dismiss Button
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Let's find something for your playlist",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFA7A7A7),
                  size: 22,
                ),
                tooltip: 'Collapse section',
                onPressed: _toggleSectionVisibility,
              ),
            ],
          ),

          // 2. Search Input Field
          Container(
            height: 44,
            margin: const EdgeInsets.only(top: 16, bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFFA7A7A7),
                  size: 20,
                ),
                hintText: 'Search for songs or episodes',
                hintStyle: const TextStyle(
                  color: Color(0xFFA7A7A7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFFA7A7A7),
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // 3. Live Search Results (if querying)
          if (hasSearchQuery || _isSearching) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Text(
                    'Search Results',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_isSearching) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_isSearching && _searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No songs found for "${_searchController.text.trim()}".',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                  ),
                ),
              )
            else
              ..._searchResults.map(
                (song) => _EnrichmentSongRow(
                  song: song,
                  playlistId: widget.playlistId,
                  isAdded: existingIds.contains(song.id.value),
                  onAdd: () => _handleAddSong(song),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _musicService.playSong(song);
                  },
                ),
              ),
            const SizedBox(height: 24),
          ],

          // 4. Smart Recommendations Sub-Section ("Recommended")
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommended',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Based on what's in this playlist",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                icon: _isLoadingRecommendations
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFB3B3B3),
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFB3B3B3),
                        size: 16,
                      ),
                label: const Text(
                  'Find more',
                  style: TextStyle(
                    color: Color(0xFFB3B3B3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: _isLoadingRecommendations
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _refreshCount++;
                        _fetchRecommendations(forceRefresh: true);
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Recommended Tracks List
          if (_isLoadingRecommendations && _recommendedTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white38,
                  ),
                ),
              ),
            )
          else if (_recommendedTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No recommendations found. Tap "Find more" above to refresh.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 13,
                ),
              ),
            )
          else
            ..._recommendedTracks.map(
              (song) => _EnrichmentSongRow(
                song: song,
                playlistId: widget.playlistId,
                isAdded: existingIds.contains(song.id.value),
                onAdd: () => _handleAddSong(song),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _musicService.playSong(song);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Spotify-style song row inside the playlist enrichment container.
class _EnrichmentSongRow extends StatefulWidget {
  final Video song;
  final String? playlistId;
  final bool isAdded;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  const _EnrichmentSongRow({
    required this.song,
    required this.playlistId,
    required this.isAdded,
    required this.onAdd,
    required this.onTap,
  });

  @override
  State<_EnrichmentSongRow> createState() => _EnrichmentSongRowState();
}

class _EnrichmentSongRowState extends State<_EnrichmentSongRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final albumTitle =
        MusicService.getCachedAlbumTitle(widget.song.id.value) ??
        MusicService.extractMovieOrAlbumTitle(widget.song.title);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          showUnifiedTrackMenu(
            context: context,
            globalPosition: details.globalPosition,
            song: widget.song,
            currentPlaylistId: widget.playlistId,
          );
        },
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            children: [
              // 40x40 squircle thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: Container(
                  width: 40,
                  height: 40,
                  color: const Color(0xFF282828),
                  child: Image.network(
                    MusicService.getHdThumbnail(widget.song.id.value),
                    width: 40,
                    height: 40,
                    cacheWidth: 80,
                    cacheHeight: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white30,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title & Artist details
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: widget.onTap,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.song.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Album Column on Desktop (>= 1024px)
              if (isDesktop) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Text(
                    albumTitle != null && albumTitle.isNotEmpty
                        ? albumTitle
                        : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.40),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(width: 16),

              // "Add" Stadium Pill Button
              widget.isAdded
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                        border: Border.all(
                          color: const Color(
                            0xFF1DB954,
                          ).withValues(alpha: 0.50),
                          width: 1.0,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            color: Color(0xFF1DB954),
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Added',
                            style: TextStyle(
                              color: Color(0xFF1DB954),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : OutlinedButton(
                      onPressed: widget.onAdd,
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.0,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        backgroundColor: Colors.transparent,
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
