import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/music_service.dart';
import '../services/playlist_artist_filter.dart';
import '../services/preferences_service.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/mini_player.dart';
import '../widgets/playlist_action_menu.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/desktop/desktop_context_menu.dart';
import '../widgets/desktop/desktop_playlist_enrichment.dart';
import '../layouts/desktop_layout_state.dart';

class CustomPlaylistScreen extends StatefulWidget {
  final String playlistId;
  const CustomPlaylistScreen({super.key, required this.playlistId});

  @override
  State<CustomPlaylistScreen> createState() => _CustomPlaylistScreenState();
}

class _CustomPlaylistScreenState extends State<CustomPlaylistScreen> {
  final MusicService _musicService = MusicService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  String _searchQuery = '';
  bool _isSearchingGlobal = false;
  bool _showExpandedRecommendations = false;
  List<Video> _globalRecommendations = [];

  @override
  void initState() {
    super.initState();
    _musicService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _musicService.removeListener(_onServiceChanged);
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchGlobalRecommendations(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    setState(() => _isSearchingGlobal = true);
    try {
      final results = await _musicService.searchSongs(trimmed);
      if (mounted && _searchController.text.trim() == trimmed) {
        setState(() {
          _globalRecommendations = results;
          _isSearchingGlobal = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingGlobal = false);
    }
  }

  void _onSearchQueryChanged(String query) {
    final trimmed = query.trim();
    final isLikedSongs = widget.playlistId == 'liked_songs';
    final playlist = isLikedSongs
        ? <String, dynamic>{
            'id': 'liked_songs',
            'name': 'Liked Songs',
            'isLiked': true,
            'isPermanent': true,
            'songs': _musicService.likedSongs
                .map((s) => Map<String, dynamic>.from(s))
                .toList(),
          }
        : _musicService.customPlaylists.firstWhere(
            (p) => p['id'] == widget.playlistId,
            orElse: () => <String, dynamic>{},
          );
    final songs = List<Map<String, dynamic>>.from(playlist['songs'] ?? []);
    final searchResult = PlaylistArtistFilter.searchPlaylist(
      songs: songs,
      query: trimmed,
    );

    setState(() {
      _searchQuery = trimmed;
      _showExpandedRecommendations = false;
      if (trimmed.length < 2) {
        _globalRecommendations = [];
        _isSearchingGlobal = false;
      }
    });

    _debounceTimer?.cancel();

    // If query is absent from this playlist, automatically debounce-fetch catalog recommendations to add!
    // But if songs of that artist or title ARE in this playlist, do not flood the screen with YouTube recommendations.
    if (trimmed.length >= 2 && searchResult.matchedIndices.isEmpty) {
      _debounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _searchController.text.trim() != trimmed) return;
        _fetchGlobalRecommendations(trimmed);
      });
    } else {
      setState(() {
        _globalRecommendations = [];
        _isSearchingGlobal = false;
      });
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final nonNegative = d.isNegative ? Duration.zero : d;
    final hours = nonNegative.inHours;
    final minutes = nonNegative.inMinutes.remainder(60);
    final seconds = (nonNegative.inSeconds.remainder(
      60,
    )).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isLikedSongs = widget.playlistId == 'liked_songs';
    final playlist = isLikedSongs
        ? <String, dynamic>{
            'id': 'liked_songs',
            'name': 'Liked Songs',
            'isLiked': true,
            'isPermanent': true,
            'songs': _musicService.likedSongs
                .map((s) => Map<String, dynamic>.from(s))
                .toList(),
          }
        : _musicService.customPlaylists.firstWhere(
            (p) => p['id'] == widget.playlistId,
            orElse: () => <String, dynamic>{},
          );

    if (playlist.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
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
        body: const Center(
          child: Text(
            'Playlist not found',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    final name =
        (playlist['name'] as String?) ??
        (isLikedSongs ? 'Liked Songs' : 'Custom Playlist');
    final songs = List<Map<String, dynamic>>.from(playlist['songs'] ?? []);
    final firstThumbnail = songs.isNotEmpty
        ? songs.first['thumbnail'] as String?
        : null;

    final topArtists = PlaylistArtistFilter.getTopArtistsWithCounts(
      songs,
      limit: 12,
    );

    // Filter local songs using PlaylistArtistFilter
    final isSearching = _searchQuery.isNotEmpty;
    final searchResult = isSearching
        ? PlaylistArtistFilter.searchPlaylist(songs: songs, query: _searchQuery)
        : const PlaylistSearchResult(matchedIndices: []);
    final localMatches = searchResult.matchedIndices
        .map((i) => songs[i])
        .toList();
    final localIndices = searchResult.matchedIndices;

    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          DilSeScrollbar(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: const Color(0xFF181822),
                  expandedHeight: 260,
                  pinned: true,
                  stretch: true,
                  leading: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        DesktopLayoutState.closeDetailView();
                      }
                    },
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: false,
                    titlePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isLikedSongs)
                          _buildLikedSongsArtwork()
                        else if (firstThumbnail != null &&
                            firstThumbnail.isNotEmpty)
                          Image.network(
                            firstThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultArtwork(),
                          )
                        else
                          _buildDefaultArtwork(),
                        // Gradient overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.3),
                                const Color(0xFF121212).withValues(alpha: 0.95),
                                const Color(0xFF121212),
                              ],
                              stops: const [0.0, 0.7, 1.0],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Buttons & Playlist Stats Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isLikedSongs
                                ? '${songs.length} ${songs.length == 1 ? "song" : "songs"}'
                                : '${songs.length} ${songs.length == 1 ? "track" : "tracks"} • Drag handle to reorder',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (songs.isNotEmpty) ...[
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 22,
                            ),
                            label: const Text(
                              'Play',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 4,
                            ),
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              if (isLikedSongs) {
                                _musicService.playLikedSong(
                                  _musicService.likedSongs.first,
                                );
                              } else {
                                _musicService.playCustomPlaylist(
                                  widget.playlistId,
                                  0,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.shuffle_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'Shuffle',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              if (!_musicService.isShuffle) {
                                _musicService.toggleShuffle();
                              }
                              if (isLikedSongs) {
                                _musicService.playLikedSong(
                                  _musicService.likedSongs.first,
                                );
                              } else {
                                _musicService.playCustomPlaylist(
                                  widget.playlistId,
                                  0,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (!isLikedSongs)
                          PlaylistActionMenu(
                            playlistId: widget.playlistId,
                            playlistName: name,
                            isSpotifyImport: PreferencesService()
                                .isSpotifyImportedPlaylist(widget.playlistId),
                            customTrigger: Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                            closeScreenOnDelete: true,
                            onRenamed: (_) {
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),

                // Search Bar in Playlist
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E28).withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSearching
                              ? themeColor.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.08),
                          width: 1.0,
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                        ),
                        cursorColor: themeColor,
                        decoration: InputDecoration(
                          hintText: 'Search songs in this playlist...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.40),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: isSearching ? themeColor : Colors.white54,
                            size: 20,
                          ),
                          suffixIcon: isSearching
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white60,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchQueryChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 13,
                          ),
                        ),
                        onChanged: _onSearchQueryChanged,
                      ),
                    ),
                  ),
                ),

                // Artist Quick Filter Chips
                if (topArtists.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: topArtists.length,
                          itemBuilder: (context, idx) {
                            final artistItem = topArtists[idx];
                            final isSelected =
                                PlaylistArtistFilter.isArtistMatch(
                                  _searchQuery,
                                  artistItem.name,
                                );

                            final activeTextColor = isSelected
                                ? (ThemeData.estimateBrightnessForColor(
                                            themeColor,
                                          ) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black)
                                : Colors.white.withValues(alpha: 0.85);
                            final activeIconColor = isSelected
                                ? activeTextColor
                                : Colors.white60;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                showCheckmark: false,
                                avatar: Icon(
                                  Icons.person_rounded,
                                  size: 14,
                                  color: activeIconColor,
                                ),
                                label: Text(
                                  '${artistItem.name} (${artistItem.count})',
                                  style: TextStyle(
                                    color: activeTextColor,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: themeColor,
                                backgroundColor: const Color(
                                  0xFF1E1E28,
                                ).withValues(alpha: 0.85),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: isSelected
                                        ? themeColor
                                        : Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                onSelected: (selected) {
                                  HapticFeedback.selectionClick();
                                  if (isSelected) {
                                    _searchController.clear();
                                    _onSearchQueryChanged('');
                                  } else {
                                    _searchController.text = artistItem.name;
                                    _onSearchQueryChanged(artistItem.name);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                // BODY A: When in Search Mode
                if (isSearching) ...[
                  // 1. Local Matches in this playlist
                  if (localMatches.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Row(
                          children: [
                            Icon(
                              searchResult.isArtistSearch
                                  ? Icons.mic_external_on_rounded
                                  : Icons.playlist_play_rounded,
                              color: themeColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                searchResult.isArtistSearch
                                    ? 'Songs by "${searchResult.matchedArtist}" in playlist (${localMatches.length})'
                                    : 'In this playlist (${localMatches.length})',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.90),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (searchResult.isArtistSearch)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: themeColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  'Artist Filter',
                                  style: TextStyle(
                                    color: themeColor,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = localMatches[index];
                        final songId = (song['id'] as String?) ?? '';
                        final originalIndex = localIndices[index];
                        final isCurrent =
                            _musicService.currentSong?.id.value == songId;
                        final thumb = song['thumbnail'] as String? ?? '';

                        return Container(
                          height: 72.0,
                          color: isCurrent
                              ? themeColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          child: Material(
                            color: Colors.transparent,
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                DesktopContextMenu.showSongMenu(
                                  context: context,
                                  globalPosition: details.globalPosition,
                                  song: songMapToVideo(song),
                                  currentPlaylistId: isLikedSongs
                                      ? null
                                      : widget.playlistId,
                                  onRemovedFromPlaylist: () => setState(() {}),
                                );
                              },
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child:
                                          isCurrent && _musicService.isPlaying
                                          ? Center(
                                              child: AnimatedEqualizer(
                                                isPlaying: true,
                                                color: themeColor,
                                                size: 16,
                                              ),
                                            )
                                          : Text(
                                              '${originalIndex + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: isCurrent
                                                    ? themeColor
                                                    : Colors.white.withValues(
                                                        alpha: 0.4,
                                                      ),
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: 13,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        color: const Color(0xFF1E1E28),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            thumb.isNotEmpty
                                                ? Image.network(
                                                    thumb,
                                                    width: 48,
                                                    height: 48,
                                                    cacheWidth: 120,
                                                    cacheHeight: 120,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const Icon(
                                                          Icons
                                                              .music_note_rounded,
                                                          color: Colors.white30,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.music_note_rounded,
                                                    color: Colors.white30,
                                                  ),
                                            if (isCurrent)
                                              Container(
                                                color: Colors.black45,
                                                child: Center(
                                                  child: AnimatedEqualizer(
                                                    isPlaying:
                                                        _musicService.isPlaying,
                                                    size: 18,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  (song['title'] as String?) ?? 'Unknown Title',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? themeColor
                                        : Colors.white,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 14.5,
                                  ),
                                ),
                                subtitle: Text(
                                  (song['author'] as String?) ??
                                      'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 12.5,
                                  ),
                                ),
                                trailing: Builder(
                                  builder: (btnCtx) => IconButton(
                                    key: ValueKey('local_match_more_$songId'),
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      color: Colors.white38,
                                      size: 20,
                                    ),
                                    tooltip: 'Song options',
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      if (kIsWeb ||
                                          MediaQuery.of(context).size.width >=
                                              1024) {
                                        final renderBox =
                                            btnCtx.findRenderObject()
                                                as RenderBox?;
                                        final offset =
                                            renderBox?.localToGlobal(
                                              Offset.zero,
                                            ) ??
                                            Offset.zero;
                                        final buttonSize =
                                            renderBox?.size ?? Size.zero;
                                        final menuPosition = Offset(
                                          offset.dx,
                                          offset.dy + buttonSize.height,
                                        );
                                        DesktopContextMenu.showSongMenu(
                                          context: context,
                                          globalPosition: menuPosition,
                                          song: songMapToVideo(song),
                                          currentPlaylistId: isLikedSongs
                                              ? null
                                              : widget.playlistId,
                                          onRemovedFromPlaylist: () =>
                                              setState(() {}),
                                        );
                                      } else {
                                        showPlaylistSongOptionsBottomSheet(
                                          context,
                                          songMap: song,
                                          playlistId: widget.playlistId,
                                          onPlayNow: () {
                                            if (isLikedSongs) {
                                              _musicService.playLikedSong(
                                                _musicService
                                                    .likedSongs[originalIndex],
                                              );
                                            } else {
                                              _musicService.playCustomPlaylist(
                                                widget.playlistId,
                                                originalIndex,
                                              );
                                            }
                                          },
                                        );
                                      }
                                    },
                                  ),
                                ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  if (isLikedSongs) {
                                    _musicService.playLikedSong(
                                      _musicService.likedSongs[originalIndex],
                                    );
                                  } else {
                                    _musicService.playCustomPlaylist(
                                      widget.playlistId,
                                      originalIndex,
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      }, childCount: localMatches.length),
                    ),
                    if (!_showExpandedRecommendations)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.add_circle_outline_rounded,
                              size: 18,
                              color: themeColor,
                            ),
                            label: Text(
                              searchResult.isArtistSearch
                                  ? 'Find more "${searchResult.matchedArtist}" songs from catalog'
                                  : 'Find more "$_searchQuery" songs from catalog',
                              style: TextStyle(
                                color: themeColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: themeColor.withValues(alpha: 0.40),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: themeColor.withValues(
                                alpha: 0.05,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(
                                () => _showExpandedRecommendations = true,
                              );
                              _fetchGlobalRecommendations(_searchQuery);
                            },
                          ),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ] else ...[
                    // Absence Notice Banner: Searched song is not in playlist
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E1E28,
                            ).withValues(alpha: 0.70),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.amber.withValues(alpha: 0.12),
                                ),
                                child: const Icon(
                                  Icons.search_off_rounded,
                                  color: Colors.amberAccent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '"$_searchQuery" is not in this playlist',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Discover and add matching tracks from DilSe catalog below:',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 2. Global Catalog Recommendations to Add (Shown if absent or explicitly expanded)
                  if (localMatches.isEmpty || _showExpandedRecommendations) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: themeColor,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              localMatches.isEmpty
                                  ? 'Recommended to Add to Playlist'
                                  : 'More Songs from Catalog (Tap to Add)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            if (_isSearchingGlobal) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (_isSearchingGlobal && _globalRecommendations.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: ShimmerSongRow(),
                        ),
                      )
                    else if (!_isSearchingGlobal &&
                        _globalRecommendations.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 32,
                            horizontal: 24,
                          ),
                          child: Center(
                            child: Text(
                              'No online songs found for "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final song = _globalRecommendations[index];
                          final songId = song.id.value;
                          final isInPlaylist = songs.any(
                            (s) => s['id'] == songId,
                          );
                          final isCurrent =
                              _musicService.currentSong?.id.value == songId;
                          final durationStr = _formatDuration(song.duration);

                          return Container(
                            height: 72.0,
                            color: isCurrent
                                ? themeColor.withValues(alpha: 0.12)
                                : Colors.transparent,
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                DesktopContextMenu.showSongMenu(
                                  context: context,
                                  globalPosition: details.globalPosition,
                                  song: song,
                                );
                              },
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    color: const Color(0xFF1E1E28),
                                    child: Image.network(
                                      MusicService.getHdThumbnail(songId),
                                      width: 48,
                                      height: 48,
                                      cacheWidth: 120,
                                      cacheHeight: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.music_note_rounded,
                                                color: Colors.white30,
                                              ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? themeColor
                                        : Colors.white,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 14.5,
                                  ),
                                ),
                                subtitle: Text(
                                  durationStr.isNotEmpty
                                      ? '${song.author} • $durationStr'
                                      : song.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 12.5,
                                  ),
                                ),
                                trailing: isInPlaylist
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.green.withValues(
                                              alpha: 0.40,
                                            ),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_rounded,
                                              color: Colors.greenAccent,
                                              size: 14,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Added',
                                              style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Add',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: themeColor,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          elevation: 2,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.mediumImpact();
                                          if (isLikedSongs) {
                                            _musicService.toggleLike(song);
                                          } else {
                                            _musicService.addSongToPlaylist(
                                              widget.playlistId,
                                              song,
                                            );
                                          }
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                isLikedSongs
                                                    ? 'Added "${song.title}" to Liked Songs'
                                                    : 'Added "${song.title}" to $name',
                                              ),
                                              backgroundColor: const Color(
                                                0xFF1E1E28,
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _musicService.playSong(song);
                                },
                              ),
                            ),
                          );
                        }, childCount: _globalRecommendations.length),
                      ),
                  ],
                ] else ...[
                  // BODY B: Standard Non-Search Playlist Mode
                  if (songs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 24,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLikedSongs
                                    ? Icons.favorite_border_rounded
                                    : Icons.music_note_rounded,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isLikedSongs
                                    ? 'No liked songs yet'
                                    : 'No songs in this playlist yet',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isLikedSongs
                                    ? 'Songs you like will appear here'
                                    : 'Find and add songs using the search and recommendations below',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (isLikedSongs)
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = songs[index];
                        final songId = (song['id'] as String?) ?? '';
                        final isCurrent =
                            _musicService.currentSong?.id.value == songId;
                        final thumb = song['thumbnail'] as String? ?? '';

                        return Dismissible(
                          key: ValueKey('liked_dismiss_${songId}_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            child: const Icon(
                              Icons.favorite_border_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          onDismissed: (_) {
                            HapticFeedback.mediumImpact();
                            _musicService.removeLikedSong(songId);
                          },
                          child: Container(
                            height: 72.0,
                            color: isCurrent
                                ? themeColor.withValues(alpha: 0.12)
                                : Colors.transparent,
                            child: Material(
                              color: Colors.transparent,
                              child: GestureDetector(
                                onSecondaryTapDown: (details) {
                                  DesktopContextMenu.showSongMenu(
                                    context: context,
                                    globalPosition: details.globalPosition,
                                    song: songMapToVideo(song),
                                  );
                                },
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child:
                                            isCurrent && _musicService.isPlaying
                                            ? Center(
                                                child: AnimatedEqualizer(
                                                  isPlaying: true,
                                                  color: themeColor,
                                                  size: 16,
                                                ),
                                              )
                                            : Text(
                                                '${index + 1}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: isCurrent
                                                      ? themeColor
                                                      : Colors.white.withValues(
                                                          alpha: 0.4,
                                                        ),
                                                  fontWeight: isCurrent
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  fontSize: 13,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          color: const Color(0xFF1E1E28),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              thumb.isNotEmpty
                                                  ? Image.network(
                                                      thumb,
                                                      width: 48,
                                                      height: 48,
                                                      cacheWidth: 120,
                                                      cacheHeight: 120,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) => const Icon(
                                                            Icons
                                                                .music_note_rounded,
                                                            color:
                                                                Colors.white30,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.music_note_rounded,
                                                      color: Colors.white30,
                                                    ),
                                              if (isCurrent)
                                                Container(
                                                  color: Colors.black45,
                                                  child: Center(
                                                    child: AnimatedEqualizer(
                                                      isPlaying: _musicService
                                                          .isPlaying,
                                                      size: 18,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    (song['title'] as String?) ??
                                        'Unknown Title',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isCurrent
                                          ? themeColor
                                          : Colors.white,
                                      fontWeight: isCurrent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  subtitle: Text(
                                    (song['author'] as String?) ??
                                        'Unknown Artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  trailing: Builder(
                                    builder: (btnCtx) => IconButton(
                                      key: ValueKey('liked_song_more_$songId'),
                                      icon: const Icon(
                                        Icons.more_vert_rounded,
                                        color: Colors.white38,
                                        size: 20,
                                      ),
                                      tooltip: 'Song options',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 40,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        if (kIsWeb ||
                                            MediaQuery.of(context).size.width >=
                                                1024) {
                                          final renderBox =
                                              btnCtx.findRenderObject()
                                                  as RenderBox?;
                                          final offset =
                                              renderBox?.localToGlobal(
                                                Offset.zero,
                                              ) ??
                                              Offset.zero;
                                          final buttonSize =
                                              renderBox?.size ?? Size.zero;
                                          final menuPosition = Offset(
                                            offset.dx,
                                            offset.dy + buttonSize.height,
                                          );
                                          DesktopContextMenu.showSongMenu(
                                            context: context,
                                            globalPosition: menuPosition,
                                            song: songMapToVideo(song),
                                            currentPlaylistId: null,
                                            onRemovedFromPlaylist: () =>
                                                setState(() {}),
                                          );
                                        } else {
                                          showPlaylistSongOptionsBottomSheet(
                                            context,
                                            songMap: song,
                                            playlistId: widget.playlistId,
                                            onPlayNow: () {
                                              _musicService.playLikedSong(
                                                _musicService.likedSongs[index],
                                              );
                                            },
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _musicService.playLikedSong(
                                      _musicService.likedSongs[index],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      }, childCount: songs.length),
                    )
                  else
                    SliverReorderableList(
                      itemCount: songs.length,
                      itemExtent: 72.0,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.lightImpact();
                        _musicService.reorderPlaylistSongs(
                          widget.playlistId,
                          oldIndex,
                          newIndex,
                        );
                      },
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final songId = (song['id'] as String?) ?? '';
                        final isCurrent =
                            _musicService.currentSong?.id.value == songId;
                        final thumb = song['thumbnail'] as String? ?? '';

                        return ReorderableDelayedDragStartListener(
                          key: ValueKey('song_${songId}_$index'),
                          index: index,
                          child: Dismissible(
                            key: ValueKey('dismiss_${songId}_$index'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            onDismissed: (_) {
                              HapticFeedback.mediumImpact();
                              _musicService.removeSongFromPlaylist(
                                widget.playlistId,
                                songId,
                              );
                            },
                            child: Container(
                              height: 72.0,
                              color: isCurrent
                                  ? themeColor.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              child: Material(
                                color: Colors.transparent,
                                child: GestureDetector(
                                  onSecondaryTapDown: (details) {
                                    DesktopContextMenu.showSongMenu(
                                      context: context,
                                      globalPosition: details.globalPosition,
                                      song: songMapToVideo(song),
                                      currentPlaylistId: widget.playlistId,
                                      onRemovedFromPlaylist: () =>
                                          setState(() {}),
                                    );
                                  },
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 28,
                                          child:
                                              isCurrent &&
                                                  _musicService.isPlaying
                                              ? Center(
                                                  child: AnimatedEqualizer(
                                                    isPlaying: true,
                                                    color: themeColor,
                                                    size: 16,
                                                  ),
                                                )
                                              : Text(
                                                  '${index + 1}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: isCurrent
                                                        ? themeColor
                                                        : Colors.white
                                                              .withValues(
                                                                alpha: 0.4,
                                                              ),
                                                    fontWeight: isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                    fontSize: 13,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Container(
                                            width: 48,
                                            height: 48,
                                            color: const Color(0xFF1E1E28),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                thumb.isNotEmpty
                                                    ? Image.network(
                                                        thumb,
                                                        width: 48,
                                                        height: 48,
                                                        cacheWidth: 120,
                                                        cacheHeight: 120,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) => const Icon(
                                                              Icons
                                                                  .music_note_rounded,
                                                              color: Colors
                                                                  .white30,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .music_note_rounded,
                                                        color: Colors.white30,
                                                      ),
                                                if (isCurrent)
                                                  Container(
                                                    color: Colors.black45,
                                                    child: Center(
                                                      child: AnimatedEqualizer(
                                                        isPlaying: _musicService
                                                            .isPlaying,
                                                        size: 18,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    title: Text(
                                      (song['title'] as String?) ??
                                          'Unknown Title',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? themeColor
                                            : Colors.white,
                                        fontWeight: isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    subtitle: Text(
                                      (song['author'] as String?) ??
                                          'Unknown Artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Builder(
                                          builder: (btnCtx) => IconButton(
                                            key: ValueKey(
                                              'playlist_song_more_$songId',
                                            ),
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                              color: Colors.white38,
                                              size: 20,
                                            ),
                                            tooltip: 'Song options',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 36,
                                              minHeight: 40,
                                            ),
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              if (kIsWeb ||
                                                  MediaQuery.of(
                                                        context,
                                                      ).size.width >=
                                                      1024) {
                                                final renderBox =
                                                    btnCtx.findRenderObject()
                                                        as RenderBox?;
                                                final offset =
                                                    renderBox?.localToGlobal(
                                                      Offset.zero,
                                                    ) ??
                                                    Offset.zero;
                                                final buttonSize =
                                                    renderBox?.size ??
                                                    Size.zero;
                                                final menuPosition = Offset(
                                                  offset.dx,
                                                  offset.dy + buttonSize.height,
                                                );
                                                DesktopContextMenu.showSongMenu(
                                                  context: context,
                                                  globalPosition: menuPosition,
                                                  song: songMapToVideo(song),
                                                  currentPlaylistId:
                                                      widget.playlistId,
                                                  onRemovedFromPlaylist: () =>
                                                      setState(() {}),
                                                );
                                              } else {
                                                showPlaylistSongOptionsBottomSheet(
                                                  context,
                                                  songMap: song,
                                                  playlistId: widget.playlistId,
                                                  onPlayNow: () {
                                                    _musicService
                                                        .playCustomPlaylist(
                                                          widget.playlistId,
                                                          index,
                                                        );
                                                  },
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Container(
                                            width: 36,
                                            height: 40,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.drag_handle_rounded,
                                              color: Colors.white38,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _musicService.playCustomPlaylist(
                                        widget.playlistId,
                                        index,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  SliverToBoxAdapter(
                    child: DesktopPlaylistEnrichment(
                      playlistId: widget.playlistId,
                      existingSongs: songs,
                      onSongAdded: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],

                // Bottom spacing: dynamic clearance for floating MiniPlayer
                SliverToBoxAdapter(
                  child: SizedBox(
                    height:
                        (MediaQuery.of(context).size.width < 1024 &&
                            _musicService.currentSong != null)
                        ? 96
                        : 40,
                  ),
                ),
              ],
            ),
          ),
          // Floating MiniPlayer visible over playlist content when a song is playing (mobile only)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: MusicService(),
              builder: (context, _) {
                if (MediaQuery.of(context).size.width >= 1024 ||
                    MusicService().currentSong == null) {
                  return const SizedBox.shrink();
                }
                return const MiniPlayer();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikedSongsArtwork() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5018F0), Color(0xFF8A2BE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.favorite_rounded, size: 72, color: Colors.white),
      ),
    );
  }

  Widget _buildDefaultArtwork() {
    final themeColor = PreferencesService().themeColor;
    return Container(
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: 72,
          color: themeColor.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
