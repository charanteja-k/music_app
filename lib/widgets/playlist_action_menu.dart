import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import 'desktop/desktop_context_menu.dart';

/// Reusable three-dot More action menu for playlists.
/// Encapsulates playlist-level management actions (Rename, Delete, Source toggling)
/// with built-in dialog flows usable across Library rows and opened playlist screens.
class PlaylistActionMenu extends StatelessWidget {
  final String playlistId;
  final String playlistName;
  final bool isSpotifyImport;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleSource;
  final bool closeScreenOnDelete;
  final void Function(String newName)? onRenamed;
  final VoidCallback? onDeleted;
  final Widget? customTrigger;
  final Color? iconColor;
  final double iconSize;

  const PlaylistActionMenu({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.isSpotifyImport = false,
    this.onRename,
    this.onDelete,
    this.onToggleSource,
    this.closeScreenOnDelete = false,
    this.onRenamed,
    this.onDeleted,
    this.customTrigger,
    this.iconColor,
    this.iconSize = 20,
  });

  /// Displays the standardized Rename Playlist dialog.
  static Future<void> showRenameDialog(
    BuildContext context, {
    required String playlistId,
    required String currentName,
    void Function(String newName)? onRenamed,
  }) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New playlist name',
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != currentName) {
                MusicService().renamePlaylist(playlistId, newName);
                onRenamed?.call(newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Displays the standardized Delete Playlist confirmation dialog.
  static Future<void> showDeleteDialog(
    BuildContext context, {
    required String playlistId,
    required String playlistName,
    bool closeScreenOnDelete = false,
    VoidCallback? onDeleted,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "$playlistName"?',
          style: const TextStyle(color: Colors.white70),
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
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              MusicService().deletePlaylist(playlistId);
              PreferencesService().unregisterSpotifyPlaylistId(playlistId);
              PreferencesService().unregisterManualPlaylistId(playlistId);
              Navigator.pop(ctx);
              onDeleted?.call();
              if (closeScreenOnDelete) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    HapticFeedback.lightImpact();
    switch (action) {
      case 'rename':
        if (onRename != null) {
          onRename!();
        } else {
          showRenameDialog(
            context,
            playlistId: playlistId,
            currentName: playlistName,
            onRenamed: onRenamed,
          );
        }
        break;
      case 'toggle_source':
        onToggleSource?.call();
        break;
      case 'delete':
        if (onDelete != null) {
          onDelete!();
        } else {
          showDeleteDialog(
            context,
            playlistId: playlistId,
            playlistName: playlistName,
            closeScreenOnDelete: closeScreenOnDelete,
            onDeleted: onDeleted,
          );
        }
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
  ) => <PopupMenuEntry<String>>[
    const PopupMenuItem<String>(
      value: 'rename',
      height: 44,
      child: Row(
        children: [
          Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rename',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
    if (onToggleSource != null) ...[
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'toggle_source',
        height: 44,
        child: Row(
          children: [
            Icon(
              isSpotifyImport
                  ? Icons.person_outline_rounded
                  : Icons.sync_alt_rounded,
              color: isSpotifyImport ? Colors.white70 : const Color(0xFF1DB954),
              size: 18,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                isSpotifyImport ? 'Set as Personal' : 'Set as Spotify',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSpotifyImport
                      ? Colors.white
                      : const Color(0xFF1DB954),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
    const PopupMenuDivider(height: 1),
    const PopupMenuItem<String>(
      value: 'delete',
      height: 44,
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Delete',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = kIsWeb || MediaQuery.of(context).size.width >= 1024;

    void openUnifiedMenu(BuildContext btnCtx) {
      final renderBox = btnCtx.findRenderObject() as RenderBox?;
      final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      final size = renderBox?.size ?? Size.zero;
      final anchor = Offset(offset.dx, offset.dy + size.height);
      showUnifiedPlaylistMenu(
        context: context,
        globalPosition: anchor,
        playlist: {
          'id': playlistId,
          'name': playlistName,
          'isSpotify': isSpotifyImport,
        },
        onDeleted: () {
          onDeleted?.call();
          if (closeScreenOnDelete) {
            Navigator.of(context).pop();
          }
        },
      );
    }

    if (isDesktop) {
      if (customTrigger != null) {
        return Builder(
          builder: (btnCtx) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openUnifiedMenu(btnCtx),
            child: customTrigger,
          ),
        );
      }
      return Builder(
        builder: (btnCtx) => IconButton(
          tooltip: 'More options',
          icon: Icon(
            Icons.more_vert_rounded,
            color: iconColor ?? Colors.white54,
            size: iconSize,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          splashRadius: 20,
          onPressed: () => openUnifiedMenu(btnCtx),
        ),
      );
    }

    final menu = customTrigger != null
        ? PopupMenuButton<String>(
            tooltip: 'More options',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            offset: const Offset(0, 40),
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: _buildMenuItems,
            child: customTrigger,
          )
        : PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(
              Icons.more_vert_rounded,
              color: iconColor ?? Colors.white54,
              size: iconSize,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 20,
            offset: const Offset(0, 40),
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: _buildMenuItems,
          );

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.white.withValues(alpha: 0.08),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF181818),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
        ),
      ),
      child: menu,
    );
  }
}
