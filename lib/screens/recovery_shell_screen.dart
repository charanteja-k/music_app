import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_theme_tokens.dart';
import '../services/data_snapshot_service.dart';
import '../services/bug_report_service.dart';
import '../widgets/previous_versions_sheet.dart';
import 'intro_splash_screen.dart';
import 'main_screen.dart';

/// Sovereign, engine-independent recovery shell for DilSe Music.
///
/// Codified under Rule #7: Sovereign Bootstrap & Recovery Invariant.
/// This screen has ZERO dependencies on [MusicService], audio sessions,
/// platform equalizers, or online streaming cascades. It guarantees that users
/// can always rollback versions, restore data snapshots, clear corrupted caches,
/// or export diagnostics even if the core UI or audio engine crashes.
class RecoveryShellScreen extends StatefulWidget {
  final FlutterErrorDetails? errorDetails;
  final bool isCrashRecovery;

  const RecoveryShellScreen({
    super.key,
    this.errorDetails,
    this.isCrashRecovery = false,
  });

  @override
  State<RecoveryShellScreen> createState() => _RecoveryShellScreenState();
}

class _RecoveryShellScreenState extends State<RecoveryShellScreen> {
  final DataSnapshotService _snapshotService = DataSnapshotService();

  bool _isRestoring = false;
  bool _isPurgingCache = false;
  bool _showStackTrace = false;
  String _appVersion = 'Loading...';
  String _snapshotStatus = 'Checking backup status...';
  bool _hasSnapshot = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version} (Build ${info.buildNumber})';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = 'v3.9.13+36';
        });
      }
    }

    try {
      if (!kIsWeb) {
        final snapshotFile = await _snapshotService.findLatestSnapshotFile();
        if (mounted) {
          setState(() {
            if (snapshotFile != null && snapshotFile.existsSync()) {
              _hasSnapshot = true;
              final sizeKb = (snapshotFile.lengthSync() / 1024).toStringAsFixed(
                1,
              );
              _snapshotStatus = 'Safety backup available ($sizeKb KB)';
            } else {
              _hasSnapshot = false;
              _snapshotStatus = 'No offline snapshot found on device';
            }
          });
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final hasWebBackup =
            prefs.containsKey('dilse_safety_snapshot_web') ||
            prefs.containsKey('custom_playlists_web');
        if (mounted) {
          setState(() {
            _hasSnapshot = hasWebBackup;
            _snapshotStatus = hasWebBackup
                ? 'Web storage backup available'
                : 'No web snapshot found';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasSnapshot = false;
          _snapshotStatus = 'Snapshot status unavailable ($e)';
        });
      }
    }
  }

  Future<void> _restoreSnapshot() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeTokens.radiusCard),
          side: const BorderSide(color: AppThemeTokens.surfaceBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.restore_page_rounded, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Restore Snapshot?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will restore your custom playlists, liked songs, and settings '
          'from your latest safety backup.\n\n'
          'Existing downloaded music files will not be deleted.',
          style: TextStyle(color: AppThemeTokens.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.greenAccent.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Restore Now',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isRestoring = true);

    try {
      final result = await _snapshotService.restoreFromLatestSnapshot();
      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E3A24),
            content: Text(
              'Snapshot Restored! ${result.restoredPlaylists} playlists, '
              '${result.restoredLikedSongs} liked songs restored.',
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF3A1E1E),
            content: Text(
              'Restore failed: ${result.errorMessage ?? "Unknown error"}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF3A1E1E),
            content: Text(
              'Restore error: $e',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
        _loadMetadata();
      }
    }
  }

  Future<void> _purgeTransientCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeTokens.radiusCard),
          side: const BorderSide(color: AppThemeTokens.surfaceBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Colors.amberAccent),
            SizedBox(width: 10),
            Text(
              'Clear Cache & Reset State?',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: const Text(
          'This will purge corrupt temporary cache files, home feed caches, '
          'and stale session tokens.\n\n'
          'Your offline downloaded songs and custom playlists are preserved and will NOT be erased.',
          style: TextStyle(color: AppThemeTokens.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amberAccent.shade700,
            ),
            onPressed: () {
              Navigator.of(ctx, rootNavigator: true).pop(true);
            },
            child: const Text(
              'Confirm Purge',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isPurgingCache = true);

    int deletedCount = 0;
    try {
      if (!kIsWeb) {
        try {
          final tempDir = await getTemporaryDirectory().timeout(
            const Duration(seconds: 2),
          );
          final p = tempDir.path;
          if (p.isNotEmpty &&
              p != '.' &&
              p != '/' &&
              !p.endsWith('music_app') &&
              tempDir.existsSync()) {
            final entities = tempDir.listSync(recursive: false);
            for (final entity in entities) {
              try {
                entity.deleteSync(recursive: true);
                deletedCount++;
              } catch (_) {}
            }
          }
        } catch (dirErr) {
          debugPrint('[Recovery] Temp directory purge skipped: $dirErr');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        if (key.startsWith('home_cache_') ||
            key == 'last_playback_session' ||
            key == 'last_playback_position' ||
            key == 'pending_update_info') {
          await prefs.remove(key);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF282818),
            content: Text(
              'Transient cache cleaned ($deletedCount cache entries removed).',
              style: const TextStyle(color: Colors.amberAccent),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF3A1E1E),
            content: Text(
              'Failed to clear cache: $e',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurgingCache = false);
      }
    }
  }

  void _copyDiagnostics() {
    final buffer = StringBuffer();
    buffer.writeln('=== DILSE RECOVERY DIAGNOSTICS ===');
    buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    buffer.writeln('App Version: $_appVersion');
    buffer.writeln(
      'Platform: ${kIsWeb ? "Web" : Platform.operatingSystem} ${kIsWeb ? "" : Platform.operatingSystemVersion}',
    );
    buffer.writeln('Crash Mode: ${widget.isCrashRecovery}');

    if (widget.errorDetails != null) {
      buffer.writeln('\n--- Exception ---');
      buffer.writeln(widget.errorDetails!.exceptionAsString());
      buffer.writeln('\n--- Stack Trace ---');
      buffer.writeln(widget.errorDetails!.stack.toString());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard.')),
    );
  }

  void _attemptNormalLaunch() {
    IntroSplashScreen.hasCompletedSplash = true;
    final nav =
        BugReportService.instance.rootNavKey.currentState ??
        Navigator.of(context);
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // If mounted as an isolated ErrorWidget without Navigator/Theme, wrap safely
    final scaffoldContent = Scaffold(
      backgroundColor: AppThemeTokens.oledBackground,
      appBar: AppBar(
        backgroundColor: AppThemeTokens.oledBackground,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.amberAccent,
                  size: 18,
                ),
              ),
        title: const Text(
          'Safe Mode & Recovery',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Recovery Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E1408),
                      Colors.amberAccent.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(
                    AppThemeTokens.radiusCard,
                  ),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.amberAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sovereign Recovery Shell',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Completely decoupled from audio hardware and streaming services. '
                            'If an update or corrupt cache causes crashes or a black screen, use the recovery tools below.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Crash Diagnostics Card (if error details present)
              if (widget.errorDetails != null || widget.isCrashRecovery) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF241010),
                    borderRadius: BorderRadius.circular(
                      AppThemeTokens.radiusCard,
                    ),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Framework Error Intercepted',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                            label: const Text(
                              'Copy',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: _copyDiagnostics,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.errorDetails?.exceptionAsString() ??
                              'An unhandled exception occurred in the widget tree.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.errorDetails?.stack != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showStackTrace = !_showStackTrace;
                            });
                          },
                          child: Text(
                            _showStackTrace
                                ? 'Hide Stack Trace'
                                : 'View Full Stack Trace',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_showStackTrace) ...[
                          const SizedBox(height: 6),
                          Container(
                            height: 140,
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                widget.errorDetails!.stack.toString(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'EMERGENCY RECOVERY ACTIONS',
                style: TextStyle(
                  color: AppThemeTokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // Tool 1: Version Rollback & Update Engine
              _buildRecoveryActionCard(
                icon: Icons.history_rounded,
                iconColor: Colors.cyanAccent,
                title: 'Rollback to Previous Versions / Update',
                subtitle:
                    'Install any previous GitHub release if an update introduces bugs, or check for new hotfixes.',
                actionLabel: 'Manage Versions',
                actionColor: Colors.cyanAccent,
                onTap: () => PreviousVersionsSheet.show(context),
              ),

              const SizedBox(height: 12),

              // Tool 2: Safety Snapshot Restore
              _buildRecoveryActionCard(
                icon: Icons.restore_page_rounded,
                iconColor: Colors.greenAccent,
                title: 'Restore Safety Snapshot',
                subtitle: _snapshotStatus,
                actionLabel: _isRestoring ? 'Restoring...' : 'Restore Backup',
                actionColor: Colors.greenAccent,
                isLoading: _isRestoring,
                enabled: _hasSnapshot && !_isRestoring,
                onTap: _restoreSnapshot,
              ),

              const SizedBox(height: 12),

              // Tool 3: Purge Transient Cache & State
              _buildRecoveryActionCard(
                icon: Icons.cleaning_services_rounded,
                iconColor: Colors.amberAccent,
                title: 'Purge Corrupt Cache & State',
                subtitle:
                    'Wipes temporary files, cached feeds, and stale session tokens without touching your offline music.',
                actionLabel: _isPurgingCache ? 'Purging...' : 'Purge Cache',
                actionColor: Colors.amberAccent,
                isLoading: _isPurgingCache,
                enabled: !_isPurgingCache,
                onTap: _purgeTransientCache,
              ),

              const SizedBox(height: 12),

              // Tool 4: Normal Launch
              _buildRecoveryActionCard(
                icon: Icons.rocket_launch_rounded,
                iconColor: AppThemeTokens.brandRuby,
                title: 'Launch Normal App',
                subtitle:
                    'Attempts to start the main music player interface and dismiss recovery mode.',
                actionLabel: 'Launch Now',
                actionColor: AppThemeTokens.brandRuby,
                onTap: _attemptNormalLaunch,
              ),

              const SizedBox(height: 24),

              // Environment Details Footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(
                    AppThemeTokens.radiusSmall,
                  ),
                  border: Border.all(color: AppThemeTokens.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SYSTEM & RUNTIME DETAILS',
                      style: TextStyle(
                        color: AppThemeTokens.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMetaRow('Installed Version', _appVersion),
                    _buildMetaRow(
                      'Platform / OS',
                      kIsWeb
                          ? 'Web Browser'
                          : '${Platform.operatingSystem} (${Platform.operatingSystemVersion.split(' ')[0]})',
                    ),
                    _buildMetaRow(
                      'Zero-Black-Screen State',
                      'Active & Guarded',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );

    // If context doesn't have a Navigator or Directionality (e.g. from ErrorWidget.builder)
    if (Navigator.maybeOf(context) == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppThemeTokens.oledBackground,
        ),
        home: scaffoldContent,
      );
    }

    return scaffoldContent;
  }

  Widget _buildRecoveryActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String actionLabel,
    required Color actionColor,
    required VoidCallback onTap,
    bool isLoading = false,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeTokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppThemeTokens.radiusCard),
        border: Border.all(color: AppThemeTokens.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: actionColor.withValues(alpha: 0.18),
                      foregroundColor: actionColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: enabled ? onTap : null,
                    child: isLoading
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: actionColor,
                            ),
                          )
                        : Text(
                            actionLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppThemeTokens.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
