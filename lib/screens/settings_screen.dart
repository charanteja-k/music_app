import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/preferences_service.dart';
import '../services/music_service.dart';
import '../services/update_service.dart';
import '../services/notification_permission_service.dart';
import '../services/bug_report_service.dart';
import '../widgets/interactive_update_dialog.dart';
import '../widgets/equalizer_bottom_sheet.dart';
import '../widgets/previous_versions_sheet.dart';
import '../layouts/desktop_layout_state.dart';
import 'recovery_shell_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
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

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF181818).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_musicService.isSleepTimerActive)
                    Text(
                      _musicService.sleepTimerLabel,
                      style: const TextStyle(
                        color: Color(0xFFFA2D48),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_musicService.isSleepTimerActive)
                ListTile(
                  leading: const Icon(
                    Icons.timer_off_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Turn Off Timer',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Active: ${_musicService.sleepTimerLabel}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  onTap: () {
                    _musicService.cancelSleepTimer();
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.white),
                title: const Text(
                  '15 Minutes',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _musicService.startSleepTimer(const Duration(minutes: 15));
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.white),
                title: const Text(
                  '30 Minutes',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _musicService.startSleepTimer(const Duration(minutes: 30));
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.white),
                title: const Text(
                  '45 Minutes',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _musicService.startSleepTimer(const Duration(minutes: 45));
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.white),
                title: const Text(
                  '1 Hour',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _musicService.startSleepTimer(const Duration(hours: 1));
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.music_note_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'End of Current Track',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _musicService.setStopAtEndOfTrack(true);
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showAudioQualityModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF181818).withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SafeArea(
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
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _prefs.themeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.high_quality_rounded,
                            color: _prefs.themeColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Streaming Audio Quality',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Select audio bitrate and dynamic range',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...AudioQualityPreset.values.map((preset) {
                      final isSelected = _prefs.audioQuality == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _prefs.setAudioQuality(preset);
                              setModalState(() {});
                              setState(() {});
                              if (_musicService.currentSong != null) {
                                unawaited(
                                  _musicService
                                      .reloadCurrentSongWithNewEngineSettings(),
                                );
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Audio Quality set to ${preset.label}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: const Color(0xFF181818),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _prefs.themeColor.withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? _prefs.themeColor.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.06),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected
                                        ? _prefs.themeColor
                                        : Colors.white38,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              preset.label,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? _prefs.themeColor
                                                          .withValues(
                                                            alpha: 0.3,
                                                          )
                                                    : Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                preset.badge,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          preset.description,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 12,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAudioFormatModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF181818).withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SafeArea(
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
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _prefs.themeColor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(10),
                            ),
                          ),
                          child: const Icon(
                            Icons.album_rounded,
                            color: Colors.black87,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Audio Format & Codec',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Select compression container and decoding engine',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...AudioFormatPreference.values.map((format) {
                      final isSelected = _prefs.audioFormat == format;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _prefs.setAudioFormat(format);
                              setModalState(() {});
                              setState(() {});
                              if (_musicService.currentSong != null) {
                                unawaited(
                                  _musicService
                                      .reloadCurrentSongWithNewEngineSettings(),
                                );
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Audio Format set to ${format.label}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: const Color(0xFF181818),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _prefs.themeColor.withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? _prefs.themeColor.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.06),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected
                                        ? _prefs.themeColor
                                        : Colors.white38,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              format.label,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? _prefs.themeColor
                                                          .withValues(
                                                            alpha: 0.3,
                                                          )
                                                    : Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                format.badge,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          format.description,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 12,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
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
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back to Home',
                    onPressed: () =>
                        DesktopLayoutState.setNavTab(DesktopNavTab.home),
                  ),
            title: const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 0,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            children: [
              _buildSectionTitle('PLAYBACK & AUDIO ENGINE'),
              _buildSettingsGroup([
                // Equalizer Tile
                ListTile(
                  title: const Text(
                    'Studio Equalizer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _prefs.equalizerEnabled
                        ? 'Preset: ${_prefs.equalizerPreset} • Active'
                        : 'Off',
                    style: TextStyle(
                      color: _prefs.equalizerEnabled
                          ? _prefs.themeColor
                          : Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () => EqualizerBottomSheet.show(context),
                ),

                const Divider(color: Colors.white10, height: 1, indent: 56),

                // Crossfade Switch
                SwitchListTile(
                  title: const Text(
                    'Crossfade Tracks',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Seamlessly merge audio between songs',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _prefs.themeColor,
                  value: _prefs.crossfadeEnabled,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  onChanged: (val) {
                    _prefs.setCrossfade(val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Crossfade set to ${val ? "On" : "Off"}'),
                        backgroundColor: _prefs.themeColor,
                      ),
                    );
                  },
                ),

                // Crossfade Duration Slider (if crossfade enabled)
                if (_prefs.crossfadeEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 4, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Merge Duration',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _prefs.themeColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_prefs.crossfadeSeconds} seconds',
                                style: TextStyle(
                                  color: _prefs.themeColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: _prefs.themeColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: _prefs.themeColor.withValues(
                              alpha: 0.2,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            value: _prefs.crossfadeSeconds.toDouble(),
                            min: 1,
                            max: 12,
                            divisions: 11,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              _prefs.setCrossfadeSeconds(val.round());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Smart Crossfade Switch
                  SwitchListTile(
                    title: const Text(
                      'Smart AI Merging',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Dynamically adapt crossfade duration to song tempo & energy',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: _prefs.themeColor,
                    value: _prefs.smartCrossfadeEnabled,
                    contentPadding: const EdgeInsets.only(left: 56, right: 16),
                    onChanged: (val) {
                      _prefs.setSmartCrossfade(val);
                    },
                  ),
                ],

                const Divider(color: Colors.white10, height: 1, indent: 56),

                // Fade-In on Start
                SwitchListTile(
                  title: const Text(
                    'Gentle Fade-In on Start',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Gently ramps up volume when a song starts fresh to prevent sudden blasts',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _prefs.themeColor,
                  value: _prefs.fadeInOnStartEnabled,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.volume_up_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  onChanged: (val) {
                    _prefs.setFadeInOnStart(val);
                  },
                ),

                const Divider(color: Colors.white10, height: 1, indent: 56),

                // Sleep Timer
                ListTile(
                  title: const Text(
                    'Sleep Timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _musicService.isSleepTimerActive
                        ? 'Active: ${_musicService.sleepTimerLabel}'
                        : 'Stop playback automatically',
                    style: TextStyle(
                      color: _musicService.isSleepTimerActive
                          ? _prefs.themeColor
                          : Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.bedtime_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
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
                  title: const Text(
                    'Artwork Style',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return _prefs.themeColor;
                        }
                        return Colors.white10;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
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
                  title: const Text(
                    'Progress Line Style',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return _prefs.themeColor;
                        }
                        return Colors.white10;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
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

              _buildSectionTitle('AUDIO ENGINE & FORMATS'),
              _buildSettingsGroup([
                // 1. Streaming Audio Quality (Studio Master 320k, High 160k, Balanced 128k, Data Saver 64k)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _prefs.themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.high_quality_rounded,
                      color: _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Streaming Audio Quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${_prefs.audioQuality.label} • ${_prefs.audioQuality.approxBitrate}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _prefs.themeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _prefs.themeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _prefs.audioQuality.badge,
                          style: TextStyle(
                            color: _prefs.themeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white30,
                      ),
                    ],
                  ),
                  onTap: _showAudioQualityModal,
                ),

                // 2. Audio Format & Codec (Auto, Opus WebM, AAC MP4, MP3 Universal)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.purpleAccent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Audio Format & Codec',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${_prefs.audioFormat.label} (${_prefs.audioFormat.shortLabel})',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.purpleAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _prefs.audioFormat.badge,
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white30,
                      ),
                    ],
                  ),
                  onTap: _showAudioFormatModal,
                ),

                // 3. Active Stream Engine Status / Hot-Reload
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (_musicService.currentSong != null
                                  ? Colors.greenAccent
                                  : Colors.blueGrey)
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _musicService.currentSong != null
                          ? Icons.bolt_rounded
                          : Icons.tune_rounded,
                      color: _musicService.currentSong != null
                          ? Colors.greenAccent
                          : Colors.blueGrey,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    _musicService.currentSong != null
                        ? 'Active Stream Engine'
                        : 'Audio Engine Pipeline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _musicService.currentSong != null
                        ? '${_musicService.activeStreamInfo.format} • ${_musicService.activeStreamInfo.qualityLabel} (${_musicService.activeStreamInfo.source})'
                        : 'Adaptive pipeline • JioSaavn 320k + YouTube Opus/AAC',
                    style: TextStyle(
                      color: _musicService.currentSong != null
                          ? Colors.greenAccent.shade200
                          : Colors.grey[400],
                      fontSize: 12,
                      fontWeight: _musicService.currentSong != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: _musicService.currentSong != null
                      ? IconButton(
                          tooltip: 'Hot-swap stream to current settings',
                          icon: const Icon(
                            Icons.sync_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Reloading stream with active engine settings...',
                                ),
                                duration: Duration(milliseconds: 1200),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            await _musicService
                                .reloadCurrentSongWithNewEngineSettings();
                          },
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ONLINE',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
              ]),
              const SizedBox(height: 16),

              _buildSectionTitle('SYSTEM & CONTROLS'),
              _buildSettingsGroup([
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (_notificationGranted
                                  ? Colors.green
                                  : _prefs.themeColor)
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _notificationGranted
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      color: _notificationGranted
                          ? Colors.greenAccent
                          : _prefs.themeColor,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Lock Screen Controls',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _notificationGranted
                        ? 'Active'
                        : 'Tap to enable permissions',
                    style: TextStyle(
                      color: _notificationGranted
                          ? Colors.greenAccent
                          : Colors.amberAccent,
                      fontSize: 13,
                    ),
                  ),
                  trailing: _notificationGranted
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.greenAccent,
                          size: 20,
                        )
                      : ElevatedButton(
                          onPressed: () async {
                            await NotificationPermissionService.requestNotificationPermission(
                              context,
                            );
                            _checkNotificationStatus();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _prefs.themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Enable',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                  onTap: () async {
                    await NotificationPermissionService.requestNotificationPermission(
                      context,
                    );
                    _checkNotificationStatus();
                  },
                ),
                ListTile(
                  title: const Text(
                    'Clear Search History',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () {
                    _prefs.clearSearchHistory();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Search history cleared'),
                        backgroundColor: _prefs.themeColor,
                      ),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 16),

              _buildSectionTitle(
                'STORAGE (${_prefs.cacheSizeMB.toInt()} MB Limit)',
              ),
              _buildSettingsGroup([
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
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
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    _appVersion.isEmpty
                        ? 'Music App'
                        : 'Version $_appVersion${_buildNumber.isNotEmpty ? " (Build $_buildNumber)" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _isCheckingUpdate
                        ? 'Checking for updates…'
                        : 'Tap to check for new releases',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: _isCheckingUpdate
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _prefs.themeColor,
                          ),
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white30,
                        ),
                  onTap: _isCheckingUpdate ? null : _handleCheckForUpdates,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Previous Versions',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Install or rollback to any GitHub release',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () => PreviousVersionsSheet.show(context),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.amberAccent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Safe Mode & Recovery Shell',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Tools for rollback, snapshot restore, and cache purge',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RecoveryShellScreen(),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text(
                    'Shake to Report Bug',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Shake phone 3 times anytime to capture diagnostics and submit a bug',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _prefs.themeColor,
                  value: BugReportService.instance.isShakeEnabled,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFA2D48).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.vibration_rounded,
                      color: Color(0xFFFA2D48),
                      size: 20,
                    ),
                  ),
                  onChanged: (val) async {
                    await BugReportService.instance.setShakeEnabled(val);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.bug_report_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Report a Bug',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Submit issue with snapshot & diagnostics',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () {
                    BugReportService.instance.triggerReportModal(context);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFA2D48).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      color: Color(0xFFFA2D48),
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Crafted with ❤️ by Charan Teja',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'github.com/charanteja-k',
                    style: TextStyle(color: _prefs.themeColor, fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.white30,
                    size: 18,
                  ),
                  onTap: () async {
                    final uri = Uri.parse('https://github.com/charanteja-k');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      color: Colors.blueAccent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Open Source & Disclaimer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Non-profit educational music streaming',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white30,
                  ),
                  onTap: () => _showDisclaimerDialog(context),
                ),
              ]),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  void _showDisclaimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.verified_user_rounded,
              color: Colors.blueAccent,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Educational Disclaimer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DilSe is a free, open-source application built strictly for educational, personal, and research purposes.\n\n'
                '• No Audio Hosting: DilSe does not host, store, or cache any copyrighted audio or video media on any central or private servers. All streams are resolved directly on-device from publicly accessible endpoints.\n\n'
                '• Non-Commercial: DilSe contains no advertisements, no tracking, and no monetization. It was created to provide students and music lovers with clean, ad-free access.\n\n'
                '• Copyright: All trademarks, song titles, artist names, album art, and audio recordings belong to their respective copyright holders.\n\n'
                'Inquiries or requests can be sent to: charanteja.kondakalla030206@gmail.com',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
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
            content: Text(
              'Could not reach GitHub Releases. Please check your internet connection.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else if (!updateInfo.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
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
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  void _showUpdateSheet(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => InteractiveUpdateDialog(info: info),
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
        separatedChildren.add(
          const Divider(color: Colors.white10, height: 1, indent: 56),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Material(
        color: const Color(0xFF181818),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        child: Column(children: separatedChildren),
      ),
    );
  }

  Widget _buildThemeStudio() {
    final palette = PreferencesService.organicPalette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Organic Accent Palette',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 3.0,
                ),
                decoration: BoxDecoration(
                  color: _prefs.themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _prefs.themeColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  palette.firstWhere(
                        (p) =>
                            (p['color'] as Color).toARGB32() ==
                            _prefs.themeColor.toARGB32(),
                        orElse: () => {'name': 'Custom'},
                      )['name']
                      as String,
                  style: TextStyle(
                    color: _prefs.themeColor,
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Curated botanical and mineral solid tones. Zero synthetic neon glare.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.0,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: palette.length,
              itemBuilder: (context, index) {
                final item = palette[index];
                final color = item['color'] as Color;
                final name = item['name'] as String;
                final subtitle = item['subtitle'] as String;
                final isSelected =
                    _prefs.themeColor.toARGB32() == color.toARGB32();

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _prefs.setThemeColor(color);
                  },
                  child: Container(
                    width: 112,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? color.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.05),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : Colors.transparent,
                              width: 2.0,
                            ),
                          ),
                          child: isSelected
                              ? const Center(
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 11.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 9.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
