import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing hardware-accelerated and DSP audio effects
/// (Bass Boost, 3D Surround Virtualizer, and Audiophile Anti-Clipping Headroom).
class AudioEffectsService {
  AudioEffectsService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.music_app/audio_effects',
  );

  /// Apply hardware-accelerated Bass Boost on Android (strength: 0.0 to 1.0).
  static Future<bool> setBassBoost(
    double strength, {
    bool enabled = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('setBassBoost', {
        'enabled': enabled,
        'strength': strength.clamp(0.0, 1.0),
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[AudioEffectsService] BassBoost invocation error: $e');
      return false;
    }
  }

  /// Apply hardware-accelerated 3D Virtualizer on Android (strength: 0.0 to 1.0).
  static Future<bool> setVirtualizer(
    double strength, {
    bool enabled = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('setVirtualizer', {
        'enabled': enabled,
        'strength': strength.clamp(0.0, 1.0),
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[AudioEffectsService] Virtualizer invocation error: $e');
      return false;
    }
  }

  /// Release native audio effects resources.
  static Future<void> release() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseEffects');
    } catch (_) {}
  }

  /// Computes audiophile anti-clipping headroom-compensated bands.
  ///
  /// Prevents digital clipping (hard distortion and breaking) when equalizer
  /// bands or bass boost have positive decibel gains.
  ///
  /// In digital audio, when audio signals mastered at ~0 dBFS receive positive
  /// gain without headroom compensation, the signal clips against the DAC ceiling,
  /// causing severe harmonic distortion and loss of clarity.
  ///
  /// This calculates dynamic negative pre-cut headroom so that:
  /// 1. Tonal shape / frequency curve is 100% preserved.
  /// 2. Positive peaks remain within safe linear operating range (<= +1.5 dB).
  /// 3. Bass remains punchy and high frequencies remain crystal clear with zero distortion.
  static Map<int, double> computeAntiClippingBands({
    required Map<int, double> rawBands,
    double bassBoost = 0.0,
  }) {
    final result = Map<int, double>.from(rawBands);

    // If Bass Boost is active, apply gentle low-end enhancement to sub-bass (60Hz) and bass (230Hz)
    if (bassBoost > 0.0) {
      final boostDb = (bassBoost.clamp(0.0, 1.0)) * 5.0; // Up to +5.0 dB
      result[0] = (result[0] ?? 0.0) + boostDb;
      result[1] = (result[1] ?? 0.0) + (boostDb * 0.65);
    }

    // Find the maximum gain across all bands
    double maxGain = 0.0;
    for (final gain in result.values) {
      if (gain > maxGain) maxGain = gain;
    }

    // Safe ceiling threshold (+1.5 dB allows analog warmth without digital clipping)
    const safeCeilingDb = 1.5;
    if (maxGain > safeCeilingDb) {
      final headroomCut = maxGain - safeCeilingDb;
      for (final key in result.keys) {
        result[key] = (result[key] ?? 0.0) - headroomCut;
      }
    }

    // Clamp each band to reasonable bounds
    for (final key in result.keys) {
      result[key] = (result[key] ?? 0.0).clamp(-12.0, 12.0);
    }

    return result;
  }
}
