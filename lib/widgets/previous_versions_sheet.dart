import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/data_snapshot_service.dart';
import '../services/preferences_service.dart';
import '../services/update_service.dart';

class PreviousVersionsSheet extends StatefulWidget {
  const PreviousVersionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PreviousVersionsSheet(),
    );
  }

  @override
  State<PreviousVersionsSheet> createState() => _PreviousVersionsSheetState();
}

class _PreviousVersionsSheetState extends State<PreviousVersionsSheet> {
  final UpdateService _updateService = UpdateService();
  final DataSnapshotService _snapshotService = DataSnapshotService();

  bool _isLoading = true;
  String? _errorMessage;
  List<GitHubReleaseItem> _releases = [];
  String _currentVersion = '';
  String _currentBuild = '';

  // Active download tracking
  String? _downloadingTag;
  int _downloadProgress = 0;
  String _downloadStatus = '';
  final Set<String> _expandedChangelogs = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentVersionAndReleases();
  }

  Future<void> _loadCurrentVersionAndReleases() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pkg = await PackageInfo.fromPlatform();
      _currentVersion = pkg.version;
      _currentBuild = pkg.buildNumber;

      final releases = await _updateService.fetchAllReleases(perPage: 30);
      if (!mounted) return;

      if (releases.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not retrieve releases from GitHub. Please check your internet connection.';
        });
      } else {
        setState(() {
          _releases = releases;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading releases: $e';
      });
    }
  }

  Future<void> _handleManualBackup() async {
    final result = await _snapshotService.createSafetySnapshot(
      triggerReason: 'Manual backup from Previous Versions sheet',
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Backup secured! (${result.playlistCount} playlists, ${result.likedSongsCount} likes)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1DB954),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: ${result.errorMessage}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleInstallRelease(GitHubReleaseItem release) async {
    if (_downloadingTag != null) return;
    if (!release.hasApk) {
      _launchInBrowser(release.htmlUrl);
      return;
    }

    if (kIsWeb || !Platform.isAndroid) {
      _launchInBrowser(release.apkDownloadUrl!);
      return;
    }

    // 1. Mandatory Data Shield: Capture pre-install atomic safety snapshot
    final snapshot = await _snapshotService.createSafetySnapshot(
      triggerReason: 'Pre-install snapshot for ${release.tagName}',
    );

    if (!mounted) return;

    final comparison = UpdateService.compareVersion(
      release.tagName,
      _currentVersion,
      _currentBuild,
    );

    // 2. If rolling back to an older version, present friendly reassurance
    if (comparison < 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF181818),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.shield_rounded, color: Color(0xFF1DB954), size: 24),
              SizedBox(width: 10),
              Text(
                'Data Protected',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are rolling back from $_currentVersion to ${release.tagName}.\n\n'
                '✅ Your playlists (${snapshot.playlistCount}), liked songs (${snapshot.likedSongsCount}), and listening history are safely backed up.\n\n'
                'Note: If Android blocks installing an older version over a newer one, simply uninstall DilSe and tap the downloaded APK. DilSe will automatically restore all your data on first launch.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: PreferencesService().themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Proceed with Install'),
            ),
          ],
        ),
      );

      if (proceed != true || !mounted) return;
    }

    // 3. Request Android install packages permission
    try {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Install permission required. Please enable "Install unknown apps" or download via browser.',
              ),
              backgroundColor: Colors.orangeAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
    } catch (_) {}

    // 4. Begin OTA Download
    setState(() {
      _downloadingTag = release.tagName;
      _downloadProgress = 0;
      _downloadStatus = 'Starting download...';
    });

    try {
      final cleanTag = release.tagName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final targetFilename = 'DilSe_$cleanTag.apk';

      _updateService
          .startOtaUpdate(release.apkDownloadUrl!, filename: targetFilename)
          .listen(
            (OtaEvent event) {
              if (!mounted) return;
              switch (event.status) {
                case OtaStatus.DOWNLOADING:
                  final p = int.tryParse(event.value ?? '0') ?? 0;
                  setState(() {
                    _downloadProgress = p;
                    _downloadStatus = 'Downloading ${release.tagName} ($p%)';
                  });
                  break;
                case OtaStatus.INSTALLING:
                  setState(() {
                    _downloadStatus = 'Launching package installer...';
                  });
                  break;
                case OtaStatus.ALREADY_RUNNING_ERROR:
                  setState(() {
                    _downloadingTag = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('A download is already in progress.'),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                  break;
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  setState(() {
                    _downloadingTag = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Storage / Install permission denied.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  break;
                case OtaStatus.INTERNAL_ERROR:
                default:
                  setState(() {
                    _downloadingTag = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('OTA error: ${event.value ?? 'Unknown'}'),
                      backgroundColor: Colors.redAccent,
                      action: SnackBarAction(
                        label: 'Browser',
                        textColor: Colors.amberAccent,
                        onPressed: () =>
                            _launchInBrowser(release.apkDownloadUrl!),
                      ),
                    ),
                  );
                  break;
              }
            },
            onError: (err) {
              if (!mounted) return;
              setState(() {
                _downloadingTag = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Download failed: $err'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingTag = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start download: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _launchInBrowser(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[PreviousVersionsSheet] Error launching browser: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = PreferencesService().themeColor;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Colors.white12, width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: themeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Release Archive',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentVersion.isEmpty
                            ? 'Install or rollback to any version'
                            : 'Current: v$_currentVersion • Zero-loss protected',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Manual Backup CTA
                IconButton(
                  tooltip: 'Create Safety Backup',
                  icon: const Icon(Icons.backup_rounded, color: Colors.white70),
                  onPressed: _handleManualBackup,
                ),

                // Close Button
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Body
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: themeColor,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Loading GitHub releases…',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.white38,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadCurrentVersionAndReleases,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _releases.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final release = _releases[index];
                      return _buildReleaseCard(release, themeColor);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseCard(GitHubReleaseItem release, Color themeColor) {
    final comparison = UpdateService.compareVersion(
      release.tagName,
      _currentVersion,
      _currentBuild,
    );
    final isCurrent = comparison == 0;
    final isNewer = comparison > 0;
    final isOlder = comparison < 0;
    final isDownloadingThis = _downloadingTag == release.tagName;
    final isExpanded = _expandedChangelogs.contains(release.tagName);

    return Container(
      decoration: BoxDecoration(
        color: isCurrent
            ? themeColor.withValues(alpha: 0.08)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? themeColor.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Tag, Badges, Date
          Row(
            children: [
              Text(
                release.tagName,
                style: TextStyle(
                  color: isCurrent ? themeColor : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),

              // Badges
              if (isCurrent)
                _buildBadge('CURRENT', themeColor, Colors.white)
              else if (isNewer)
                _buildBadge('NEWER', Colors.amberAccent, Colors.black)
              else if (isOlder)
                _buildBadge('PREVIOUS', Colors.grey[700]!, Colors.white70),

              if (release.isPrerelease) ...[
                const SizedBox(width: 6),
                _buildBadge('PRE-RELEASE', Colors.purpleAccent, Colors.white),
              ],

              const Spacer(),

              // Date
              if (release.publishedAt != null)
                Text(
                  '${release.publishedAt!.day}/${release.publishedAt!.month}/${release.publishedAt!.year}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
            ],
          ),

          // Release Name
          if (release.releaseName.isNotEmpty &&
              release.releaseName != release.tagName) ...[
            const SizedBox(height: 4),
            Text(
              release.releaseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Asset info & Action
          Row(
            children: [
              Icon(
                Icons.android_rounded,
                size: 15,
                color: release.hasApk ? Colors.greenAccent : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                release.formattedSize,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const Spacer(),

              // Changelog toggle
              if (release.changelog.isNotEmpty)
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedChangelogs.remove(release.tagName);
                      } else {
                        _expandedChangelogs.add(release.tagName);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          isExpanded ? 'Hide notes' : 'Notes',
                          style: TextStyle(color: themeColor, fontSize: 12),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: themeColor,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Browser direct link
              IconButton(
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                color: Colors.white54,
                tooltip: 'Open on GitHub',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _launchInBrowser(release.apkDownloadUrl ?? release.htmlUrl),
              ),

              const SizedBox(width: 4),

              // Primary Action Button
              if (isDownloadingThis)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: themeColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_downloadProgress%',
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Installed',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => _handleInstallRelease(release),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOlder
                        ? Colors.white.withValues(alpha: 0.12)
                        : themeColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOlder
                            ? Icons.history_rounded
                            : Icons.download_rounded,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOlder ? 'Switch to this' : 'Install',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Download Progress bar (if this item is actively downloading)
          if (isDownloadingThis) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress / 100.0 : null,
                minHeight: 5,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(themeColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _downloadStatus,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],

          // Expandable changelog notes
          if (isExpanded && release.changelog.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                release.changelog,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
