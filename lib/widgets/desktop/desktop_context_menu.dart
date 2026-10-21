import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../models/jio_album.dart';
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
          title: 'Save to Your Library',
          icon: Icons.bookmark_border_rounded,
          onTap: () {
            final existing = musicService.customPlaylists.firstWhere(
              (p) =>
                  (p['name']?.toString().toLowerCase().trim() ?? '') ==
                  playlistName.toLowerCase().trim(),
              orElse: () => <String, dynamic>{},
            );
            if (existing.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"$playlistName" is already in your library.'),
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            final newId = musicService.createPlaylist(playlistName);
            final trackList = songs ?? [];
            if (trackList.isNotEmpty) {
              musicService.setPlaylistSongs(newId, trackList, commit: true);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved "$playlistName" to your library!'),
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
        title: 'Create playlist',
        icon: Icons.add_rounded,
        onTap: () {
          final newId = musicService.createPlaylist('New Playlist');
          if (newId.isNotEmpty) {
            DesktopLayoutState.openPlaylist(newId);
          }
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
    int? queueIndex,
    bool isNowPlaying = false,
  }) {
    final musicService = MusicService();
    final isLiked = musicService.isLiked(song.id.value);

    // 1. Contextual Menu for "Next in Queue" Items
    if (queueIndex != null) {
      return [
        DesktopContextMenuItem(
          title: 'Play Now',
          icon: Icons.play_arrow_rounded,
          onTap: () {
            musicService.playPlaylist(musicService.playlist, queueIndex);
          },
        ),
        DesktopContextMenuItem(
          title: 'Move to Top',
          icon: Icons.vertical_align_top_rounded,
          onTap: () {
            final currentIdx = musicService.currentIndex;
            final targetIdx = currentIdx >= 0 ? currentIdx + 1 : 0;
            musicService.reorderQueue(queueIndex, targetIdx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Moved "${song.title}" to top of queue'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        DesktopContextMenuItem(
          title: 'Remove from Queue',
          icon: Icons.playlist_remove_rounded,
          iconColor: const Color(0xFFFF5252),
          isDestructive: true,
          onTap: () {
            musicService.removeFromQueue(queueIndex);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${song.title}" from queue'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        const DesktopContextMenuItem.divider(),
        DesktopContextMenuItem(
          title: isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs',
          icon: isLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
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
        DesktopContextMenuItem(
          title: 'Add to Playlist',
          icon: Icons.playlist_add_rounded,
          onTap: () {
            showAddToPlaylistSheet(context, song);
          },
        ),
        DesktopContextMenuItem(
          title: 'Go to Album',
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
        DesktopContextMenuItem(
          title: 'View Artist Profile',
          icon: Icons.person_rounded,
          onTap: () {
            DesktopLayoutState.openArtist(song.author);
          },
        ),
        const DesktopContextMenuItem.divider(),
        DesktopContextMenuItem(
          title: 'Share Song',
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

    // 2. Contextual Menu for "Now Playing" Card
    if (isNowPlaying) {
      return [
        DesktopContextMenuItem(
          title: isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs',
          icon: isLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
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
        DesktopContextMenuItem(
          title: 'Add to Playlist',
          icon: Icons.playlist_add_rounded,
          onTap: () {
            showAddToPlaylistSheet(context, song);
          },
        ),
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
        DesktopContextMenuItem(
          title: 'Go to Album',
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
        DesktopContextMenuItem(
          title: 'View Artist Profile',
          icon: Icons.person_rounded,
          onTap: () {
            DesktopLayoutState.openArtist(song.author);
          },
        ),
        const DesktopContextMenuItem.divider(),
        DesktopContextMenuItem(
          title: 'Share Song',
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
      DesktopContextMenuItem(
        title: 'Play Album',
        icon: Icons.play_arrow_rounded,
        onTap: () async {
          if (songs != null && songs.isNotEmpty) {
            musicService.playPlaylist(songs, 0);
          } else if (albumId != null && albumId.isNotEmpty) {
            final loaded = await musicService.fetchAlbumTracks(albumId);
            if (loaded != null && loaded.songs.isNotEmpty) {
              final videoList = loaded.songs.map(songMapToVideo).toList();
              musicService.playPlaylist(videoList, 0);
            } else if (context.mounted) {
              DesktopLayoutState.openAlbum(
                albumId: albumId,
                albumTitle: albumTitle,
                albumArtwork: albumArtwork,
                albumArtist: albumArtist,
              );
            }
          } else {
            DesktopLayoutState.openAlbum(
              albumId: albumId,
              albumTitle: albumTitle,
              albumArtwork: albumArtwork,
              albumArtist: albumArtist,
            );
          }
        },
      ),
      DesktopContextMenuItem(
        title: 'Add to queue',
        icon: Icons.queue_music_rounded,
        onTap: () async {
          if (songs != null && songs.isNotEmpty) {
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
          } else if (albumId != null && albumId.isNotEmpty) {
            final loaded = await musicService.fetchAlbumTracks(albumId);
            if (loaded != null && loaded.songs.isNotEmpty) {
              final videoList = loaded.songs.map(songMapToVideo).toList();
              for (final song in videoList) {
                musicService.addToQueue(song);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added ${videoList.length} songs from "$albumTitle" to queue',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        },
      ),
      DesktopContextMenuItem(
        title: 'Play next',
        icon: Icons.playlist_play_rounded,
        onTap: () async {
          if (songs != null && songs.isNotEmpty) {
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
          } else if (albumId != null && albumId.isNotEmpty) {
            final loaded = await musicService.fetchAlbumTracks(albumId);
            if (loaded != null && loaded.songs.isNotEmpty) {
              final videoList = loaded.songs.map(songMapToVideo).toList();
              for (final song in videoList.reversed) {
                musicService.playNext(song);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Playing ${videoList.length} songs from "$albumTitle" next',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        },
      ),
      const DesktopContextMenuItem.divider(),
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
    int? queueIndex,
    bool isNowPlaying = false,
  }) {
    return show(
      context: context,
      globalPosition: globalPosition,
      items: songItems(
        context: context,
        song: song,
        currentPlaylistId: currentPlaylistId,
        onRemovedFromPlaylist: onRemovedFromPlaylist,
        queueIndex: queueIndex,
        isNowPlaying: isNowPlaying,
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
  int? queueIndex,
  bool isNowPlaying = false,
}) => DesktopContextMenu.showSongMenu(
  context: context,
  globalPosition: globalPosition,
  song: song,
  currentPlaylistId: currentPlaylistId,
  onRemovedFromPlaylist: onRemovedFromPlaylist,
  queueIndex: queueIndex,
  isNowPlaying: isNowPlaying,
);

/// Unified playlist menu popup for both right-click and 3-dot button triggers on desktop.
Future<void> showUnifiedPlaylistMenu({
  required BuildContext context,
  required Offset globalPosition,
  required dynamic playlist,
  bool isSidebar = false,
  VoidCallback? onCreatePlaylist,
  VoidCallback? onDeleted,
  VoidCallback? onPinnedChanged,
}) async {
  String playlistId = '';
  String playlistName = '';
  bool isSpotify = false;
  bool isCurated = false;
  List<Video>? songs;

  if (playlist is String) {
    playlistId = playlist;
    if (playlistId == 'liked_songs') {
      playlistName = 'Liked Songs';
    } else {
      final found = MusicService().customPlaylists.firstWhere(
        (p) => p['id']?.toString() == playlistId,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) {
        playlistName = found['name']?.toString() ?? 'Playlist';
        isSpotify = found['isSpotify'] == true;
        final rawSongs =
            (found['tracks'] as List?) ?? (found['songs'] as List?) ?? [];
        songs = rawSongs
            .whereType<Map<String, dynamic>>()
            .map(songMapToVideo)
            .toList();
      } else {
        playlistName = playlistId.replaceAll('_', ' ');
        if (playlistId.startsWith('curated_') ||
            playlistId.startsWith('daily_mix') ||
            playlistId == 'top_charts_india' ||
            playlistId == 'top_charts' ||
            playlistId == 'new_releases' ||
            playlistId == 'trending_now') {
          isCurated = true;
        }
      }
    }
  } else if (playlist is Map) {
    playlistId = (playlist['id'] ?? playlist['playlistId'] ?? '').toString();
    playlistName = (playlist['name'] ??
            playlist['title'] ??
            (playlistId == 'liked_songs' ? 'Liked Songs' : 'Playlist'))
        .toString();
    isSpotify = playlist['isSpotify'] == true ||
        (playlist['source']?.toString().contains('spotify') ?? false);
    isCurated = playlist['isCurated'] == true ||
        playlistId.startsWith('curated_') ||
        playlistId.startsWith('daily_mix') ||
        playlistId == 'top_charts_india' ||
        playlistId == 'top_charts' ||
        playlistId == 'new_releases' ||
        playlistId == 'trending_now';
    final raw =
        playlist['songs'] ?? playlist['tracks'] ?? playlist['initialSongs'];
    if (raw is List<Video>) {
      songs = raw;
    } else if (raw is List) {
      songs = raw
          .map((item) {
            if (item is Video) return item;
            if (item is Map<String, dynamic>) return songMapToVideo(item);
            if (item is Map) {
              return songMapToVideo(Map<String, dynamic>.from(item));
            }
            return null;
          })
          .whereType<Video>()
          .toList();
    }
  }

  return DesktopContextMenu.showPlaylistMenu(
    context: context,
    globalPosition: globalPosition,
    playlistId: playlistId,
    playlistName: playlistName,
    isSpotifyImport: isSpotify,
    isCurated: isCurated,
    songs: songs,
    onCreatePlaylist: onCreatePlaylist,
    onDeleted: onDeleted,
    onPinnedChanged: onPinnedChanged,
  );
}

/// Unified album menu popup for both right-click and 3-dot button triggers on desktop.
Future<void> showUnifiedAlbumMenu({
  required BuildContext context,
  required Offset globalPosition,
  required dynamic album,
}) async {
  String albumTitle = '';
  String? albumArtist;
  String? albumId;
  String? albumArtwork;
  List<Video>? songs;

  if (album is JioAlbum) {
    albumId = album.id;
    albumTitle = album.title;
    albumArtist = album.artist;
    albumArtwork = album.artwork;
    if (album.songs.isNotEmpty) {
      songs = album.songs.map(songMapToVideo).toList();
    }
  } else if (album is Map) {
    albumId = (album['id'] ?? album['albumId'] ?? '').toString();
    albumTitle = (album['title'] ??
            album['name'] ??
            album['albumTitle'] ??
            'Album')
        .toString();
    albumArtist = (album['artist'] ?? album['albumArtist'] ?? '').toString();
    albumArtwork =
        (album['artwork'] ?? album['thumbnail'] ?? album['albumArtwork'] ?? '')
            .toString();
    final rawSongs = album['songs'] ?? album['tracks'];
    if (rawSongs is List<Video>) {
      songs = rawSongs;
    } else if (rawSongs is List) {
      songs = rawSongs
          .map((item) {
            if (item is Video) return item;
            if (item is Map<String, dynamic>) return songMapToVideo(item);
            if (item is Map) {
              return songMapToVideo(Map<String, dynamic>.from(item));
            }
            return null;
          })
          .whereType<Video>()
          .toList();
    }
  } else if (album != null) {
    try {
      albumTitle = (album.title as String?) ?? 'Album';
    } catch (_) {}
    try {
      albumArtist = album.artist as String?;
    } catch (_) {}
    try {
      albumArtwork = (album.thumbnail as String?) ?? (album.artwork as String?);
    } catch (_) {}
    try {
      final rawSongs = album.songs;
      if (rawSongs is List<Video>) {
        songs = rawSongs;
      } else if (rawSongs is List) {
        songs = rawSongs
            .map((item) {
              if (item is Video) return item;
              if (item is Map<String, dynamic>) return songMapToVideo(item);
              if (item is Map) {
                return songMapToVideo(Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<Video>()
            .toList();
      }
    } catch (_) {}
  }

  return DesktopContextMenu.showAlbumMenu(
    context: context,
    globalPosition: globalPosition,
    albumTitle: albumTitle,
    albumArtist: albumArtist,
    albumId: albumId,
    albumArtwork: albumArtwork,
    songs: songs,
  );
}
