import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    show Video, VideoId, ChannelId, ThumbnailSet, Engagement;
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';
import '../services/album_color_deriver.dart';
import '../services/canonical_song_dedup.dart';
import '../utils/image_utils.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/mini_player.dart';
import '../widgets/playlist_action_menu.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/desktop/desktop_context_menu.dart';
import '../widgets/desktop/desktop_playlist_enrichment.dart';
import '../widgets/desktop/desktop_playlist_toolbar.dart';
import '../layouts/desktop_layout_state.dart';

class CustomPlaylistScreen extends StatefulWidget {
  final String playlistId;
  const CustomPlaylistScreen({super.key, required this.playlistId});

  @override
  State<CustomPlaylistScreen> createState() => _CustomPlaylistScreenState();
}

class _CustomPlaylistScreenState extends State<CustomPlaylistScreen> {
  final MusicService _musicService = MusicService();
  final ScrollController _scrollController = ScrollController();

  late PlaylistSortOption _currentSort;
  late PlaylistViewMode _currentViewMode;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentSort = PreferencesService().playlistSortOption;
    _currentViewMode = PreferencesService().playlistViewMode;
    _musicService.addListener(_onServiceChanged);
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

  Future<void> _showEditDetailsModal(
    BuildContext context,
    String currentName,
  ) async {
    final nameCtrl = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1.0,
          ),
        ),
        title: const Text(
          'Edit details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Playlist Name',
                style: TextStyle(
                  color: Color(0xFFA3A3A3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF222222),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty && newName != currentName) {
                _musicService.renamePlaylist(widget.playlistId, newName);
                if (mounted) setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
  }

  List<Map<String, dynamic>> _getDisplayedSongs(
    List<Map<String, dynamic>> originalSongs,
  ) {
    final list = List<Map<String, dynamic>>.from(originalSongs);
    switch (_currentSort) {
      case PlaylistSortOption.customOrder:
        break;
      case PlaylistSortOption.title:
        list.sort(
          (a, b) => (a['title']?.toString().toLowerCase() ?? '').compareTo(
            b['title']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case PlaylistSortOption.artist:
        list.sort(
          (a, b) => (a['author']?.toString().toLowerCase() ?? '').compareTo(
            b['author']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case PlaylistSortOption.album:
        list.sort(
          (a, b) => (a['album']?.toString().toLowerCase() ?? '').compareTo(
            b['album']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case PlaylistSortOption.recentlyAdded:
        return list.reversed.toList();
      case PlaylistSortOption.releaseDate:
        list.sort(
          (a, b) => (b['album']?.toString().toLowerCase() ?? '').compareTo(
            a['album']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case PlaylistSortOption.duration:
        list.sort((a, b) {
          final durA = (a['durationMs'] as num?)?.toInt() ?? 0;
          final durB = (b['durationMs'] as num?)?.toInt() ?? 0;
          return durA.compareTo(durB);
        });
        break;
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return list.where((s) {
        final t = (s['title']?.toString() ?? '').toLowerCase();
        final a = (s['author']?.toString() ?? '').toLowerCase();
        final al = (s['album']?.toString() ?? '').toLowerCase();
        return t.contains(q) || a.contains(q) || al.contains(q);
      }).toList();
    }

    return list;
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

    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final displayedSongs = _getDisplayedSongs(songs);
    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          DilSeScrollbar(
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  backgroundColor: const Color(0xFF181818),
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
                    background: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        showUnifiedPlaylistMenu(
                          context: context,
                          globalPosition: details.globalPosition,
                          playlist: isLikedSongs
                              ? 'liked_songs'
                              : {
                                  'id': widget.playlistId,
                                  'name': name,
                                  'isSpotify': PreferencesService()
                                      .isSpotifyImportedPlaylist(
                                        widget.playlistId,
                                      ),
                                  'songs': songs,
                                },
                        );
                      },
                      child: Stack(
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
                                  const Color(
                                    0xFF121212,
                                  ).withValues(alpha: 0.95),
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
                              if (isLikedSongs) {
                                if (_musicService.likedSongs.isNotEmpty) {
                                  _musicService.playLikedSong(
                                    _musicService.likedSongs.first,
                                    enableShuffle: true,
                                  );
                                }
                              } else {
                                _musicService.playCustomPlaylistWithShuffle(
                                  widget.playlistId,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (isLikedSongs)
                          Builder(
                            builder: (btnCtx) => IconButton(
                              tooltip: 'Playlist options',
                              icon: Container(
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
                              onPressed: () {
                                final renderBox =
                                    btnCtx.findRenderObject() as RenderBox?;
                                final offset =
                                    renderBox?.localToGlobal(Offset.zero) ??
                                    Offset.zero;
                                final size = renderBox?.size ?? Size.zero;
                                showUnifiedPlaylistMenu(
                                  context: context,
                                  globalPosition: Offset(
                                    offset.dx,
                                    offset.dy + size.height,
                                  ),
                                  playlist: 'liked_songs',
                                );
                              },
                            ),
                          )
                        else
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

                // Spotify Desktop Playlist Toolbar & Sticky Table Header
                if (isDesktop) ...[
                  SliverToBoxAdapter(
                    child: DesktopPlaylistToolbar(
                      showAddButton: true,
                      showEditDetailsButton: !isLikedSongs,
                      searchQuery: _searchQuery,
                      onSearchChanged: (query) =>
                          setState(() => _searchQuery = query),
                      onAddTap: () {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                      onEditDetailsTap: () =>
                          _showEditDetailsModal(context, name),
                      currentSort: _currentSort,
                      currentViewMode: _currentViewMode,
                      onSortChanged: (sort) {
                        setState(() => _currentSort = sort);
                        PreferencesService().setPlaylistSortOption(sort);
                      },
                      onViewModeChanged: (mode) {
                        setState(() => _currentViewMode = mode);
                        PreferencesService().setPlaylistViewMode(mode);
                      },
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildStickyTableHeader(context)),
                ],

                if (isDesktop) ...[
                  if (displayedSongs.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(
                        isLikedSongs: isLikedSongs,
                        isSearch: _searchQuery.trim().isNotEmpty,
                        searchQuery: _searchQuery,
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = displayedSongs[index];
                        final songId = (song['id'] as String?) ?? '';
                        final isCurrent =
                            _musicService.currentSong?.id.value == songId;
                        final originalIndex = songs.indexWhere(
                          (s) => s['id'] == songId,
                        );
                        final displayIndex =
                            _currentSort == PlaylistSortOption.customOrder
                            ? (originalIndex >= 0
                                  ? originalIndex + 1
                                  : index + 1)
                            : index + 1;

                        return _DesktopTrackRowWidget(
                          key: ValueKey('desktop_song_${songId}_$index'),
                          song: song,
                          songId: songId,
                          index: displayIndex,
                          isCurrent: isCurrent,
                          isPlaying: isCurrent && _musicService.isPlaying,
                          viewMode: _currentViewMode,
                          playlistId: widget.playlistId,
                          isLikedSongs: isLikedSongs,
                          themeColor: themeColor,
                          onPlay: () {
                            HapticFeedback.lightImpact();
                            if (isLikedSongs) {
                              final likedIdx = _musicService.likedSongs
                                  .indexWhere((s) => s['id'] == songId);
                              if (likedIdx >= 0) {
                                _musicService.playLikedSong(
                                  _musicService.likedSongs[likedIdx],
                                );
                              } else {
                                _musicService.playSong(songMapToVideo(song));
                              }
                            } else {
                              final pIdx = songs.indexWhere(
                                (s) => s['id'] == songId,
                              );
                              _musicService.playCustomPlaylist(
                                widget.playlistId,
                                pIdx >= 0 ? pIdx : index,
                              );
                            }
                          },
                          onRemoved: () {
                            if (mounted) setState(() {});
                          },
                        );
                      }, childCount: displayedSongs.length),
                    ),
                  if (!isLikedSongs)
                    SliverToBoxAdapter(
                      child: DesktopPlaylistEnrichment(
                        playlistId: widget.playlistId,
                        existingSongs: songs,
                        onSongAdded: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                ] else ...[
                  // Mobile viewports (< 1024px)
                  if (displayedSongs.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(
                        isLikedSongs: isLikedSongs,
                        isSearch: _searchQuery.trim().isNotEmpty,
                        searchQuery: _searchQuery,
                      ),
                    )
                  else if (isLikedSongs)
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = displayedSongs[index];
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
                                  DesktopContextMenu.show(
                                    context: context,
                                    globalPosition: details.globalPosition,
                                    items: DesktopContextMenu.songItems(
                                      context: context,
                                      song: songMapToVideo(song),
                                    ),
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
                                          color: const Color(0xFF181818),
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
                                        final likedIdx = _musicService
                                            .likedSongs
                                            .indexWhere(
                                              (s) => s['id'] == songId,
                                            );
                                        showPlaylistSongOptionsBottomSheet(
                                          context,
                                          songMap: song,
                                          playlistId: widget.playlistId,
                                          onPlayNow: () {
                                            if (likedIdx >= 0) {
                                              _musicService.playLikedSong(
                                                _musicService
                                                    .likedSongs[likedIdx],
                                              );
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    final likedIdx = _musicService.likedSongs
                                        .indexWhere((s) => s['id'] == songId);
                                    if (likedIdx >= 0) {
                                      _musicService.playLikedSong(
                                        _musicService.likedSongs[likedIdx],
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      }, childCount: displayedSongs.length),
                    )
                  else if (_currentSort == PlaylistSortOption.customOrder &&
                      _searchQuery.trim().isEmpty)
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
                                    DesktopContextMenu.show(
                                      context: context,
                                      globalPosition: details.globalPosition,
                                      items: DesktopContextMenu.songItems(
                                        context: context,
                                        song: songMapToVideo(song),
                                        currentPlaylistId: widget.playlistId,
                                        onRemovedFromPlaylist: () =>
                                            setState(() {}),
                                      ),
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
                                            color: const Color(0xFF181818),
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
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = displayedSongs[index];
                        final songId = (song['id'] as String?) ?? '';
                        final isCurrent =
                            _musicService.currentSong?.id.value == songId;
                        final thumb = song['thumbnail'] as String? ?? '';
                        final pIdx = songs.indexWhere((s) => s['id'] == songId);

                        return Dismissible(
                          key: ValueKey('dismiss_${songId}_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                  DesktopContextMenu.show(
                                    context: context,
                                    globalPosition: details.globalPosition,
                                    items: DesktopContextMenu.songItems(
                                      context: context,
                                      song: songMapToVideo(song),
                                      currentPlaylistId: widget.playlistId,
                                      onRemovedFromPlaylist: () =>
                                          setState(() {}),
                                    ),
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
                                          color: const Color(0xFF181818),
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
                                        showPlaylistSongOptionsBottomSheet(
                                          context,
                                          songMap: song,
                                          playlistId: widget.playlistId,
                                          onPlayNow: () {
                                            _musicService.playCustomPlaylist(
                                              widget.playlistId,
                                              pIdx >= 0 ? pIdx : index,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _musicService.playCustomPlaylist(
                                      widget.playlistId,
                                      pIdx >= 0 ? pIdx : index,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      }, childCount: displayedSongs.length),
                    ),
                  if (!isLikedSongs)
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
          colors: [Color(0xFF2E2E2E), Color(0xFF181818)],
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

  Widget _buildStickyTableHeader(BuildContext context) {
    return Container(
      height: 36.0,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 40.0,
            child: Text(
              '#',
              style: TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Title',
              style: TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Album',
              style: TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 120.0,
            child: Text(
              'Date added',
              style: TextStyle(
                color: Color(0xFFA3A3A3),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 60.0,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 36.0),
                child: Icon(
                  Icons.access_time_rounded,
                  size: 16.0,
                  color: Color(0xFFA3A3A3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required bool isLikedSongs,
    required bool isSearch,
    required String searchQuery,
  }) {
    if (isSearch) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 48,
                color: Colors.white24,
              ),
              const SizedBox(height: 12),
              Text(
                'No results found for "$searchQuery"',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check for spelling errors or try a different term',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
    );
  }
}

class _DesktopTrackRowWidget extends StatefulWidget {
  final Map<String, dynamic> song;
  final String songId;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final PlaylistViewMode viewMode;
  final String playlistId;
  final bool isLikedSongs;
  final Color themeColor;
  final VoidCallback onPlay;
  final VoidCallback onRemoved;

  const _DesktopTrackRowWidget({
    super.key,
    required this.song,
    required this.songId,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.viewMode,
    required this.playlistId,
    required this.isLikedSongs,
    required this.themeColor,
    required this.onPlay,
    required this.onRemoved,
  });

  @override
  State<_DesktopTrackRowWidget> createState() => _DesktopTrackRowWidgetState();
}

class _DesktopTrackRowWidgetState extends State<_DesktopTrackRowWidget> {
  bool _isHovered = false;

  String _formatDuration(dynamic duration, dynamic durationMs) {
    if (durationMs is num && durationMs > 0) {
      final dur = Duration(milliseconds: durationMs.toInt());
      final minutes = dur.inMinutes;
      final seconds = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    if (duration is Duration) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '$minutes:$seconds';
    }
    if (duration is int && duration > 0) {
      final dur = duration > 10000
          ? Duration(milliseconds: duration)
          : Duration(seconds: duration);
      final minutes = dur.inMinutes;
      final seconds = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    if (duration is String && duration.isNotEmpty) {
      if (duration.contains(':')) return duration;
      final parsed = int.tryParse(duration);
      if (parsed != null && parsed > 0) {
        final dur = parsed > 10000
            ? Duration(milliseconds: parsed)
            : Duration(seconds: parsed);
        final minutes = dur.inMinutes;
        final seconds = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
        return '$minutes:$seconds';
      }
    }
    return '';
  }

  String _formatDateAdded(dynamic addedAt) {
    if (addedAt == null) return 'Recently';
    if (addedAt is DateTime) {
      return '${addedAt.year}-${addedAt.month.toString().padLeft(2, '0')}-${addedAt.day.toString().padLeft(2, '0')}';
    }
    final s = addedAt.toString();
    if (s.length >= 10) return s.substring(0, 10);
    return s.isNotEmpty ? s : 'Recently';
  }

  void _showContextMenu(BuildContext context, Offset position) {
    DesktopContextMenu.show(
      context: context,
      globalPosition: position,
      items: DesktopContextMenu.songItems(
        context: context,
        song: songMapToVideo(widget.song),
        currentPlaylistId: widget.isLikedSongs ? null : widget.playlistId,
        onRemovedFromPlaylist: widget.onRemoved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.song['title'] as String?) ?? 'Unknown Title';
    final artist = (widget.song['author'] as String?) ?? 'Unknown Artist';
    final album = (widget.song['album'] as String?) ?? '';
    final thumb = (widget.song['thumbnail'] as String?) ?? '';
    final durationStr = _formatDuration(
      widget.song['duration'],
      widget.song['durationMs'],
    );
    final dateAddedStr = _formatDateAdded(
      widget.song['addedAt'] ?? widget.song['dateAdded'],
    );

    final isCompact = widget.viewMode == PlaylistViewMode.compact;
    final rowHeight = isCompact ? 38.0 : 56.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(4.0),
          onTap: widget.onPlay,
          child: Container(
            height: rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            decoration: BoxDecoration(
              color: widget.isCurrent
                  ? widget.themeColor.withValues(alpha: 0.14)
                  : (_isHovered
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Row(
              children: [
                // # or Play Icon or Animated Equalizer (width: 40)
                SizedBox(
                  width: 40.0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _isHovered
                        ? InkWell(
                            onTap: widget.onPlay,
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          )
                        : (widget.isPlaying
                              ? AnimatedEqualizer(
                                  isPlaying: true,
                                  color: widget.themeColor,
                                  size: 14,
                                )
                              : Text(
                                  '${widget.index}',
                                  style: TextStyle(
                                    color: widget.isCurrent
                                        ? widget.themeColor
                                        : Colors.white.withValues(alpha: 0.54),
                                    fontSize: 13.0,
                                    fontWeight: widget.isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                )),
                  ),
                ),

                // Title (+ Artist and Thumbnail) (flex: 3)
                Expanded(
                  flex: 3,
                  child: isCompact
                      // Compact: Single-line Title • Artist
                      ? Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.isCurrent
                                      ? widget.themeColor
                                      : Colors.white,
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (artist.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                ),
                                child: Text(
                                  '•',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.30),
                                    fontSize: 12.0,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFB3B3B3),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )
                      // List: 40x40 thumbnail + 2 lines (Title, Artist)
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4.0),
                              child: Container(
                                width: 40.0,
                                height: 40.0,
                                color: const Color(0xFF1E1E1E),
                                child: thumb.isNotEmpty
                                    ? Image.network(
                                        thumb,
                                        width: 40.0,
                                        height: 40.0,
                                        cacheWidth: 100,
                                        cacheHeight: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.music_note_rounded,
                                                  color: Colors.white30,
                                                  size: 20,
                                                ),
                                      )
                                    : const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white30,
                                        size: 20,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: widget.isCurrent
                                          ? widget.themeColor
                                          : Colors.white,
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3.0),
                                  Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFB3B3B3),
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),

                // Album (flex: 2)
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Text(
                      album.isNotEmpty ? album : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB3B3B3),
                        fontSize: 13.0,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),

                // Date Added (width: 120)
                SizedBox(
                  width: 120.0,
                  child: Text(
                    dateAddedStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB3B3B3),
                      fontSize: 13.0,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // Duration + More Options Button (width: 60)
                SizedBox(
                  width: 60.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        durationStr,
                        style: const TextStyle(
                          color: Color(0xFFB3B3B3),
                          fontSize: 13.0,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Builder(
                        builder: (btnCtx) => IconButton(
                          key: ValueKey(
                            widget.isLikedSongs
                                ? 'liked_song_more_${widget.songId}'
                                : 'playlist_song_more_${widget.songId}',
                          ),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 18.0,
                            color: _isHovered || widget.isCurrent
                                ? Colors.white70
                                : Colors.transparent,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28.0,
                            minHeight: 28.0,
                          ),
                          tooltip: 'More options',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final renderBox =
                                btnCtx.findRenderObject() as RenderBox?;
                            final offset =
                                renderBox?.localToGlobal(Offset.zero) ??
                                Offset.zero;
                            final size = renderBox?.size ?? Size.zero;
                            _showContextMenu(
                              context,
                              Offset(offset.dx, offset.dy + size.height + 2),
                            );
                          },
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
    );
  }
}
