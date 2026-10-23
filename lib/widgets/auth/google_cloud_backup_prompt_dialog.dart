import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/audio/favorites_repository.dart';

/// Modal dialog presented to users upon first launch after Google sign-in
/// offering a 1-tap option to back up their local playlists and liked songs to the cloud.
class GoogleCloudBackupPromptDialog extends StatelessWidget {
  final CloudSyncAnalysis? analysis;

  const GoogleCloudBackupPromptDialog({super.key, this.analysis});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final displayName = auth.userDisplayName ?? 'Music Lover';
    final playlistCount = analysis != null
        ? analysis!.newLocalPlaylistsCount
        : MusicService().customPlaylists.length;
    final likesCount = analysis != null
        ? analysis!.newLocalLikesCount
        : FavoritesRepository().likedSongs.length;

    String readyText;
    if (playlistCount > 0 && likesCount > 0) {
      readyText = '$playlistCount Playlists • $likesCount Likes ready';
    } else if (likesCount > 0) {
      readyText = '$likesCount Likes ready to back up';
    } else if (playlistCount > 0) {
      readyText = '$playlistCount Playlists ready to back up';
    } else {
      readyText = 'Ready to sync with cloud';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Cloud Icon with Ambient Gradient Glow
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_upload_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),

            // Dialog Title
            const Text(
              'Back Up to Cloud',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              'Welcome, $displayName! Keep your music collection safe. Sync your playlists and liked songs to your Google Account across all devices.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),

            // Ready to sync metadata pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.folder_special_rounded,
                    color: Color(0xFF60A5FA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    readyText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await PreferencesService()
                          .setHasPromptedGoogleCloudBackup(true);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white60,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Maybe Later',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await PreferencesService()
                          .setHasPromptedGoogleCloudBackup(true);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Backing up your library to cloud...'),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }

                      final result = await CloudSyncService().sync();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? 'Library safely backed up to Cloudflare Cloud!'
                                  : 'Backup note: ${result.message}',
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: result.success
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF332025),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.cloud_done_rounded, size: 18),
                    label: const Text('Back Up Now'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2563EB),
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
