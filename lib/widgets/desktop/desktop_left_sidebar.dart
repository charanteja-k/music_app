import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/dynamic_artist_service.dart';
import '../playlist_action_menu.dart';
import '../dilse_tooltip.dart';
import '../shimmer_loading.dart';
import 'desktop_context_menu.dart';
import 'desktop_import_modal.dart';

/// Spotify-grade dual-mode Left Sidebar (#Desktop_LeftSidebar_Id).
///
/// Features:
/// - Compact Mode (Width <= 96px): Tooltip-backed icon navigation & 48x48 squircle tiles.
/// - Expanded Mode (Width > 96px): Primary Navigation Card + "Your Library" deck with
///   filter chips (`Playlists`, `Albums`, `Imported from Spotify`, `History`),
///   in-library instant search, sort indicator, and virtualized list rows.
class DesktopLeftSidebar extends StatefulWidget {
  final double width;

  const DesktopLeftSidebar({super.key, required this.width});

  /// Resolves the authentic playlist artwork URL from direct properties
  /// (`artworkUrl`, `thumbnail`, `thumbnailUrl`, `imageUrl`, `coverUrl`) or from
  /// the playlist's first track/song entry.
  static String resolveArtworkUrl(Map<String, dynamic> pl) {
    final direct =
        (pl['artworkUrl'] ??
                pl['thumbnail'] ??
                pl['thumbnailUrl'] ??
                pl['imageUrl'] ??
                pl['coverUrl'] ??
                '')
            .toString();
    if (direct.isNotEmpty) return direct;

    final songs = (pl['songs'] as List?) ?? (pl['tracks'] as List?);
    if (songs != null && songs.isNotEmpty) {
      final first = songs.first;
      if (first is Map) {
        final thumb =
            (first['thumbnail'] ??
                    first['thumbnailUrl'] ??
                    first['artworkUrl'] ??
                    first['imageUrl'] ??
                    '')
                .toString();
        if (thumb.isNotEmpty) return thumb;
        final songId = first['id']?.toString() ?? '';
        if (songId.isNotEmpty) {
          final hd = MusicService.getHdThumbnail(songId);
          if (hd.isNotEmpty) return hd;
        }
      } else if (first is Video) {
        final thumb = MusicService.getHdThumbnail(first.id.value);
        if (thumb.isNotEmpty) return thumb;
        return first.thumbnails.lowResUrl;
      }
    }
    return '';
  }

  @override
  State<DesktopLeftSidebar> createState() => _DesktopLeftSidebarState();
}

class _DesktopLeftSidebarState extends State<DesktopLeftSidebar> {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();
  final ValueNotifier<Set<String>> _selectedFilters =
      ValueNotifier<Set<String>>({});
  final ValueNotifier<bool> _isSearchActive = ValueNotifier<bool>(false);
  final TextEditingController _searchController = TextEditingController();
  String? _hoveredRowId;

  @override
  void dispose() {
    _selectedFilters.dispose();
    _isSearchActive.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create New Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final newId = _musicService.createPlaylist(name);
                Navigator.pop(ctx);
                if (newId.isNotEmpty && mounted) {
                  DesktopLayoutState.openPlaylist(newId);
                }
              }
            },
            child: const Text(
              'Create',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.width <= 96.0;

    if (isCompact) {
      return _buildCompactSidebar(context);
    }

    return _buildExpandedSidebar(context);
  }

  // ===========================================================================
  // 1. COMPACT MODE (Width <= 96px)
  // ===========================================================================
  Widget _buildCompactSidebar(BuildContext context) {
    final prefs = PreferencesService();

    return AnimatedBuilder(
      animation: Listenable.merge([
        _musicService,
        prefs,
        DesktopLayoutState.activeNavTab,
        DesktopLayoutState.activePlaylistId,
      ]),
      builder: (context, _) {
        final activeTab = DesktopLayoutState.activeNavTab.value;
        final activePlaylistId = DesktopLayoutState.activePlaylistId.value;

        return Container(
          margin: const EdgeInsets.fromLTRB(8.0, 8.0, 0.0, 8.0),
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
          ),
          child: Column(
            children: [
              // 1. Primary Navigation Icons (Home & Search)
              _buildCompactNavIcon(
                icon: Icons.home_filled,
                label: 'Home',
                isActive: activeTab == DesktopNavTab.home,
                onTap: () => DesktopLayoutState.setNavTab(DesktopNavTab.home),
              ),
              _buildCompactNavIcon(
                icon: Icons.search_rounded,
                label: 'Search',
                isActive: activeTab == DesktopNavTab.search,
                onTap: () => DesktopLayoutState.setNavTab(DesktopNavTab.search),
              ),

              const SizedBox(height: 6.0),
              const Divider(
                color: Color(0xFF1E1E1E),
                height: 1.0,
                indent: 6.0,
                endIndent: 6.0,
              ),
              const SizedBox(height: 6.0),

              // 2. Authoritative Library Expand Trigger
              _buildCompactNavIcon(
                icon: Icons.view_sidebar_rounded,
                label: 'Expand sidebar',
                onTap: () => DesktopLayoutState.toggleLeftSidebar(),
              ),

              // 3. Create / Import Playlist Action
              _buildCompactNavIcon(
                icon: Icons.add_rounded,
                label: 'Create or Import Playlist',
                onTap: _showPlaylistAddOrImportMenu,
              ),

              const SizedBox(height: 6.0),

              // 4. "Liked Songs" Permanent 48x48 High-Fidelity Album Tile
              _CompactLikedSongsTile(
                songCount: _musicService.likedSongs.length,
                isSelected:
                    activeTab == DesktopNavTab.customPlaylist &&
                    activePlaylistId == 'liked_songs',
                onTap: () {
                  DesktopLayoutState.openPlaylist('liked_songs');
                },
                onSecondaryTapDown: (details) {
                  showUnifiedPlaylistMenu(
                    context: context,
                    globalPosition: details.globalPosition,
                    playlist: 'liked_songs',
                    isSidebar: true,
                  );
                },
              ),

              const SizedBox(height: 4.0),

              // 5. Custom & Imported Playlists (48x48 Squircle Artwork Tiles)
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _musicService,
                    DesktopLayoutState.isHomeFeedComplete,
                    prefs,
                  ]),
                  builder: (context, _) {
                    if (!DesktopLayoutState.isHomeFeedComplete.value) {
                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: 4,
                        itemBuilder: (context, index) =>
                            const ShimmerSidebarRow(isCompact: true),
                      );
                    }
                    final playlists = _getFilteredPlaylists();
                    final pinnedIds = prefs.pinnedPlaylistIds.toSet();
                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final pl = playlists[index];
                        final id = pl['id']?.toString() ?? '';
                        final isPinned = pinnedIds.contains(id);
                        final isSelected =
                            activeTab == DesktopNavTab.customPlaylist &&
                            activePlaylistId == id;

                        return _CompactPlaylistTile(
                          playlist: pl,
                          isSelected: isSelected,
                          isPinned: isPinned,
                          onTap: () {
                            if (id.isNotEmpty) {
                              DesktopLayoutState.openPlaylist(id);
                            }
                          },
                          onSecondaryTapDown: (details) {
                            if (id.isNotEmpty) {
                              showUnifiedPlaylistMenu(
                                context: context,
                                globalPosition: details.globalPosition,
                                playlist: pl,
                                isSidebar: true,
                                onCreatePlaylist: _showCreatePlaylistDialog,
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactNavIcon({
    required IconData icon,
    required String label,
    Color? color,
    bool isActive = false,
    bool isFlipped = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Center(
        child: DilSeTooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(8.0),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              splashColor: Colors.white.withValues(alpha: 0.12),
              onTap: onTap,
              child: SizedBox(
                width: 40.0,
                height: 40.0,
                child: Center(
                  child: isFlipped
                      ? Transform.flip(
                          flipX: true,
                          child: Icon(
                            icon,
                            color: isActive
                                ? Colors.white
                                : (color ?? const Color(0xFFB3B3B3)),
                            size: 24.0,
                          ),
                        )
                      : Icon(
                          icon,
                          color: isActive
                              ? Colors.white
                              : (color ?? const Color(0xFFB3B3B3)),
                          size: 24.0,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. EXPANDED MODE (Width > 96px, 280px–398px)
  // ===========================================================================
  Widget _buildExpandedSidebar(BuildContext context) {
    return Column(
      children: [
        // CARD 1: PRIMARY NAVIGATION (Home / Search)
        Container(
          margin: const EdgeInsets.fromLTRB(8.0, 8.0, 0.0, 0.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
          ),
          child: ValueListenableBuilder<DesktopNavTab>(
            valueListenable: DesktopLayoutState.activeNavTab,
            builder: (context, activeTab, _) {
              return Column(
                children: [
                  _buildNavRow(
                    icon: Icons.home_filled,
                    title: 'Home',
                    isActive: activeTab == DesktopNavTab.home,
                    onTap: () =>
                        DesktopLayoutState.setNavTab(DesktopNavTab.home),
                  ),
                  const SizedBox(height: 6.0),
                  _buildNavRow(
                    icon: Icons.search_rounded,
                    title: 'Search',
                    isActive: activeTab == DesktopNavTab.search,
                    onTap: () =>
                        DesktopLayoutState.setNavTab(DesktopNavTab.search),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 8.0),

        // CARD 2: YOUR LIBRARY DECK (Expanded)
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8.0, 0.0, 0.0, 8.0),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Library Header: Title, Collapse button, and Add action
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 10.0, 8.0, 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Collapse sidebar',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.view_sidebar_rounded,
                                color: Colors.white70,
                                size: 20.0,
                              ),
                              onPressed: () =>
                                  DesktopLayoutState.toggleLeftSidebar(),
                            ),
                            const SizedBox(width: 6.0),
                            Flexible(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () =>
                                      DesktopLayoutState.toggleLeftSidebar(),
                                  child: const Text(
                                    'Your Library',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Button 1: Dedicated Spotify / Exportify Import Button
                          _SidebarHeaderActionButton(
                            tooltip: 'Import from Spotify / Exportify',
                            onPressed: () => showDesktopImportModal(context),
                            builder: (isHovered) => CustomPaint(
                              size: const Size(16, 16),
                              painter: _SpotifyIconPainter(
                                color: isHovered
                                    ? const Color(0xFF1DB954)
                                    : const Color(0xFFB3B3B3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Button 2: Dedicated Add Playlist Button (+)
                          _SidebarHeaderActionButton(
                            tooltip: 'Create Playlist',
                            onPressed: _showCreatePlaylistDialog,
                            builder: (isHovered) => Icon(
                              Icons.add_rounded,
                              size: 20,
                              color: isHovered
                                  ? Colors.white
                                  : const Color(0xFFB3B3B3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Horizontal Filter Chips Strip with Multi-Select and (X) Reset Button
                SizedBox(
                  height: 34.0,
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: _selectedFilters,
                    builder: (context, activeFilters, _) {
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 14.0),
                        children: [
                          if (activeFilters.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: DilSeTooltip(
                                message: 'Clear filters',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16.0),
                                  onTap: () {
                                    _selectedFilters.value = {};
                                  },
                                  child: Container(
                                    width: 32.0,
                                    height: 32.0,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 16.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          _buildFilterChip('Playlists', activeFilters),
                          _buildFilterChip('Albums', activeFilters),
                          _buildFilterChip(
                            'Imported from Spotify',
                            activeFilters,
                          ),
                          _buildFilterChip('History', activeFilters),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8.0),

                // In-Library Search & Sort Toolbar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      // Expandable search field
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isSearchActive,
                          builder: (context, isSearchActive, _) {
                            if (!isSearchActive) {
                              return Row(
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Search in Your Library',
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      color: Colors.white60,
                                      size: 18.0,
                                    ),
                                    onPressed: () {
                                      _isSearchActive.value = true;
                                    },
                                  ),
                                ],
                              );
                            }

                            return Container(
                              height: 32.0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.search_rounded,
                                    color: Colors.white54,
                                    size: 16.0,
                                  ),
                                  const SizedBox(width: 6.0),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      autofocus: true,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.0,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: 'Search Library...',
                                        hintStyle: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12.0,
                                        ),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _searchController.clear();
                                      _isSearchActive.value = false;
                                      setState(() {});
                                    },
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white54,
                                      size: 16.0,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Trailing Sort Indicator ("Recents")
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Recents',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12.0,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          Icon(
                            Icons.sort_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 16.0,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6.0),

                // Virtualized Entity List (Liked Songs, Custom Playlists, Spotify Imports, History)
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _musicService,
                      _prefs,
                      _selectedFilters,
                      DesktopLayoutState.activeNavTab,
                      DesktopLayoutState.activePlaylistId,
                      DesktopLayoutState.activeArtistName,
                      DesktopLayoutState.isHomeFeedComplete,
                    ]),
                    builder: (context, _) {
                      if (!DesktopLayoutState.isHomeFeedComplete.value) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          itemCount: 6,
                          itemBuilder: (context, index) =>
                              const ShimmerSidebarRow(),
                        );
                      }

                      final filters = _selectedFilters.value;
                      final query = _searchController.text.trim().toLowerCase();

                      if (filters.contains('Artists')) {
                        final followed = _prefs.followedArtists.where((name) {
                          if (query.isEmpty) return true;
                          return name.toLowerCase().contains(query);
                        }).toList();

                        if (followed.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 24.0,
                              ),
                              child: Text(
                                query.isEmpty
                                    ? 'No followed artists yet'
                                    : 'No artists match ""',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          itemCount: followed.length,
                          itemBuilder: (context, index) {
                            final artistName = followed[index];
                            return _buildArtistRow(context, artistName);
                          },
                        );
                      }
                      final playlists = _getFilteredPlaylists();
                      final showLiked = _shouldShowLikedSongs();
                      final isImportedFilter = filters.contains(
                        'Imported from Spotify',
                      );

                      if (isImportedFilter && playlists.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 24.0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF1DB954,
                                    ).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.file_download_outlined,
                                    color: Color(0xFF1DB954),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No imported playlists yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Transfer Exportify CSV files or Spotify playlists into DilSe.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.file_download_outlined,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Import from Exportify / Spotify',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () =>
                                      showDesktopImportModal(context),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final showImportHeader =
                          isImportedFilter && playlists.isNotEmpty;
                      final extraCount =
                          (showLiked ? 1 : 0) + (showImportHeader ? 1 : 0);

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        itemCount: extraCount + playlists.length,
                        itemBuilder: (context, index) {
                          var effectiveIndex = index;
                          if (showImportHeader) {
                            if (effectiveIndex == 0) {
                              return _buildImportNewHeader(context);
                            }
                            effectiveIndex--;
                          }

                          // Row 0: Liked Songs Row
                          if (showLiked && effectiveIndex == 0) {
                            return _buildLikedSongsRow(context);
                          }

                          final plIndex = showLiked
                              ? effectiveIndex - 1
                              : effectiveIndex;
                          final pl = playlists[plIndex];
                          return _buildPlaylistRow(context, pl);
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
    );
  }

  Widget _buildNavRow({
    required IconData icon,
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8.0),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
              size: 22.0,
            ),
            const SizedBox(width: 14.0),
            Text(
              title,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: 14.0,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, Set<String> activeFilters) {
    final isSelected = activeFilters.contains(label);

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () {
          final next = Set<String>.from(_selectedFilters.value);
          if (isSelected) {
            next.remove(label);
          } else {
            next.add(label);
          }
          _selectedFilters.value = next;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF282836)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.75),
              fontSize: 12.0,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldShowLikedSongs() {
    final filters = _selectedFilters.value;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty && !'liked songs'.contains(query)) {
      return false;
    }
    if (filters.isEmpty) return true;
    if (filters.contains('Playlists')) return true;
    if (filters.contains('Albums') ||
        filters.contains('History') ||
        filters.contains('Artists') ||
        filters.contains('Imported from Spotify')) {
      return false;
    }
    return true;
  }

  Widget _buildImportNewHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4.0, 2.0, 4.0, 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: () => showDesktopImportModal(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: const Color(0xFF1DB954).withValues(alpha: 0.25),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.file_download_outlined,
                color: Color(0xFF1DB954),
                size: 16.0,
              ),
              SizedBox(width: 8.0),
              Text(
                'Import New (Spotify / Exportify)',
                style: TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaylistAddOrImportMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final targetPosition = renderBox.localToGlobal(const Offset(64, 120));
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF18181F),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF282836)),
      ),
      position: RelativeRect.fromRect(
        targetPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 280.0, maxWidth: 320.0),
      items: const [
        PopupMenuItem(
          value: 'create',
          height: 42,
          child: Row(
            children: [
              Icon(Icons.playlist_add_rounded, color: Colors.white, size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Create New Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import',
          height: 42,
          child: Row(
            children: [
              Icon(
                Icons.file_download_outlined,
                color: Color(0xFF1DB954),
                size: 19,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Import Playlist (Spotify / Exportify)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (selected == 'create') {
      _showCreatePlaylistDialog();
    } else if (selected == 'import') {
      showDesktopImportModal(context);
    }
  }

  List<Map<String, dynamic>> _getFilteredPlaylists() {
    final customPlaylists = _musicService.customPlaylists;
    final allPlaylists = customPlaylists;
    final filters = _selectedFilters.value;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = allPlaylists.where((pl) {
      final name = pl['name']?.toString().toLowerCase() ?? '';
      final isSpotify =
          pl['isSpotify'] == true ||
          (pl['source']?.toString().contains('spotify') ?? false);
      final isAlbum = pl['type'] == 'album';

      if (query.isNotEmpty && !name.contains(query)) {
        return false;
      }

      if (filters.isEmpty) return true;

      bool matches = false;
      if (filters.contains('Playlists') && !isAlbum) {
        matches = true;
      }
      if (filters.contains('Imported from Spotify') && isSpotify) {
        matches = true;
      }
      if (filters.contains('Albums') && isAlbum) {
        matches = true;
      }
      if (filters.contains('History')) {
        if (pl['type'] == 'history') matches = true;
      }
      return matches;
    }).toList();

    // Sort: pinned playlists first immediately following Liked Songs
    final pinnedIds = _prefs.pinnedPlaylistIds.toSet();
    filtered.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aPinned = pinnedIds.contains(aId);
      final bPinned = pinnedIds.contains(bId);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });

    return filtered;
  }

  Widget _buildLikedSongsRow(BuildContext context) {
    final count = _musicService.likedSongs.length;
    final isHovered = _hoveredRowId == 'liked_songs';
    final isSelected =
        DesktopLayoutState.activeNavTab.value == DesktopNavTab.customPlaylist &&
        DesktopLayoutState.activePlaylistId.value == 'liked_songs';

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRowId = 'liked_songs'),
      onExit: (_) => setState(() => _hoveredRowId = null),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          showUnifiedPlaylistMenu(
            context: context,
            globalPosition: details.globalPosition,
            playlist: 'liked_songs',
            isSidebar: true,
          );
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            DesktopLayoutState.openPlaylist('liked_songs');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.10)
                  : isHovered
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              children: [
                // 48x48 Solid Liked Songs Squircle
                Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5038A0),
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 24.0,
                  ),
                ),
                const SizedBox(width: 12.0),

                // Title and Subtitle with Pin
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liked Songs',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF1DB954)
                              : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Row(
                        children: [
                          const Icon(
                            Icons.push_pin_rounded,
                            color: Color(0xFF1DB954),
                            size: 13.0,
                          ),
                          const SizedBox(width: 4.0),
                          Expanded(
                            child: Text(
                              'Playlist • $count ${count == 1 ? "song" : "songs"}',
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(
                                        0xFF1DB954,
                                      ).withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.6),
                                fontSize: 12.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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

  Widget _buildPlaylistFallback(bool isSpotify, String name) {
    return Container(
      color: const Color(0xFF282836),
      alignment: Alignment.center,
      child: isSpotify
          ? const Icon(
              Icons.stream_rounded,
              color: Color(0xFF1DB954),
              size: 22.0,
            )
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'P',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 17.0,
              ),
            ),
    );
  }

  Widget _buildPlaylistRow(BuildContext context, Map<String, dynamic> pl) {
    final id = pl['id']?.toString() ?? '';
    final name = pl['name']?.toString() ?? 'Untitled Playlist';
    final isSpotify = pl['isSpotify'] == true;
    final thumb = DesktopLeftSidebar.resolveArtworkUrl(pl);
    final trackCount =
        pl['trackCount'] as int? ??
        (pl['tracks'] as List?)?.length ??
        (pl['songs'] as List?)?.length ??
        0;
    final isHovered = _hoveredRowId == id;
    final isSelected =
        DesktopLayoutState.activeNavTab.value == DesktopNavTab.customPlaylist &&
        DesktopLayoutState.activePlaylistId.value == id;
    final isPinned = _prefs.isPlaylistPinned(id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRowId = id),
      onExit: (_) => setState(() => _hoveredRowId = null),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          if (id.isNotEmpty) {
            showUnifiedPlaylistMenu(
              context: context,
              globalPosition: details.globalPosition,
              playlist: pl,
              isSidebar: true,
              onCreatePlaylist: _showCreatePlaylistDialog,
            );
          }
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            if (id.isNotEmpty) {
              DesktopLayoutState.openPlaylist(id);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.10)
                  : isHovered
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              children: [
                // 48x48 Squircle Album / Playlist Tile
                Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF282836),
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6.0),
                    child: thumb.isNotEmpty
                        ? Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            cacheHeight: 96,
                            errorBuilder: (_, _, _) =>
                                _buildPlaylistFallback(isSpotify, name),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: const Color(0xFF282836),
                                child: const Center(
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: 20.0,
                                    color: Color(0xFF737373),
                                  ),
                                ),
                              );
                            },
                          )
                        : _buildPlaylistFallback(isSpotify, name),
                  ),
                ),
                const SizedBox(width: 12.0),

                // Title and Details Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF1DB954)
                              : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Row(
                        children: [
                          if (isPinned) ...[
                            const Icon(
                              Icons.push_pin_rounded,
                              color: Color(0xFF1DB954),
                              size: 13.0,
                            ),
                            const SizedBox(width: 4.0),
                          ],
                          Expanded(
                            child: Text(
                              isSpotify
                                  ? 'Playlist • Spotify Import'
                                  : 'Playlist • $trackCount ${trackCount == 1 ? "song" : "songs"}',
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(
                                        0xFF1DB954,
                                      ).withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.6),
                                fontSize: 12.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Hover Actions: 3-Dot More Menu
                if (isHovered && id.isNotEmpty)
                  PlaylistActionMenu(
                    playlistId: id,
                    playlistName: name,
                    isSpotifyImport: isSpotify,
                    iconSize: 18.0,
                    iconColor: Colors.white70,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtistRow(BuildContext context, String artistName) {
    final artistItem = DynamicArtistService().findArtist(artistName);
    final displayName = artistItem?.name ?? artistName;
    final isHovered = _hoveredRowId == 'artist_';
    final isSelected =
        DesktopLayoutState.activeNavTab.value == DesktopNavTab.artistProfile &&
        DesktopLayoutState.activeArtistName.value == displayName;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRowId = 'artist_'),
      onExit: (_) => setState(() => _hoveredRowId = null),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: () {
          DesktopLayoutState.openArtist(displayName);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.10)
                : isHovered
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Row(
            children: [
              // 48x48 Circular Artist Avatar
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF282836),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
                child: ClipOval(
                  child: artistItem != null && artistItem.imageUrl.isNotEmpty
                      ? Image.network(
                          artistItem.imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                          cacheHeight: 120,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'A',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 17.0,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.0,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12.0),

              // Title and Subtitle with Verified Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF1DB954)
                                  : Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4.0),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14.0,
                          color: Color(0xFF1DB954),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      artistItem?.genre.isNotEmpty == true
                          ? artistItem!.genre
                          : 'Artist',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotify-grade 48x48 Liked Songs permanent high-fidelity album tile.
class _CompactLikedSongsTile extends StatefulWidget {
  final int songCount;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTapDown;

  const _CompactLikedSongsTile({
    required this.songCount,
    required this.isSelected,
    required this.onTap,
    required this.onSecondaryTapDown,
  });

  @override
  State<_CompactLikedSongsTile> createState() => _CompactLikedSongsTileState();
}

class _CompactLikedSongsTileState extends State<_CompactLikedSongsTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tooltipText =
        'Liked Songs • ${widget.songCount} ${widget.songCount == 1 ? "song" : "songs"}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Center(
        child: DilSeTooltip(
          message: tooltipText,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              onSecondaryTapDown: widget.onSecondaryTapDown,
              child: AnimatedScale(
                scale: _isHovered ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5038A0),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.08),
                      width: widget.isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.favorite,
                      size: 22.0,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spotify-grade 48x48 custom/imported playlist artwork squircle tile.
class _CompactPlaylistTile extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final bool isSelected;
  final bool isPinned;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTapDown;

  const _CompactPlaylistTile({
    required this.playlist,
    required this.isSelected,
    required this.isPinned,
    required this.onTap,
    required this.onSecondaryTapDown,
  });

  @override
  State<_CompactPlaylistTile> createState() => _CompactPlaylistTileState();
}

class _CompactPlaylistTileState extends State<_CompactPlaylistTile> {
  bool _isHovered = false;

  String _resolveArtworkUrl() {
    return DesktopLeftSidebar.resolveArtworkUrl(widget.playlist);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.playlist['name']?.toString() ?? 'Playlist';
    final artworkUrl = _resolveArtworkUrl();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Center(
        child: DilSeTooltip(
          message: widget.isPinned ? '$name • Playlist 📌' : '$name • Playlist',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              onSecondaryTapDown: widget.onSecondaryTapDown,
              child: AnimatedScale(
                scale: _isHovered ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 48.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.08),
                      width: widget.isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (artworkUrl.isNotEmpty)
                          Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            cacheHeight: 96,
                            errorBuilder: (_, _, _) => _buildFallback(),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: const Color(0xFF1E1E24),
                                child: const Center(
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: 22.0,
                                    color: Color(0xFF737373),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          _buildFallback(),
                        if (widget.isPinned)
                          const Positioned(
                            top: 2,
                            right: 2,
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 10,
                              color: Color(0xFF1DB954),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final isSpotify = widget.playlist['isSpotify'] == true;
    final name = widget.playlist['name']?.toString() ?? 'P';
    return Container(
      color: const Color(0xFF1E1E24),
      alignment: Alignment.center,
      child: isSpotify
          ? const Icon(
              Icons.stream_rounded,
              color: Color(0xFF1DB954),
              size: 22.0,
            )
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'P',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 17.0,
              ),
            ),
    );
  }
}

/// Spotify brand icon vector painter (3 authentic arcs).
class _SpotifyIconPainter extends CustomPainter {
  final Color color;
  const _SpotifyIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Top arc
    paint.strokeWidth = w * 0.14;
    final topPath = Path();
    topPath.moveTo(w * 0.16, h * 0.36);
    topPath.quadraticBezierTo(w * 0.50, h * 0.16, w * 0.84, h * 0.38);
    canvas.drawPath(topPath, paint);

    // Middle arc
    paint.strokeWidth = w * 0.125;
    final midPath = Path();
    midPath.moveTo(w * 0.22, h * 0.56);
    midPath.quadraticBezierTo(w * 0.50, h * 0.40, w * 0.78, h * 0.58);
    canvas.drawPath(midPath, paint);

    // Bottom arc
    paint.strokeWidth = w * 0.11;
    final botPath = Path();
    botPath.moveTo(w * 0.28, h * 0.76);
    botPath.quadraticBezierTo(w * 0.50, h * 0.63, w * 0.72, h * 0.77);
    canvas.drawPath(botPath, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotifyIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 32x32 Sidebar Header Action Button with soft circular hover highlights.
class _SidebarHeaderActionButton extends StatefulWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget Function(bool isHovered) builder;

  const _SidebarHeaderActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.builder,
  });

  @override
  State<_SidebarHeaderActionButton> createState() =>
      _SidebarHeaderActionButtonState();
}

class _SidebarHeaderActionButtonState
    extends State<_SidebarHeaderActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DilSeTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: widget.builder(_isHovered),
          ),
        ),
      ),
    );
  }
}
