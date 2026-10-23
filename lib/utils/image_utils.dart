/// Utility methods for image URL upgrades and anti-blur resolution handling.
class ImageUtils {
  /// Upgrades low or standard resolution image URLs to crystal-clear high-res URLs:
  /// - JioSaavn: Upgrades `50x50` and `150x150` to `500x500`
  /// - YouTube: Upgrades `default.jpg` and `mqdefault.jpg` to `hqdefault.jpg`
  /// - Spotify CDN: Upgrades `ab67616d00001e02` (300x300) and `ab67616d00004851` (64x64) to `ab67616d0000b273` (640x640)
  static String toHighResUrl(String url) {
    if (url.isEmpty) return url;
    var result = url;

    // JioSaavn dimension replacements
    if (result.contains('50x50')) {
      result = result.replaceAll('50x50', '500x500');
    }
    if (result.contains('150x150')) {
      result = result.replaceAll('150x150', '500x500');
    }

    // YouTube thumbnails upgrades: avoid low-res default.jpg and mqdefault.jpg
    if (result.contains('i.ytimg.com') || result.contains('youtube.com')) {
      if (result.contains('/default.jpg')) {
        result = result.replaceAll('/default.jpg', '/hqdefault.jpg');
      } else if (result.contains('/mqdefault.jpg')) {
        result = result.replaceAll('/mqdefault.jpg', '/hqdefault.jpg');
      }
    } else {
      if (result.endsWith('/default.jpg')) {
        result = result.replaceAll('/default.jpg', '/hqdefault.jpg');
      } else if (result.endsWith('/mqdefault.jpg')) {
        result = result.replaceAll('/mqdefault.jpg', '/hqdefault.jpg');
      }
    }

    // Spotify CDN image hash upgrade to 640x640
    if (result.contains('i.scdn.co') || result.contains('spotifycdn.com')) {
      result = result
          .replaceAll('ab67616d00001e02', 'ab67616d0000b273')
          .replaceAll('ab67616d00004851', 'ab67616d0000b273');
    }

    return result;
  }
}
