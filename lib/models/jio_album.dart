/// Represents a JioSaavn movie or soundtrack album.
class JioAlbum {
  final String id;
  final String title;
  final String artist;
  final String artwork;
  final String year;
  final int songCount;
  final String language;
  final String type;

  /// Song list — only populated after calling [MusicService.fetchAlbumTracks].
  final List<Map<String, dynamic>> songs;

  const JioAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.artwork,
    required this.year,
    required this.songCount,
    required this.language,
    this.type = 'album',
    this.songs = const [],
  });

  factory JioAlbum.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    final List<Map<String, dynamic>> songs = rawSongs is List
        ? rawSongs.map((s) => Map<String, dynamic>.from(s as Map)).toList()
        : [];
    final count = json['songCount'] as int? ?? songs.length;
    final rawType =
        json['type'] as String? ?? (count <= 1 ? 'single' : 'album');
    final artwork = json['artwork'] as String? ?? '';
    final rawTitle = json['title'] as String? ?? 'Unknown Album';
    final title = formatAlbumTitle(rawTitle, artwork);
    final rawArtist = json['artist'] as String? ?? 'Soundtrack';
    final artist = rawArtist.trim().isEmpty ? 'Soundtrack' : rawArtist;
    return JioAlbum(
      id: json['id']?.toString() ?? '',
      title: title,
      artist: artist,
      artwork: artwork,
      year: json['year']?.toString() ?? '',
      songCount: count,
      language: (json['language'] as String? ?? '').toLowerCase(),
      type: rawType,
      songs: songs,
    );
  }

  /// Extracts Romanized album title from artwork URL slug if title contains Indic script.
  static String formatAlbumTitle(String rawTitle, String artwork) {
    final title = rawTitle.trim();
    if (RegExp(r'[\u0900-\u0D7F]').hasMatch(title) && artwork.isNotEmpty) {
      final match = RegExp(
        r'/([A-Za-z0-9\-]+)-(?:Hindi|Telugu|Tamil|Kannada|Malayalam|Punjabi|Bengali|Bhojpuri|Gujarati|Marathi)-\d{4}-',
        caseSensitive: false,
      ).firstMatch(artwork);
      if (match != null && match.group(1) != null) {
        final slug = match.group(1)!;
        final words = slug
            .split('-')
            .where((w) => w.isNotEmpty)
            .map((w) {
              if (w.length <= 1) return w.toUpperCase();
              return '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
        if (words.isNotEmpty) return words;
      }
    }
    return title.isEmpty ? 'Unknown Album' : title;
  }

  JioAlbum copyWith({
    List<Map<String, dynamic>>? songs,
    int? songCount,
    String? type,
    String? artwork,
  }) {
    return JioAlbum(
      id: id,
      title: title,
      artist: artist,
      artwork: artwork ?? this.artwork,
      year: year,
      songCount: songCount ?? this.songCount,
      language: language,
      type: type ?? this.type,
      songs: songs ?? this.songs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artwork': artwork,
    'year': year,
    'songCount': songCount,
    'language': language,
    'type': type,
    'songs': songs,
  };

  @override
  String toString() =>
      'JioAlbum($id, "$title", $year, $type, ${songs.length} songs)';
}
