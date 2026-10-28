import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cloud_sync_service.dart';
import '../services/preferences_service.dart';
import '../services/update_service.dart';
import 'interactive_update_dialog.dart';

/// Hidden Top-Bar Action Button 1:
/// Appears when "Backup" is clicked or while new JSON details are actively backing up to cloud.
/// Gently fades out once sync is complete.
class CloudBackupTopBarButton extends StatefulWidget {
  const CloudBackupTopBarButton({super.key});

  @override
  State<CloudBackupTopBarButton> createState() =>
      _CloudBackupTopBarButtonState();
}

class _CloudBackupTopBarButtonState extends State<CloudBackupTopBarButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  Timer? _autoHideTimer;
  bool _forceVisible = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    CloudSyncService().syncStatus.addListener(_onSyncStatusChanged);
  }

  void _onSyncStatusChanged() {
    final status = CloudSyncService().syncStatus.value;
    if (status == CloudSyncStatus.syncing) {
      _autoHideTimer?.cancel();
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
      if (mounted) setState(() => _forceVisible = true);
    } else {
      _spinController.stop();
      if (status == CloudSyncStatus.success ||
          status == CloudSyncStatus.error ||
          status == CloudSyncStatus.offline) {
        // Keep visible for 4.5 seconds to acknowledge completion
        _autoHideTimer?.cancel();
        _autoHideTimer = Timer(const Duration(milliseconds: 4500), () {
          if (mounted) {
            setState(() => _forceVisible = false);
          }
        });
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    CloudSyncService().syncStatus.removeListener(_onSyncStatusChanged);
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudSyncStatus>(
      valueListenable: CloudSyncService().syncStatus,
      builder: (context, status, _) {
        final isSyncing = status == CloudSyncStatus.syncing;
        final isVisible = isSyncing || _forceVisible;

        if (!isVisible) {
          return const SizedBox.shrink();
        }

        final isSuccess = status == CloudSyncStatus.success;
        final isError =
            status == CloudSyncStatus.error ||
            status == CloudSyncStatus.offline;

        final Color accentColor = isSyncing
            ? const Color(0xFF38BDF8)
            : isSuccess
            ? const Color(0xFF34D399)
            : isError
            ? const Color(0xFFF87171)
            : const Color(0xFF818CF8);

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Tooltip(
            message: isSyncing
                ? 'Backing up library to Cloudflare...'
                : isSuccess
                ? 'Cloud backup up to date'
                : isError
                ? 'Backup issue. Tap to retry.'
                : 'Cloud backup',
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final currentStatus = CloudSyncService().syncStatus.value;
                if (currentStatus == CloudSyncStatus.syncing) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cloud backup in progress...'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Starting cloud backup...'),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  final res = await CloudSyncService().sync(
                    forcePushLocal: true,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          res.success
                              ? 'Backup completed: ${res.mergedPlaylistsCount} playlists, ${res.mergedLikesCount} likes.'
                              : 'Backup note: ${res.message}',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: res.success
                            ? const Color(0xFF1E293B)
                            : const Color(0xFF332025),
                      ),
                    );
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF181818),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: isSyncing
                      ? RotationTransition(
                          turns: _spinController,
                          child: Icon(
                            Icons.sync_rounded,
                            color: accentColor,
                            size: 20,
                          ),
                        )
                      : Icon(
                          isSuccess
                              ? Icons.cloud_done_rounded
                              : isError
                              ? Icons.cloud_off_rounded
                              : Icons.cloud_upload_rounded,
                          color: accentColor,
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Hidden Top-Bar Action Button 2:
/// Appears strictly when a newer version is available compared to the current application build.
/// Tapping opens the interactive update dialogue or versions sheet.
class AppUpdateTopBarButton extends StatelessWidget {
  const AppUpdateTopBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateInfo?>(
      valueListenable: UpdateService().latestUpdateInfoNotifier,
      builder: (context, updateInfo, _) {
        final info =
            updateInfo ??
            (PreferencesService().pendingUpdateInfo != null
                ? AppUpdateInfo.fromJson(
                    PreferencesService().pendingUpdateInfo!,
                  )
                : null);

        if (info == null || !info.hasUpdate) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Tooltip(
            message: 'New update available: ${info.tagName}',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierColor: Colors.black.withValues(alpha: 0.75),
                  builder: (ctx) => InteractiveUpdateDialog(info: info),
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF181818),
                      border: Border.all(
                        color: const Color(0xFFE03E52).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFE03E52,
                          ).withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.system_update_rounded,
                        color: Color(0xFFFF5277),
                        size: 20,
                      ),
                    ),
                  ),

                  // Notification dot on top right
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF181818),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
