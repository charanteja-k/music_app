import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../playlist_action_menu.dart';
import '../song_options_bottom_sheet.dart';

/// Item descriptor for unified Desktop Context Menus.
class DesktopContextMenuItem {
  final String? title;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isDivider;
  final bool isPinned;
  final Widget? trailing;

  const DesktopContextMenuItem({
    required this.title,
    this.icon,
    this.iconColor,
    this.onTap,
    this.isDestructive = false,
    this.isPinned = false,
    this.trailing,
  }) : isDivider = false;

  const DesktopContextMenuItem.divider()
    : title = null,
      icon = null,
      iconColor = null,
      onTap = null,
      isDestructive = false,
      isDivider = true,
      isPinned = false,
      trailing = null;
}

/// Custom PopupMenuEntry rendering an individual hoverable context menu item.
class _DesktopPopupItemEntry extends PopupMenuEntry<VoidCallback> {
  final DesktopContextMenuItem item;
  final Color themeColor;

  const _DesktopPopupItemEntry({required this.item, required this.themeColor});

  @override
  double get height => 38.0;

  @override
  bool represents(VoidCallback? value) => value == item.onTap;

  @override
  State<_DesktopPopupItemEntry> createState() => _DesktopPopupItemEntryState();
}

class _DesktopPopupItemEntryState extends State<_DesktopPopupItemEntry> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDestructive = item.isDestructive;
    final effectiveTextColor = isDestructive
        ? const Color(0xFFFF5252)
        : Colors.white;
    final effectiveIconColor =
        item.iconColor ??
        (isDestructive
            ? const Color(0xFFFF5252)
            : (item.isPinned
                  ? const Color(0xFF1DB954)
                  : Colors.white.withValues(alpha: 0.75)));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop(item.onTap);
        },
        child: Container(
          height: 36.0,
          margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: _isHovered ? const Color(0xFF282836) : Colors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 16.0, color: effectiveIconColor),
                const SizedBox(width: 12.0),
              ],
              Expanded(
                child: Text(
                  item.title ?? '',
                  style: TextStyle(
                    color: effectiveTextColor,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.trailing != null) item.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom 1px divider for logical item grouping.
class _DesktopPopupDividerEntry extends PopupMenuEntry<VoidCallback> {
  const _DesktopPopupDividerEntry();

  @override
  double get height => 9.0;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_DesktopPopupDividerEntry> createState() =>
      _DesktopPopupDividerEntryState();
}

class _DesktopPopupDividerEntryState extends State<_DesktopPopupDividerEntry> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.0,
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

/// Spotify-grade Desktop Context Menu Engine.
///
/// Spawns an elevated dark-mode menu (#16161E) clamped precisely at cursor coordinates.
/// Reuses existing public service abstractions with zero extra dependencies.
class DesktopContextMenu {
  DesktopContextMenu._();

  /// Displays the contextual popup menu at the mouse coordinates.
  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition,
    required List<DesktopContextMenuItem> items,
  }) async {
    if (items.isEmpty) return;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlayBox =
        overlay ??
        (Navigator.of(context).context.findRenderObject() as RenderBox);

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlayBox.size,
    );

    final themeColor = PreferencesService().legibleThemeColor;

    final entries = <PopupMenuEntry<VoidCallback>>[];
    for (final item in items) {
      if (item.isDivider) {
        entries.add(const _DesktopPopupDividerEntry());
      } else {
        entries.add(_DesktopPopupItemEntry(item: item, themeColor: themeColor));
      }
    }

    final selectedCallback = await showMenu<VoidCallback>(
      context: context,
      position: position,
      items: entries,
      elevation: 16.0,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      color: const Color(0xFF16161E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      constraints: const BoxConstraints(minWidth: 190.0, maxWidth: 260.0),
      clipBehavior: Clip.antiAlias,
    );

    selectedCallback?.call();
  }

  /// Builds context menu items for a playlist (Curated/Daily Mix, User Custom, or Liked Songs).
  static List<DesktopContextMenuItem> playlistItems({
    required BuildContext context,
    required String playlistId,
    required String playlistName,
    bool isSpotifyImport = false,
    bool isCurated = false,
    List<Video>? songs,
    VoidCallback? onCreatePlaylist,
    VoidCallback? onDeleted,
    VoidCallback? onPinnedChanged,
  }) {
    final musicService = MusicService();
    final prefs = PreferencesService();
    final isLikedSongs = playlistId == 'liked_songs';

    // PERMANENT LIKED SONGS GUARD:
    // Strictly omit "Delete", "Remove", and "Unpin" for Liked Songs.
    if (isLikedSongs) {
      return [
        DesktopContextMenuItem(
          title: 'Add to queue',
          icon: Icons.queue_music_rounded,
          onTap: () {
            final liked = musicService.likedSongs;
            for (final song in liked) {
              musicService.addToQueue(songMapToVideo(song));
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${liked.length} Liked Songs to queue'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        DesktopContextMenuItem(
          title: 'Play next',
          icon: Icons.playlist_play_rounded,
          onTap: () {
            final liked = musicService.likedSongs;
            for (final song in liked.reversed) {
              musicService.playNext(songMapToVideo(song));
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Playing ${liked.length} Liked Songs next'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        const DesktopContextMenuItem.divider(),
        DesktopContextMenuItem(
          title: 'Share playlist',
          icon: Icons.share_rounded,
          onTap: () {
            Clipboard.setData(
              const ClipboardData(text: 'DilSe Music — Liked Songs'),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied Liked Songs link to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ];
    }

    final isSystemCurated =
        isCurated ||
        playlistId.startsWith('daily_mix') ||
        playlistId.startsWith('curated_') ||
        playlistId == 'top_charts';

    final isPinned = prefs.isPlaylistPinned(playlistId);

    if (isSystemCurated) {
      // DEFECT 2 - A: Curated / Daily Mix Playlists (System-Generated)
      return [
        DesktopContextMenuItem(
          title: 'Add to queue',
          icon: Icons.queue_music_rounded,
          onTap: () {
            final trackList = songs ?? [];
            if (trackList.isEmpty) {
              final pl = musicService.customPlaylists.firstWhere(
                (p) => p['id']?.toString() == playlistId,
                orElse: () => {},
              );
              final raw =
                  (pl['tracks'] as List?) ?? (pl['songs'] as List?) ?? [];
              for (final item in raw) {
                if (item is Map<String, dynamic>) {
                  musicService.addToQueue(songMapToVideo(item));
                }
              }
            } else {
              for (final song in trackList) {
                musicService.addToQueue(song);
              }
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added songs from "$playlistName" to queue'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        DesktopContextMenuItem(
          title: 'Play next',
          icon: Icons.playlist_play_rounded,
          onTap: () {
            final trackList = songs ?? [];
            if (trackList.isEmpty) {
              final pl = musicService.customPlaylists.firstWhere(
                (p) => p['id']?.toString() == playlistId,
                orElse: () => {},
              );
              final raw =
                  (pl['tracks'] as List?) ?? (pl['songs'] as List?) ?? [];
              for (final item in raw.reversed) {
                if (item is Map<String, dynamic>) {
                  musicService.playNext(songMapToVideo(item));
                }
              }
            } else {
              for (final song in trackList.reversed) {
                musicService.playNext(song);
              }
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Playing songs from "$playlistName" next'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        const DesktopContextMenuItem.divider(),
        DesktopContextMenuItem(
          title: isPinned ? 'Unpin from Library' : 'Pin to Your Library',
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          isPinned: isPinned,
          onTap: () async {
            await prefs.togglePinPlaylist(playlistId);
            onPinnedChanged?.call();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isPinned
                        ? 'Unpinned "$playlistName"'
                        : 'Pinned "$playlistName" to Library 📌',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        DesktopContextMenuItem(
          title: 'Share playlist',
          icon: Icons.share_rounded,
          onTap: () {
            Clipboard.setData(
              ClipboardData(text: 'DilSe Music Playlist: $playlistName'),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied link for "$playlistName"'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ];
    }

    // DEFECT 2 - B: User-Created Custom Playlists
    return [
      DesktopContextMenuItem(
        title: 'Add to queue',
        icon: Icons.queue_music_rounded,
        onTap: () {
          final pl = musicService.customPlaylists.firstWhere(
            (p) => p['id']?.toString() == playlistId,
            orElse: () => {},
          );
          final rawSongs =
              (pl['tracks'] as List?) ?? (pl['songs'] as List?) ?? [];
          int added = 0;
          for (final item in rawSongs) {
            if (item is Map<String, dynamic>) {
              musicService.addToQueue(songMapToVideo(item));
              added++;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added $added songs from "$playlistName" to queue'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      DesktopContextMenuItem(
        title: 'Play next',
        icon: Icons.playlist_play_rounded,
        onTap: () {
          final pl = musicService.customPlaylists.firstWhere(
            (p) => p['id']?.toString() == playlistId,
            orElse: () => {},
          );
          final rawSongs =
              (pl['tracks'] as List?) ?? (pl['songs'] as List?) ?? [];
          final reversed = rawSongs.reversed.toList();
          int count = 0;
          for (final item in reversed) {
            if (item is Map<String, dynamic>) {
              musicService.playNext(songMapToVideo(item));
              count++;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing $count songs from "$playlistName" next'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      const DesktopContextMenuItem.divider(),
      DesktopContextMenuItem(
        title: isPinned ? 'Unpin playlist' : 'Pin playlist',
        icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        isPinned: isPinned,
        onTap: () async {
          await prefs.togglePinPlaylist(playlistId);
          onPinnedChanged?.call();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isPinned
                      ? 'Unpinned "$playlistName"'
                      : 'Pinned "$playlistName" 📌',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
      DesktopContextMenuItem(
        title: 'Rename playlist',
        icon: Icons.edit_outlined,
        onTap: () {
          PlaylistActionMenu.showRenameDialog(
            context,
            playlistId: playlistId,
            currentName: playlistName,
          );
        },
      ),
      DesktopContextMenuItem(
        title: 'Edit details',
        icon: Icons.tune_rounded,
        onTap: () {
          PlaylistActionMenu.showRenameDialog(
            context,
            playlistId: playlistId,
            currentName: playlistName,
          );
        },
      ),
      const DesktopContextMenuItem.divider(),
      DesktopContextMenuItem(
        title: 'Share playlist',
        icon: Icons.share_rounded,
        onTap: () {
          Clipboard.setData(
            ClipboardData(text: 'DilSe Music Playlist: $playlistName'),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied link for "$playlistName"'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      DesktopContextMenuItem(
        title: 'Delete playlist',
        icon: Icons.delete_outline_rounded,
        isDestructive: true,
        onTap: () {
          PlaylistActionMenu.showDeleteDialog(
            context,
            playlistId: playlistId,
            playlistName: playlistName,
            onDeleted: onDeleted,
          );
        },
      ),
    ];
  }

  /// Builds context menu items for an individual track.
  static List<DesktopContextMenuItem> songItems({
    required BuildContext context,
    required Video song,
    String? currentPlaylistId,
    VoidCallback? onRemovedFromPlaylist,
  }) {
    final musicService = MusicService();
    final isLiked = musicService.isLiked(song.id.value);

    return [
      // 0. Play
      DesktopContextMenuItem(
        title: 'Play',
        icon: Icons.play_arrow_rounded,
        onTap: () {
          musicService.playSong(song);
        },
      ),
      // 1. Play Next
      DesktopContextMenuItem(
        title: 'Play next',
        icon: Icons.playlist_play_rounded,
        onTap: () {
          musicService.playNext(song);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing next: "${song.title}"'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      // 2. Add to Queue
      DesktopContextMenuItem(
        title: 'Add to queue',
        icon: Icons.queue_music_rounded,
        onTap: () {
          musicService.addToQueue(song);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${song.title}" to queue'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      const DesktopContextMenuItem.divider(),
      // 3. Save to your Liked Songs / Remove from Liked Songs
      DesktopContextMenuItem(
        title: isLiked ? 'Remove from Liked Songs' : 'Save to your Liked Songs',
        icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        iconColor: isLiked ? const Color(0xFFFA2D48) : null,
        onTap: () {
          musicService.toggleLike(song);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isLiked
                    ? 'Removed from Liked Songs'
                    : 'Saved to Liked Songs ❤️',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      // 4. Add to Playlist
      DesktopContextMenuItem(
        title: 'Add to playlist',
        icon: Icons.playlist_add_rounded,
        onTap: () {
          showAddToPlaylistSheet(context, song);
        },
      ),
      // 5. Start Song Radio
      DesktopContextMenuItem(
        title: 'Start Song Radio',
        icon: Icons.radio_rounded,
        onTap: () {
          musicService.startSongRadio(song);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Starting radio for "${song.title}"'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      const DesktopContextMenuItem.divider(),
      // 6. Go to Album
      DesktopContextMenuItem(
        title: 'Go to album',
        icon: Icons.album_rounded,
        onTap: () async {
          final cachedAlbum = MusicService.getCachedAlbum(song.id.value);
          if (cachedAlbum != null && cachedAlbum.songs.isNotEmpty) {
            DesktopLayoutState.openAlbum(album: cachedAlbum);
            return;
          }
          final cachedId = MusicService.getCachedAlbumId(song.id.value);
          final cachedTitle =
              MusicService.getCachedAlbumTitle(song.id.value) ??
              MusicService.extractMovieOrAlbumTitle(song.title);
          if ((cachedId != null && cachedId.isNotEmpty) ||
              (cachedTitle != null && cachedTitle.isNotEmpty)) {
            DesktopLayoutState.openAlbum(
              albumId: cachedId,
              albumTitle: cachedTitle,
              albumArtwork: MusicService.getHdThumbnail(song.id.value),
              albumArtist: song.author,
            );
            return;
          }
          final resolved = await musicService.resolveAlbumForSong(song);
          if (resolved != null && resolved.songs.isNotEmpty) {
            DesktopLayoutState.openAlbum(album: resolved);
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No album found for "${song.title}"'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
      // 7. View Artist Profile
      DesktopContextMenuItem(
        title: 'Go to artist',
        icon: Icons.person_rounded,
        onTap: () {
          DesktopLayoutState.openArtist(song.author);
        },
      ),
      if (currentPlaylistId != null && currentPlaylistId != 'liked_songs')
        DesktopContextMenuItem(
          title: 'Remove from this playlist',
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
          onTap: () {
            musicService.removeSongFromPlaylist(
              currentPlaylistId,
              song.id.value,
            );
            onRemovedFromPlaylist?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${song.title}" from playlist'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      if (!kIsWeb)
        DesktopContextMenuItem(
          title: 'Download for offline',
          icon: Icons.download_rounded,
          onTap: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Starting download...'),
                duration: Duration(seconds: 2),
              ),
            );
            final success = await musicService.downloadSong(song);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? 'Download complete!' : 'Download failed.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      const DesktopContextMenuItem.divider(),
      // 8. Share Song
      DesktopContextMenuItem(
        title: 'Share song',
        icon: Icons.share_rounded,
        onTap: () {
          Clipboard.setData(
            ClipboardData(text: '${song.title} - ${song.author}'),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied "${song.title}" to clipboard'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    ];
  }

  /// Builds context menu items for an album.
  static List<DesktopContextMenuItem> albumItems({
    required BuildContext context,
    required String albumTitle,
    String? albumArtist,
    String? albumId,
    String? albumArtwork,
    List<Video>? songs,
  }) {
    final prefs = PreferencesService();
    final musicService = MusicService();
    final isSaved = prefs.isAlbumSaved(albumId ?? albumTitle);

    return [
      if (songs != null && songs.isNotEmpty) ...[
        DesktopContextMenuItem(
          title: 'Add to queue',
          icon: Icons.queue_music_rounded,
          onTap: () {
            for (final song in songs) {
              musicService.addToQueue(song);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Added ${songs.length} songs from "$albumTitle" to queue',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        DesktopContextMenuItem(
          title: 'Play next',
          icon: Icons.playlist_play_rounded,
          onTap: () {
            for (final song in songs.reversed) {
              musicService.playNext(song);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Playing ${songs.length} songs from "$albumTitle" next',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        const DesktopContextMenuItem.divider(),
      ],
      DesktopContextMenuItem(
        title: isSaved ? 'Remove from Your Library' : 'Save to Your Library',
        icon: isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
        iconColor: isSaved ? prefs.legibleThemeColor : null,
        onTap: () async {
          await prefs.toggleSaveAlbum({
            'id': albumId ?? albumTitle,
            'title': albumTitle,
            'artist': albumArtist ?? '',
            'artwork': albumArtwork ?? '',
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isSaved
                      ? 'Removed "$albumTitle" from Library'
                      : 'Saved "$albumTitle" to Your Library',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
      if (albumArtist != null && albumArtist.isNotEmpty) ...[
        DesktopContextMenuItem(
          title: 'Go to artist',
          icon: Icons.person_rounded,
          onTap: () {
            DesktopLayoutState.openArtist(albumArtist);
          },
        ),
      ],
      const DesktopContextMenuItem.divider(),
      DesktopContextMenuItem(
        title: 'Share album',
        icon: Icons.share_rounded,
        onTap: () {
          Clipboard.setData(
            ClipboardData(
              text: albumArtist != null && albumArtist.isNotEmpty
                  ? '$albumTitle — $albumArtist'
                  : albumTitle,
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied link for "$albumTitle"'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    ];
  }

  /// Convenience shortcut to show a playlist context menu.
  static Future<void> showPlaylistMenu({
    required BuildContext context,
    required Offset globalPosition,
    required String playlistId,
    required String playlistName,
    bool isSpotifyImport = false,
    bool isCurated = false,
    List<Video>? songs,
    VoidCallback? onCreatePlaylist,
    VoidCallback? onDeleted,
    VoidCallback? onPinnedChanged,
  }) {
    return show(
      context: context,
      globalPosition: globalPosition,
      items: playlistItems(
        context: context,
        playlistId: playlistId,
        playlistName: playlistName,
        isSpotifyImport: isSpotifyImport,
        isCurated: isCurated,
        songs: songs,
        onCreatePlaylist: onCreatePlaylist,
        onDeleted: onDeleted,
        onPinnedChanged: onPinnedChanged,
      ),
    );
  }

  /// Convenience shortcut to show a song context menu.
  static Future<void> showSongMenu({
    required BuildContext context,
    required Offset globalPosition,
    required Video song,
    String? currentPlaylistId,
    VoidCallback? onRemovedFromPlaylist,
  }) {
    return show(
      context: context,
      globalPosition: globalPosition,
      items: songItems(
        context: context,
        song: song,
        currentPlaylistId: currentPlaylistId,
        onRemovedFromPlaylist: onRemovedFromPlaylist,
      ),
    );
  }

  /// Convenience shortcut to show an album context menu.
  static Future<void> showAlbumMenu({
    required BuildContext context,
    required Offset globalPosition,
    required String albumTitle,
    String? albumArtist,
    String? albumId,
    String? albumArtwork,
    List<Video>? songs,
  }) {
    return show(
      context: context,
      globalPosition: globalPosition,
      items: albumItems(
        context: context,
        albumTitle: albumTitle,
        albumArtist: albumArtist,
        albumId: albumId,
        albumArtwork: albumArtwork,
        songs: songs,
      ),
    );
  }
}

/// Global top-level function matching specification requirement:
/// ```dart
/// Future<void> showDesktopContextMenu({
///   required BuildContext context,
///   required Offset globalPosition,
///   required List<DesktopContextMenuItem> items,
/// })
/// ```
Future<void> showDesktopContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<DesktopContextMenuItem> items,
}) => DesktopContextMenu.show(
  context: context,
  globalPosition: globalPosition,
  items: items,
);

/// Unified track menu popup for both right-click and 3-dot button triggers on desktop.
Future<void> showUnifiedTrackMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Video song,
  String? currentPlaylistId,
  VoidCallback? onRemovedFromPlaylist,
}) => DesktopContextMenu.showSongMenu(
  context: context,
  globalPosition: globalPosition,
  song: song,
  currentPlaylistId: currentPlaylistId,
  onRemovedFromPlaylist: onRemovedFromPlaylist,
);
