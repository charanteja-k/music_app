import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/audio_effects_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    prefs.resetForTesting();
    await prefs.init();
  });

  group('AudioEffectsService Anti-Clipping Headroom Tests', () {
    test('Flat bands remain untouched with 0 dB max headroom', () {
      final raw = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0};
      final result = AudioEffectsService.computeAntiClippingBands(
        rawBands: raw,
      );

      for (int i = 0; i < 5; i++) {
        expect(result[i], closeTo(0.0, 0.001));
      }
    });

    test(
      'Positive preset (+7dB) applies headroom compensation to prevent digital clipping',
      () {
        // Bass Boost preset: {0: 7.0, 1: 4.5, 2: 0.5, 3: 0.0, 4: -1.0}
        final raw = {0: 7.0, 1: 4.5, 2: 0.5, 3: 0.0, 4: -1.0};
        final result = AudioEffectsService.computeAntiClippingBands(
          rawBands: raw,
        );

        // Maximum gain should never exceed safe ceiling of +1.5 dB
        double maxGain = -100.0;
        for (final gain in result.values) {
          if (gain > maxGain) maxGain = gain;
        }
        expect(maxGain, closeTo(1.5, 0.001));

        // Relative difference between sub-bass (band 0) and treble (band 4) is 100% preserved
        // (7.0 - (-1.0) = 8.0 dB)
        final rawDiff = raw[0]! - raw[4]!;
        final resultDiff = result[0]! - result[4]!;
        expect(resultDiff, closeTo(rawDiff, 0.001));
      },
    );

    test(
      'Bass Boost slider dynamically enhances low-end bands with anti-clipping ceiling',
      () {
        final raw = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0};
        final result = AudioEffectsService.computeAntiClippingBands(
          rawBands: raw,
          bassBoost: 0.8, // 80% bass boost
        );

        // Low bands (60Hz & 230Hz) must be higher than upper bands
        expect(result[0]! > result[2]!, isTrue);
        expect(result[1]! > result[2]!, isTrue);

        // Total peak must not clip above safe ceiling (+1.5 dB)
        double maxGain = -100.0;
        for (final gain in result.values) {
          if (gain > maxGain) maxGain = gain;
        }
        expect(maxGain, closeTo(1.5, 0.001));
      },
    );

    test(
      'PreferencesService updates bassBoost and virtualizer values and syncs',
      () async {
        final prefs = PreferencesService();

        expect(prefs.bassBoost, equals(0.0));
        expect(prefs.virtualizer, equals(0.0));

        await prefs.setBassBoost(0.65);
        expect(prefs.bassBoost, equals(0.65));

        await prefs.setVirtualizer(0.40);
        expect(prefs.virtualizer, equals(0.40));
      },
    );
  });
}
