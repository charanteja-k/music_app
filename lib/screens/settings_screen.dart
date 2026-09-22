import 'dart:io';
import 'dart:ui';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/preferences_service.dart';
import '../services/music_service.dart';
import '../services/update_service.dart';
import '../services/notification_permission_service.dart';
import '../services/api_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _prefs = PreferencesService();
  final _musicService = MusicService();

  String _appVersion = '';
  String _buildNumber = '';
  bool _isCheckingUpdate = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPackageInfo();
    _checkNotificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationStatus();
    }
  }

  Future<void> _checkNotificationStatus() async {
    final granted = await NotificationPermissionService.isPermissionGranted();
    if (mounted) {
      setState(() => _notificationGranted = granted);
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {}
  }

  final List<Color> _availableColors = [
    const Color(0xFFFA2D48), // Apple Red
    const Color(0xFF1DB954), // Spotify Green
    const Color(0xFF9C27B0), // Purple
    const Color(0xFF2196F3), // Blue
    const Color(0xFFFF9800), // Orange
  ];

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E24).withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bedtime, color: Color(0xFFFA2D48), size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Sleep Timer',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (_musicService.isSleepTimerActive)
                      Text(
                        _musicService.sleepTimerLabel,
                        style: const TextStyle(color: Color(0xFFFA2D48), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_musicService.isSleepTimerActive)
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined, color: Colors.redAccent),
                    title: const Text('Turn Off Timer', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    subtitle: Text('Active: ${_musicService.sleepTimerLabel}', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    onTap: () {
                      _musicService.cancelSleepTimer();
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.white),
                  title: const Text('15 Minutes', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _musicService.startSleepTimer(const Duration(minutes: 15));
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.white),
                  title: const Text('30 Minutes', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _musicService.startSleepTimer(const Duration(minutes: 30));
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.white),
                  title: const Text('45 Minutes', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _musicService.startSleepTimer(const Duration(minutes: 45));
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.white),
                  title: const Text('1 Hour', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _musicService.startSleepTimer(const Duration(hours: 1));
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined, color: Colors.white),
                  title: const Text('End of Current Track', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _musicService.setStopAtEndOfTrack(true);
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCloudflareWorkerDialog(BuildContext context) {
    final controller = TextEditingController(text: _prefs.cloudflareWorkerUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: Colors.amber, size: 22),
            SizedBox(width: 10),
            Text('Edge Audio Worker', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Powers seamless iOS background playback & lock screen notifications without IP blocks.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://your-worker.workers.dev',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black38,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _prefs.setCloudflareWorkerUrl('');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reset to default Cloudflare worker'), backgroundColor: Colors.amber),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              _prefs.setCloudflareWorkerUrl(controller.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cloudflare Worker URL saved!'), backgroundColor: Colors.amber),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_prefs, _musicService]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            elevation: 0,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            children: [
              _buildSectionTitle('PLAYBACK'),
              _buildSettingsGroup([
                SwitchListTile(
                  title: const Text('Crossfade Tracks', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Smooth transition between songs', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _prefs.themeColor,
                  value: _prefs.crossfadeEnabled,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _prefs.themeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.graphic_eq_rounded, color: _prefs.themeColor, size: 20),
                  ),
                  onChanged: (val) {
                    _prefs.setCrossfade(val);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Crossfade set to ${val ? "On" : "Off"}'), backgroundColor: _prefs.themeColor));
                  },
                ),
                ListTile(
                  title: const Text('Sleep Timer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(_musicService.isSleepTimerActive ? 'Active: ${_musicService.sleepTimerLabel}' : 'Stop playback automatically', style: TextStyle(color: _musicService.isSleepTimerActive ? _prefs.themeColor : Colors.grey[400], fontSize: 13)),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _prefs.themeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.bedtime_rounded, color: _prefs.themeColor, size: 20),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: () => _showSleepTimerSheet(context),
                ),
              ]),
              const SizedBox(height: 16),

              _buildSectionTitle('PLAYER EXPERIENCE & VISUALS'),
              _buildSettingsGroup([
                // Artwork Style (Vinyl vs Album Card)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _prefs.artworkStyle == ArtworkStyle.vinyl
                          ? Icons.album_rounded
                          : Icons.crop_square_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  title: const Text('Artwork Style', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    _prefs.artworkStyle == ArtworkStyle.vinyl
                        ? 'Vinyl Turntable (Spinning Retro Player)'
                        : 'Modern Album Card (Sleek Squircle)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: SegmentedButton<ArtworkStyle>(
                    segments: const [
                      ButtonSegment(
                        value: ArtworkStyle.card,
                        icon: Icon(Icons.crop_square_rounded, size: 16),
                        label: Text('Card', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: ArtworkStyle.vinyl,
                        icon: Icon(Icons.album_outlined, size: 16),
                        label: Text('Vinyl', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_prefs.artworkStyle},
                    onSelectionChanged: (newSelection) {
                      HapticFeedback.selectionClick();
                      _prefs.setArtworkStyle(newSelection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return _prefs.themeColor;
                        }
                        return Colors.white10;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white70;
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                // Audio Scrubber Style (Waveform vs Classic)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _prefs.scrubberStyle == ScrubberStyle.waveform
                          ? Icons.graphic_eq_rounded
                          : Icons.linear_scale_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  title: const Text('Progress Line Style', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    _prefs.scrubberStyle == ScrubberStyle.waveform
                        ? 'Dynamic Waveform (Interactive Beats)'
                        : 'Classic Progress Bar (Apple Slider)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: SegmentedButton<ScrubberStyle>(
                    segments: const [
                      ButtonSegment(
                        value: ScrubberStyle.waveform,
                        icon: Icon(Icons.graphic_eq_rounded, size: 16),
                        label: Text('Wave', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: ScrubberStyle.classic,
                        icon: Icon(Icons.linear_scale_rounded, size: 16),
                        label: Text('Classic', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_prefs.scrubberStyle},
                    onSelectionChanged: (newSelection) {
                      HapticFeedback.selectionClick();
                      _prefs.setScrubberStyle(newSelection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return _prefs.themeColor;
                        }
                        return Colors.white10;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white70;
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              
              _buildSectionTitle('APPEARANCE & THEME STUDIO'),
              _buildThemeStudio(),
              const SizedBox(height: 16),

              _buildSectionTitle('AUDIO QUALITY'),
              _buildSettingsGroup([
                ListTile(
                  title: const Text('Streaming Quality', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Normal (128 kbps)', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.high_quality_rounded, color: Colors.blueAccent, size: 20),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: () {
                    // Placeholder for future implementation
                  },
                ),
              ]),
              const SizedBox(height: 16),

              _buildSectionTitle('SYSTEM & CONTROLS'),
              _buildSettingsGroup([
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: (_notificationGranted ? Colors.green : _prefs.themeColor).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Icon(_notificationGranted ? Icons.notifications_active_rounded : Icons.notifications_off_outlined, color: _notificationGranted ? Colors.greenAccent : _prefs.themeColor, size: 20),
                  ),
                  title: const Text('Lock Screen Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(_notificationGranted ? 'Active' : 'Tap to enable permissions', style: TextStyle(color: _notificationGranted ? Colors.greenAccent : Colors.amberAccent, fontSize: 13)),
                  trailing: _notificationGranted
                      ? const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20)
                      : ElevatedButton(
                          onPressed: () async {
                            await NotificationPermissionService.requestNotificationPermission(context);
                            _checkNotificationStatus();
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: _prefs.themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: const Text('Enable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                  onTap: () async {
                    await NotificationPermissionService.requestNotificationPermission(context);
                    _checkNotificationStatus();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: Colors.amber, size: 20),
                  ),
                  title: const Text('Edge Audio Worker (iOS/Web)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    _prefs.cloudflareWorkerUrl.isNotEmpty
                        ? _prefs.cloudflareWorkerUrl
                        : 'Default (${ApiConfig.defaultCloudflareWorkerUrl})',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: () => _showCloudflareWorkerDialog(context),
                ),
                ListTile(
                  title: const Text('Clear Search History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.history_rounded, color: Colors.redAccent, size: 20),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: () {
                    _prefs.clearSearchHistory();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Search history cleared'), backgroundColor: _prefs.themeColor));
                  },
                ),
              ]),
              const SizedBox(height: 16),

              _buildSectionTitle('STORAGE (${_prefs.cacheSizeMB.toInt()} MB Limit)'),
              _buildSettingsGroup([
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Slider(
                    activeColor: _prefs.themeColor,
                    inactiveColor: Colors.white10,
                    value: _prefs.cacheSizeMB,
                    min: 100,
                    max: 2000,
                    divisions: 19,
                    label: '${_prefs.cacheSizeMB.toInt()} MB',
                    onChanged: (val) => _prefs.setCacheSize(val),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              
              _buildSectionTitle('ABOUT'),
              _buildSettingsGroup([
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.system_update_alt_rounded, color: Colors.orangeAccent, size: 20),
                  ),
                  title: Text(
                    _appVersion.isEmpty
                        ? 'Music App'
                        : 'Version $_appVersion${_buildNumber.isNotEmpty ? " (Build $_buildNumber)" : ""}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(_isCheckingUpdate ? 'Checking for updates…' : 'Tap to check for new releases', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                  trailing: _isCheckingUpdate ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _prefs.themeColor)) : const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: _isCheckingUpdate ? null : _handleCheckForUpdates,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.bug_report_rounded, color: Colors.redAccent, size: 20),
                  ),
                  title: const Text('Report a Bug', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Found an issue? Let us know via Email', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                  onTap: _reportBug,
                ),
              ]),
              const SizedBox(height: 40),
            ],
          ),
        );
      }
    );
  }

  Future<void> _handleCheckForUpdates() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    try {
      final updateInfo = await UpdateService().checkForUpdate();
      if (!mounted) return;

      if (updateInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reach GitHub Releases. Please check your internet connection.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else if (!updateInfo.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're on the latest version (${updateInfo.tagName})! 🎉",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1DB954),
          ),
        );
      } else {
        _showUpdateSheet(context, updateInfo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update check failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _reportBug() async {
    final String subject = Uri.encodeComponent('Bug Report: DilSe Music App (v$_appVersion)');
    final String body = Uri.encodeComponent('Please describe the bug you encountered:\n\n\n\n--- App Info ---\nVersion: $_appVersion\nBuild: $_buildNumber\nOS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    final Uri emailLaunchUri = Uri.parse('mailto:balaamoghraj@gmail.com?subject=$subject&body=$body');

    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open your email client automatically.'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }


  void _showUpdateSheet(BuildContext context, AppUpdateInfo info) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UpdateModalSheet(
        info: info,
        themeColor: _prefs.themeColor,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0, bottom: 8.0, top: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    final List<Widget> separatedChildren = [];
    for (int i = 0; i < children.length; i++) {
      separatedChildren.add(children[i]);
      if (i < children.length - 1) {
        separatedChildren.add(const Divider(color: Colors.white10, height: 1, indent: 56));
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: separatedChildren,
      ),
    );
  }

  Widget _buildThemeStudio() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _availableColors.length,
        itemBuilder: (context, index) {
          final color = _availableColors[index];
          final isSelected = _prefs.themeColor.toARGB32() == color.toARGB32();
          return GestureDetector(
            onTap: () => _prefs.setThemeColor(color),
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? color : Colors.white10,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8)] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 60,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UpdateModalSheet extends StatefulWidget {
  final AppUpdateInfo info;
  final Color themeColor;

  const _UpdateModalSheet({required this.info, required this.themeColor});

  @override
  State<_UpdateModalSheet> createState() => _UpdateModalSheetState();
}

class _UpdateModalSheetState extends State<_UpdateModalSheet> {
  bool _isDownloading = false;
  int _downloadProgress = 0;
  String _statusText = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          setState(() {
            _errorMessage =
                'Permission needed to install packages. Please enable "Install unknown apps" for this app in Settings.';
          });
          return;
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusText = 'Connecting to download server…';
      _errorMessage = null;
    });

    try {
      UpdateService().startOtaUpdate(widget.info.downloadUrl).listen(
        (OtaEvent event) {
          if (!mounted) return;
          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                final parsed = int.tryParse(event.value ?? '0');
                if (parsed != null) _downloadProgress = parsed;
                _statusText = 'Downloading update… $_downloadProgress%';
                break;
              case OtaStatus.INSTALLING:
                _downloadProgress = 100;
                _statusText = 'Launching installer…';
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _errorMessage = 'An update download is already in progress.';
                _isDownloading = false;
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _errorMessage =
                    'Permission needed to install packages. Please allow "Install unknown apps" in Android settings.';
                _isDownloading = false;
                break;
              case OtaStatus.INTERNAL_ERROR:
                _errorMessage = 'Download failed: ${event.value ?? "Unknown error"}.';
                _isDownloading = false;
                break;
              default:
                break;
            }
          });
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Download error: $e';
              _isDownloading = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not start download: $e';
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24).withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white12),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.rocket_launch_rounded, color: widget.themeColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Update Available!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.info.tagName} • ${widget.info.formattedSize}',
                          style: TextStyle(
                            color: widget.themeColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                "What's New:",
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.changelog,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_isDownloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _statusText,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          '$_downloadProgress%',
                          style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress / 100.0 : null,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.themeColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Keep music_app open until installation starts',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Later', style: TextStyle(color: Colors.white60, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _startUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.download_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Update Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
