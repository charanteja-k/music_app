import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preferences_service.dart';

class EqualizerBottomSheet extends StatefulWidget {
  const EqualizerBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const EqualizerBottomSheet(),
    );
  }

  @override
  State<EqualizerBottomSheet> createState() => _EqualizerBottomSheetState();
}

class _EqualizerBottomSheetState extends State<EqualizerBottomSheet> {
  final PreferencesService _prefs = PreferencesService();

  static const List<String> _bandLabels = [
    '60 Hz',
    '230 Hz',
    '910 Hz',
    '3.6 kHz',
    '14 kHz',
  ];
  static const List<String> _bandSubtitles = [
    'Sub-Bass',
    'Bass',
    'Mids',
    'Presence',
    'Treble',
  ];

  static const Map<String, Map<int, double>> _presets = {
    'Flat': {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0},
    'Bass Boost': {0: 7.0, 1: 4.5, 2: 0.5, 3: 0.0, 4: -1.0},
    'Vocal Clarity': {0: -2.0, 1: 1.0, 2: 5.5, 3: 4.0, 4: 2.0},
    'Electronic': {0: 6.0, 1: 3.5, 2: 0.0, 3: 2.5, 4: 4.5},
    'Rock': {0: 4.5, 1: 2.0, 2: -1.5, 3: 3.0, 4: 5.0},
    'Pop': {0: -1.0, 1: 2.0, 2: 4.5, 3: 2.0, 4: -1.0},
    'Hip-Hop': {0: 7.0, 1: 5.0, 2: -1.0, 3: 1.5, 4: 2.5},
    'Acoustic': {0: 3.5, 1: 2.0, 2: 2.5, 3: 3.5, 4: 3.0},
    'Classical': {0: 4.0, 1: 2.5, 2: -1.0, 3: 2.5, 4: 4.0},
  };

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _prefs.themeColor;
    final isEnabled = _prefs.equalizerEnabled;
    final currentPreset = _prefs.equalizerPreset;
    final bands = _prefs.equalizerBands;
    final bassBoost = _prefs.bassBoost;
    final virtualizer = _prefs.virtualizer;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grabber handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: themeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audio Equalizer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '5-Band Spatial Studio EQ',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              Switch.adaptive(
                value: isEnabled,
                activeTrackColor: themeColor,
                activeThumbColor: Colors.white,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  _prefs.setEqualizerEnabled(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Presets Horizontal Selector
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                ..._presets.keys.map((presetName) {
                  final isSelected = isEnabled && currentPreset == presetName;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(presetName),
                      selected: isSelected,
                      selectedColor: themeColor,
                      backgroundColor: const Color(0xFF1E1E2C),
                      disabledColor: const Color(0xFF181818),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: isSelected ? themeColor : Colors.white10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      onSelected: isEnabled
                          ? (sel) {
                              if (sel) {
                                HapticFeedback.selectionClick();
                                _prefs.setEqualizerPreset(
                                  presetName,
                                  _presets[presetName]!,
                                );
                              }
                            }
                          : null,
                    ),
                  );
                }),
                if (currentPreset == 'Custom') ...[
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: true,
                    selectedColor: themeColor,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    side: BorderSide(color: themeColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    onSelected: (_) {},
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5-Band Graphic Vertical Sliders
          Opacity(
            opacity: isEnabled ? 1.0 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (bandIdx) {
                  final gain = bands[bandIdx] ?? 0.0;
                  final gainDisplay = gain > 0
                      ? '+${gain.toStringAsFixed(1)}'
                      : gain.toStringAsFixed(1);

                  return Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$gainDisplay dB',
                          style: TextStyle(
                            color: gain.abs() > 0.1
                                ? themeColor
                                : Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 140,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: themeColor,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: themeColor.withValues(alpha: 0.2),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                              ),
                              child: Slider(
                                value: gain,
                                min: -12.0,
                                max: 12.0,
                                onChanged: isEnabled
                                    ? (newGain) {
                                        _prefs.setEqualizerBand(
                                          bandIdx,
                                          newGain,
                                        );
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _bandLabels[bandIdx],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _bandSubtitles[bandIdx],
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Spatial Enhancements (Bass Boost & 3D Virtualizer)
          Opacity(
            opacity: isEnabled ? 1.0 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  // Bass Boost
                  Row(
                    children: [
                      const Icon(
                        Icons.speaker_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Bass Boost',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(bassBoost * 100).toInt()}%',
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: themeColor,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                    ),
                    child: Slider(
                      value: bassBoost,
                      min: 0.0,
                      max: 1.0,
                      onChanged: isEnabled
                          ? (val) {
                              _prefs.setBassBoost(val);
                            }
                          : null,
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 12),

                  // 3D Virtualizer
                  Row(
                    children: [
                      const Icon(
                        Icons.surround_sound_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '3D Virtualizer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(virtualizer * 100).toInt()}%',
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: themeColor,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                    ),
                    child: Slider(
                      value: virtualizer,
                      min: 0.0,
                      max: 1.0,
                      onChanged: isEnabled
                          ? (val) {
                              _prefs.setVirtualizer(val);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Reset button
          Center(
            child: TextButton.icon(
              icon: const Icon(
                Icons.restart_alt_rounded,
                size: 16,
                color: Colors.white54,
              ),
              label: const Text(
                'Reset to Flat',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onPressed: isEnabled
                  ? () {
                      HapticFeedback.mediumImpact();
                      _prefs.setEqualizerPreset('Flat', _presets['Flat']!);
                      _prefs.setBassBoost(0.0);
                      _prefs.setVirtualizer(0.0);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
