import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../song_options_bottom_sheet.dart';

/// Spotify-grade "Recent Searches" elevated dropdown popup.
///
/// Anchors directly below the desktop top navigation search pill with a 6px vertical offset.
/// Displays recent search entities with 40x40 squircle thumbnails, titles, metadata subtitles,
/// hover highlights, and remove buttons. Routes selections in-place without page reloads.
class DesktopSearchDropdown extends StatelessWidget {
  final LayerLink layerLink;
  final ValueListenable<double> searchWidthListenable;
  final VoidCallback onDismiss;
  final ValueChanged<bool>? onHoverChanged;

  const DesktopSearchDropdown({
    super.key,
    required this.layerLink,
    required this.searchWidthListenable,
    required this.onDismiss,
    this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService();

    return ValueListenableBuilder<double>(
      valueListenable: searchWidthListenable,
      builder: (context, searchWidth, _) {
        final dropdownWidth = searchWidth >= 360.0
            ? searchWidth.clamp(360.0, 420.0)
            : (searchWidth < 280.0 ? 280.0 : searchWidth);

        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 6.0),
            child: TapRegion(
              groupId: 'desktop_search_bar',
              child: MouseRegion(
                onEnter: (_) => onHoverChanged?.call(true),
                onExit: (_) => onHoverChanged?.call(false),
                child: Container(
                  width: dropdownWidth,
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181F),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 20.0,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedBuilder(
                      animation: prefs,
                      builder: (context, _) {
                        final recentSearches = prefs.getRecentSearches();

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                14.0,
                                16.0,
                                8.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent searches',
                                    style: TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  if (recentSearches.isNotEmpty)
                                    _ClearAllButton(
                                      onTap: () async {
                                        await prefs.clearRecentSearches();
                                      },
                                    ),
                                ],
                              ),
                            ),

                            // List container or empty state
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 380.0,
                              ),
                              child: recentSearches.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24.0,
                                        horizontal: 16.0,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No recent searches',
                                          style: TextStyle(
                                            color: Color(0xFF737373),
                                            fontSize: 13.0,
                                          ),
                                        ),
                                      ),
                                    )
                                  : RawScrollbar(
                                      thumbColor: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      radius: const Radius.circular(4.0),
                                      thickness: 4.0,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        itemCount: recentSearches.length,
                                        itemBuilder: (context, index) {
                                          final item = recentSearches[index];
                                          return _RecentSearchItemRow(
                                            item: item,
                                            onTap: () {
                                              _handleItemSelection(item);
                                            },
                                            onRemove: () async {
                                              final id =
                                                  (item['id'] as String?) ??
                                                  (item['title'] as String?) ??
                                                  '';
                                              final title =
                                                  (item['title'] as String?) ??
                                                  '';
                                              await prefs.removeRecentSearch(
                                                id,
                                              );
                                              if (title.isNotEmpty) {
                                                await prefs
                                                    .removeFromSearchHistory(
                                                      title,
                                                    );
                                              }
                                            },
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleItemSelection(Map<String, dynamic> item) {
    final type = (item['type'] as String?)?.toLowerCase().trim() ?? 'query';
    final id = (item['id'] as String?) ?? (item['title'] as String?) ?? '';
    final title =
        (item['title'] as String?) ?? (item['query'] as String?) ?? '';
    final subtitle = (item['subtitle'] as String?) ?? '';
    final imageUrl =
        (item['imageUrl'] as String?) ??
        (item['thumbnailUrl'] as String?) ??
        '';

    // Bump to top of recent searches
    PreferencesService().addRecentSearch(item);

    switch (type) {
      case 'song':
      case 'track':
        MusicService().playSong(songMapToVideo(item));
        break;
      case 'playlist':
        DesktopLayoutState.openPlaylist(id);
        break;
      case 'album':
        DesktopLayoutState.openAlbum(
          albumId: id,
          albumTitle: title,
          albumArtwork: imageUrl,
          albumArtist: subtitle,
        );
        break;
      case 'artist':
        DesktopLayoutState.openArtist(title);
        break;
      case 'query':
      default:
        DesktopLayoutState.globalSearchQuery.value = title;
        DesktopLayoutState.setNavTab(DesktopNavTab.search);
        break;
    }

    onDismiss();
  }
}

class _ClearAllButton extends StatefulWidget {
  final VoidCallback onTap;

  const _ClearAllButton({required this.onTap});

  @override
  State<_ClearAllButton> createState() => _ClearAllButtonState();
}

class _ClearAllButtonState extends State<_ClearAllButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          'Clear all',
          style: TextStyle(
            color: _isHovered ? Colors.white : const Color(0xFFA3A3A3),
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _RecentSearchItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentSearchItemRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_RecentSearchItemRow> createState() => _RecentSearchItemRowState();
}

class _RecentSearchItemRowState extends State<_RecentSearchItemRow> {
  bool _isHovered = false;

  String _formatType(String type) {
    switch (type.toLowerCase()) {
      case 'song':
      case 'track':
        return 'Song';
      case 'playlist':
        return 'Playlist';
      case 'album':
        return 'Album';
      case 'artist':
        return 'Artist';
      case 'category':
        return 'Category';
      case 'query':
      default:
        return 'Search';
    }
  }

  Widget _buildFallbackIcon(String type) {
    IconData icon;
    switch (type.toLowerCase()) {
      case 'artist':
        icon = Icons.person_rounded;
        break;
      case 'playlist':
        icon = Icons.queue_music_rounded;
        break;
      case 'album':
        icon = Icons.album_rounded;
        break;
      case 'song':
      case 'track':
        icon = Icons.music_note_rounded;
        break;
      case 'category':
        icon = Icons.grid_view_rounded;
        break;
      case 'query':
      default:
        icon = Icons.history_rounded;
        break;
    }
    return Center(child: Icon(icon, color: Colors.white70, size: 20.0));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title =
        (item['title'] as String?) ?? (item['query'] as String?) ?? '';
    final type = (item['type'] as String?) ?? 'query';
    final subtitle = (item['subtitle'] as String?) ?? '';
    final imageUrl =
        (item['imageUrl'] as String?) ??
        (item['thumbnailUrl'] as String?) ??
        '';

    final typeLabel = _formatType(type);
    final formattedSubtitle = subtitle.trim().isNotEmpty
        ? '$typeLabel • $subtitle'
        : typeLabel;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Row(
            children: [
              // 40x40 squircle thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: Container(
                  width: 40.0,
                  height: 40.0,
                  color: const Color(0xFF282828),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildFallbackIcon(type),
                        )
                      : _buildFallbackIcon(type),
                ),
              ),
              const SizedBox(width: 12.0),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      formattedSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA3A3A3),
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),

              // Right Action: Remove icon
              _RemoveButton(onTap: widget.onRemove),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatefulWidget {
  final VoidCallback onTap;

  const _RemoveButton({required this.onTap});

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

class _RemoveButtonState extends State<_RemoveButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(
            Icons.close,
            size: 16.0,
            color: _isHovered ? Colors.white : const Color(0xFF737373),
          ),
        ),
      ),
    );
  }
}
