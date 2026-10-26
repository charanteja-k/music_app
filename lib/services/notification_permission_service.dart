import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationPermissionService {
  /// Checks whether notification permission is granted on Android.
  static Future<bool> isPermissionGranted() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    return await Permission.notification.isGranted;
  }

  /// Explicitly requests notification permission and provides immediate user feedback.
  /// If permanently denied, presents a dialog directing the user to App Settings.
  static Future<bool> requestNotificationPermission(
    BuildContext context,
  ) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    if (result.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lock screen & notification controls enabled!'),
            backgroundColor: Color(0xFF1DB954),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    }

    if (result.isPermanentlyDenied) {
      if (context.mounted) {
        _showOpenSettingsDialog(context);
      }
    }
    return false;
  }

  /// Automatically prompts for notification permission when the user starts playing music
  /// or when the app launches, if permission has not yet been granted.
  static Future<void> promptIfNeeded(BuildContext context) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return;

      // Request system permission dialog directly
      final result = await Permission.notification.request();
      if (result.isPermanentlyDenied && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Enable notifications for lock screen media controls',
            ),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationPermission] Error checking permission: $e');
    }
  }

  /// Alias for backward compatibility
  static Future<void> checkAndPrompt(BuildContext context) =>
      promptIfNeeded(context);

  static void _showOpenSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: Color(0xFFFA2D48)),
            SizedBox(width: 10),
            Text(
              'Enable Controls',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'To show music playback controls and album artwork on your lock screen and notification drawer, please allow Notifications in App Settings.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Not Now',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
