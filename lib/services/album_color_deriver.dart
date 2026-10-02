import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Represents a 3-color harmonious palette for ambient player backgrounds and accents.
class AlbumPalette {
  final Color dominant;
  final Color vibrant;
  final Color darkVibrant;

  const AlbumPalette({
    required this.dominant,
    required this.vibrant,
    required this.darkVibrant,
  });
}

/// Instant deterministic & cached color deriver for album artwork backgrounds.
/// Ensures that the player background immediately adapts according to the album shown
/// with zero delay, no GPU blur overhead, and beautiful contrast in dark mode.
class AlbumColorDeriver {
  static final Map<String, AlbumPalette> _cache = {};

  /// Retrieves an adaptive palette for the given song.
  /// Uses cached extracted palette if available, or derives an instant deterministic palette.
  static AlbumPalette getPalette(
    Video? song, {
    Color? fallbackDominant,
    Color? fallbackVibrant,
    Color? fallbackDarkVibrant,
  }) {
    if (song == null) {
      return const AlbumPalette(
        dominant: Color(0xFF1E1E2C),
        vibrant: Color(0xFFFA2D48),
        darkVibrant: Color(0xFF12121A),
      );
    }

    final id = song.id.value;

    // If caller provided an active extracted palette from MusicService, cache and use it
    if (fallbackDominant != null &&
        fallbackDominant != const Color(0xFF1E1E2C) &&
        fallbackDominant != const Color(0xFF000000)) {
      final p = AlbumPalette(
        dominant: fallbackDominant,
        vibrant: fallbackVibrant ?? fallbackDominant,
        darkVibrant: fallbackDarkVibrant ?? fallbackDominant,
      );
      _cache[id] = p;
      return p;
    }

    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    // Instant deterministic color mapping based on song metadata (Hard-coded color algorithm)
    // Curated with high saturation and deep luminance for rich ambient aura behind the player
    final hash =
        (song.title.hashCode ^ (song.author.hashCode * 31) ^ (id.hashCode * 17))
            .abs();
    final double hue = (hash % 360).toDouble();

    final dominant = HSLColor.fromAHSL(1.0, hue, 0.65, 0.22).toColor();
    final vibrant = HSLColor.fromAHSL(1.0, hue, 0.85, 0.52).toColor();
    final darkVibrant = HSLColor.fromAHSL(
      1.0,
      (hue + 45) % 360,
      0.58,
      0.12,
    ).toColor();

    final palette = AlbumPalette(
      dominant: dominant,
      vibrant: vibrant,
      darkVibrant: darkVibrant,
    );
    _cache[id] = palette;
    return palette;
  }

  /// Registers an asynchronously extracted palette for a track ID.
  static void registerExtractedPalette(
    String songId,
    Color dominant,
    Color vibrant,
    Color darkVibrant,
  ) {
    if (songId.isNotEmpty) {
      _cache[songId] = AlbumPalette(
        dominant: dominant,
        vibrant: vibrant,
        darkVibrant: darkVibrant,
      );
    }
  }

  /// Clears the palette cache if needed.
  static void clearCache() {
    _cache.clear();
  }

  /// Evaluates whether a color is black or perceptually indistinguishable from black on dark surfaces.
  static bool isBlackOrCloseToBlack(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();

    // 1. All RGB channels are under the near-black floor (~18% brightness)
    if (r < 48 && g < 48 && b < 48) return true;

    final luminance = color.computeLuminance();
    final hsl = HSLColor.fromColor(color);

    // 2. Extremely low photometric luminance (< 0.035) with low/medium saturation
    if (luminance < 0.035 && hsl.saturation < 0.40) return true;

    // 3. Low lightness with muted saturation (dark charcoal / murky gray)
    if (hsl.lightness < 0.16 && hsl.saturation < 0.25) return true;

    return false;
  }

  /// Computes the active lyric highlight color respecting the album cover.
  /// If the dominant color is black or close to black, uses [Colors.white].
  /// If the color is colored but dark, ensures it has enough lightness (>= 0.55)
  /// so it radiates legibly with its native hue on the dark player background.
  static Color resolveLyricHighlightColor(Color dominantColor) {
    if (isBlackOrCloseToBlack(dominantColor)) {
      return Colors.white;
    }

    final hsl = HSLColor.fromColor(dominantColor);
    if (hsl.lightness < 0.45) {
      return hsl.withLightness(0.55).toColor();
    }

    return dominantColor;
  }
}
