import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight, battery-friendly service for synchronizing active playback metadata,
/// dynamic dominant color, seek progress, and intelligent top playlists to the native
/// Android Home Screen Widget via MethodChannel and SharedPreferences.
///
/// Strict architectural constraints:
/// - 0 continuous timers / periodic polling.
/// - Event-driven invocations on track change, position milestone, and play/pause toggle only.
/// - Android-only execution guard with web and iOS fallbacks.
class WidgetUpdateService {
  static final WidgetUpdateService _instance = WidgetUpdateService._internal();
  factory WidgetUpdateService() => _instance;
  WidgetUpdateService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.example.music_app/widget',
  );

  String? _lastTrackId;
  bool? _lastIsPlaying;
  int? _lastPositionBucket;

  @visibleForTesting
  static MethodChannel get channel => _channel;

  /// Registers callbacks to process intents dispatched from the native widget
  void initWidgetActionHandler({
    required VoidCallback onToggleShuffle,
    required VoidCallback onToggleRepeat,
    required Future<void> Function(int index, String id, String query)
    onPlayPlaylist,
    Future<void> Function(Duration position)? onSeekTo,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'toggleShuffle':
          onToggleShuffle();
          break;
        case 'toggleRepeat':
          onToggleRepeat();
          break;
        case 'seekTo':
          final args = call.arguments as Map?;
          final posMs = args?['positionMs'] as int? ?? 0;
          if (onSeekTo != null) {
            await onSeekTo(Duration(milliseconds: posMs));
          }
          break;
        case 'playPlaylist':
          final args = call.arguments as Map?;
          final index = args?['index'] as int? ?? 0;
          final id = args?['id'] as String? ?? '';
          final query = args?['query'] as String? ?? '';
          await onPlayPlaylist(index, id, query);
          break;
      }
    });
  }

  static String toTitleCase(String text) {
    if (text.trim().isEmpty) return text;
    return text
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((word) {
          if (word.length <= 1) return word.toUpperCase();
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  static String formatDuration(Duration? d) {
    if (d == null || d.inSeconds <= 0) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artworkPath,
    String? trackId,
    int? dominantColor,
    Duration? position,
    Duration? duration,
    bool isShuffle = false,
    bool isRepeat = false,
    List<Map<String, String>>? topPlaylists,
  }) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    // Deduplicate high-frequency progress spam by bucketing progress into ~2-second intervals
    final positionSeconds = position?.inSeconds ?? 0;
    final positionBucket = positionSeconds ~/ 2;

    if (_lastTrackId == trackId &&
        _lastIsPlaying == isPlaying &&
        _lastPositionBucket == positionBucket) {
      return;
    }
    _lastTrackId = trackId;
    _lastIsPlaying = isPlaying;
    _lastPositionBucket = positionBucket;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_title', toTitleCase(title));
      await prefs.setString('widget_artist', toTitleCase(artist));
      await prefs.setBool('widget_is_playing', isPlaying);
      await prefs.setBool('widget_is_shuffle', isShuffle);
      await prefs.setBool('widget_is_repeat', isRepeat);

      if (artworkPath != null && artworkPath.isNotEmpty) {
        await prefs.setString('widget_artwork_path', artworkPath);
      }

      if (dominantColor != null) {
        await prefs.setInt('widget_dominant_color', dominantColor);
      }

      final posMs = position?.inMilliseconds ?? 0;
      final durMs = duration?.inMilliseconds ?? 0;
      await prefs.setInt('widget_position_ms', posMs);
      await prefs.setInt('widget_duration_ms', durMs);
      await prefs.setString('widget_position_text', formatDuration(position));
      await prefs.setString('widget_duration_text', formatDuration(duration));

      if (topPlaylists != null && topPlaylists.isNotEmpty) {
        await prefs.setString(
          'widget_top_playlists_json',
          json.encode(topPlaylists),
        );
      }

      await _channel.invokeMethod('updateWidget');
    } catch (e) {
      debugPrint('[WidgetUpdateService] Error updating widget: $e');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _lastTrackId = null;
    _lastIsPlaying = null;
    _lastPositionBucket = null;
  }
}
