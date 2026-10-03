import 'preferences_service.dart';

class ApiConfig {
  static const String _defaultRenderUrl =
      'https://music-backend-4kel.onrender.com';
  static String? _huggingFaceUrl;

  /// Sets or updates the active Hugging Face backend Space URL.
  static void setHuggingFaceUrl(String? url) {
    if (url != null && url.trim().isNotEmpty) {
      final clean = url.trim();
      _huggingFaceUrl = clean.endsWith('/')
          ? clean.substring(0, clean.length - 1)
          : clean;
    } else {
      _huggingFaceUrl = null;
    }
  }

  /// Returns the configured Hugging Face URL if present.
  static String? get huggingFaceUrl => _huggingFaceUrl;

  /// Returns the base URL for the backend API.
  /// Priority:
  /// 1. Custom URL explicitly configured by the user in Settings
  /// 2. Active Hugging Face Space backend (if set)
  /// 3. Render cloud backend (fallback)
  static String get baseUrl {
    final customUrl = PreferencesService().customServerUrl;
    if (customUrl.isNotEmpty) {
      return customUrl.endsWith('/')
          ? customUrl.substring(0, customUrl.length - 1)
          : customUrl;
    }
    if (_huggingFaceUrl != null && _huggingFaceUrl!.isNotEmpty) {
      return _huggingFaceUrl!;
    }
    return _defaultRenderUrl;
  }

  static const String defaultCloudflareWorkerUrl =
      'https://dilse-edge-stream.charanteja-kondakalla030206.workers.dev';

  /// Returns the configured Cloudflare Worker base URL for direct audio streaming.
  /// Falls back to defaultCloudflareWorkerUrl if not explicitly configured.
  static String get cloudflareWorkerUrl {
    final customUrl = PreferencesService().cloudflareWorkerUrl;
    if (customUrl.isNotEmpty) {
      return customUrl.endsWith('/')
          ? customUrl.substring(0, customUrl.length - 1)
          : customUrl;
    }
    return defaultCloudflareWorkerUrl;
  }

  static Uri cloudflareStreamUri(String videoId) {
    return Uri.parse('$cloudflareWorkerUrl/stream?v=$videoId');
  }

  static String get _edgeBaseUrl {
    final customUrl = PreferencesService().customServerUrl;
    return customUrl.isNotEmpty
        ? (customUrl.endsWith('/')
              ? customUrl.substring(0, customUrl.length - 1)
              : customUrl)
        : cloudflareWorkerUrl;
  }

  /// Primary JioSaavn catalog search via Cloudflare Edge Worker (instant, zero cold start).
  static Uri jioSearchUri(String query, {int limit = 50, int page = 1}) {
    return Uri.parse(
      '$_edgeBaseUrl/jio/search?q=${Uri.encodeComponent(query)}&limit=$limit&page=$page',
    );
  }

  /// Secondary JioSaavn catalog search via Render cloud backend (fallback).
  static Uri jioBackendSearchUri(String query, {int limit = 20}) {
    return Uri.parse(
      '$baseUrl/jio/search?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
  }

  /// Single-track JioSaavn resolver — returns original album artwork, streamUrl, and album name.
  /// Used by the artwork enrichment pass to upgrade compilation covers to genuine album art.
  static Uri jioSingleTrackUri(String title, {String? artist}) {
    final customUrl = PreferencesService().cloudflareWorkerUrl;
    final base = customUrl.isNotEmpty
        ? (customUrl.endsWith('/')
              ? customUrl.substring(0, customUrl.length - 1)
              : customUrl)
        : defaultCloudflareWorkerUrl;
    final buffer = StringBuffer(
      '$base/jio?title=${Uri.encodeComponent(title)}',
    );
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    return Uri.parse(buffer.toString());
  }

  /// JioSaavn album search via Cloudflare Edge Worker.
  /// Returns a list of album metadata objects (id, title, artist, artwork, year, songCount).
  static Uri jioAlbumSearchUri(String query, {int limit = 12}) {
    return Uri.parse(
      '$_edgeBaseUrl/jio/albums?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
  }

  /// JioSaavn album detail — all songs with decrypted 320k stream URLs.
  static Uri jioAlbumDetailUri(String albumId) {
    return Uri.parse(
      '$_edgeBaseUrl/jio/album?id=${Uri.encodeComponent(albumId)}',
    );
  }

  /// Recommendations via Cloudflare Edge Worker (falls back to search on edge or Render).
  static Uri jioRecommendationsUri(
    String query, {
    String language = 'telugu',
    int limit = 20,
  }) {
    return Uri.parse(
      '$_edgeBaseUrl/jio/recommendations?q=${Uri.encodeComponent(query)}&language=${Uri.encodeComponent(language)}&limit=$limit',
    );
  }

  /// Autocomplete search suggestions via Cloudflare Edge Worker (< 100ms response).
  static Uri jioSuggestionsUri(String query, {int limit = 8}) {
    return Uri.parse(
      '$_edgeBaseUrl/jio/suggestions?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
  }

  /// Google YouTube Music radio automix via Cloudflare Edge Worker (< 150ms latency, zero cold start).
  static Uri radioUri(
    String videoId, {
    int limit = 30,
    String? title,
    String? artist,
  }) {
    final buffer = StringBuffer(
      '$_edgeBaseUrl/ytm/radio?v=$videoId&limit=$limit',
    );
    if (title != null && title.isNotEmpty) {
      buffer.write('&title=${Uri.encodeComponent(title)}');
    }
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    return Uri.parse(buffer.toString());
  }

  /// Cloudflare Edge Worker fallback for YouTube Music official song search (0ms cold start, CORS bypassed).
  static Uri ytmSearchUri(String query, {int limit = 20}) {
    return Uri.parse(
      '$_edgeBaseUrl/ytm/search?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
  }

  /// Secondary Render cloud backend radio fallback.
  static Uri renderRadioUri(
    String videoId, {
    int limit = 30,
    String? title,
    String? artist,
  }) {
    final buffer = StringBuffer('$baseUrl/radio?v=$videoId&limit=$limit');
    if (title != null && title.isNotEmpty) {
      buffer.write('&title=${Uri.encodeComponent(title)}');
    }
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    return Uri.parse(buffer.toString());
  }

  static Uri searchUri(String query, {int page = 1, int limit = 20}) {
    return Uri.parse(
      '$baseUrl/search?q=${Uri.encodeComponent(query)}&page=$page&limit=$limit',
    );
  }

  static Uri suggestionsUri(String query, {int limit = 8}) {
    return Uri.parse(
      '$baseUrl/suggestions?q=${Uri.encodeComponent(query)}&limit=$limit',
    );
  }

  static Uri streamProxyUri(String videoId) {
    return Uri.parse('$baseUrl/stream/$videoId.m4a');
  }

  static Uri streamUrlUri(String videoId) {
    return Uri.parse('$baseUrl/stream_url?v=$videoId');
  }

  static Uri nextCandidatesUri(
    String videoId, {
    int limit = 20,
    String? title,
    String? artist,
  }) {
    final buffer = StringBuffer(
      '$baseUrl/next_candidates?v=$videoId&limit=$limit',
    );
    if (title != null && title.isNotEmpty) {
      buffer.write('&title=${Uri.encodeComponent(title)}');
    }
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    return Uri.parse(buffer.toString());
  }

  static Uri trackFinishedUri() {
    return Uri.parse('$baseUrl/track_finished');
  }

  static Uri cacheInvalidateUri(String videoId) {
    return Uri.parse('$baseUrl/cache/$videoId');
  }

  static Uri preloadUri(String videoId) {
    return Uri.parse('$baseUrl/preload?v=$videoId');
  }

  static Uri clientLogUri() {
    return Uri.parse('$baseUrl/client_log');
  }

  static Uri cloudflareLyricsUri(
    String title, {
    String? artist,
    String? lang,
    int? duration,
  }) {
    final buffer = StringBuffer(
      '$cloudflareWorkerUrl/lyrics?title=${Uri.encodeComponent(title)}',
    );
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    if (lang != null && lang.isNotEmpty) {
      buffer.write('&lang=${Uri.encodeComponent(lang)}');
    }
    if (duration != null && duration > 0) {
      buffer.write('&duration=$duration');
    }
    return Uri.parse(buffer.toString());
  }

  static Uri backendLyricsUri(
    String title, {
    String? artist,
    String? lang,
    int? duration,
  }) {
    final buffer = StringBuffer(
      '$baseUrl/lyrics?title=${Uri.encodeComponent(title)}',
    );
    if (artist != null && artist.isNotEmpty) {
      buffer.write('&artist=${Uri.encodeComponent(artist)}');
    }
    if (lang != null && lang.isNotEmpty) {
      buffer.write('&lang=${Uri.encodeComponent(lang)}');
    }
    if (duration != null && duration > 0) {
      buffer.write('&duration=$duration');
    }
    return Uri.parse(buffer.toString());
  }
}
