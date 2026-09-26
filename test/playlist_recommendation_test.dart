import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/canonical_song_dedup.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  group('Playlist Multi-Artist Recommendation Tests', () {
    Video createMockSong(String id, String title, String author) {
      return Video(
        VideoId(id),
        title,
        author,
        ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
        DateTime.now(),
        '',
        null,
        '',
        null,
        ThumbnailSet(id),
        null,
        Engagement(0, null, null),
        false,
      );
    }

    List<String> extractArtistsFromSongs(List<Video> songs) {
      final Map<String, int> frequency = {};
      for (final song in songs) {
        final parts = song.author.split(RegExp(r'[,;&/]|(?:\b(?:feat\.?|ft\.?)\b)', caseSensitive: false));
        for (final rawPart in parts) {
          final cleaned = CanonicalSongDedup.cleanArtist(rawPart);
          if (cleaned.isNotEmpty && cleaned.length >= 2) {
            frequency[cleaned] = (frequency[cleaned] ?? 0) + 1;
          }
        }
      }
      final sorted = frequency.keys.toList()
        ..sort((a, b) => frequency[b]!.compareTo(frequency[a]!));
      return sorted;
    }

    test('Extracts all distinct artists across diverse playlist songs and discards record labels', () {
      final playlist = [
        createMockSong('rjkrTnma001', 'Song 1', 'Anirudh Ravichander, Arijit Singh'),
        createMockSong('rjkrTnma002', 'Song 2', 'Sid Sriram feat. Shreya Ghoshal'),
        createMockSong('rjkrTnma003', 'Song 3', 'T-Series'),
        createMockSong('rjkrTnma004', 'Song 4', 'Aditya Music'),
        createMockSong('rjkrTnma005', 'Song 5', 'Anirudh Ravichander'),
        createMockSong('rjkrTnma006', 'Song 6', 'Pritam / Arijit Singh'),
      ];

      final artists = extractArtistsFromSongs(playlist);

      expect(artists.contains('anirudh ravichander'), isTrue);
      expect(artists.contains('arijit singh'), isTrue);
      expect(artists.contains('sid sriram'), isTrue);
      expect(artists.contains('shreya ghoshal'), isTrue);
      expect(artists.contains('pritam'), isTrue);
      expect(artists.contains('t-series'), isFalse); // Record label stripped
      expect(artists.contains('aditya music'), isFalse); // Record label stripped

      // Anirudh should be first since he appeared most frequently
      expect(artists.first, 'anirudh ravichander');
    });

    test('Round-robin interleaves candidate tracks across multiple artists preventing single-artist domination', () {
      final artistA = [
        createMockSong('rjkrTnma011', 'Hukum Tiger Ka Hukum', 'Anirudh Ravichander'),
        createMockSong('rjkrTnma012', 'Arabic Kuthu Halamithi', 'Anirudh Ravichander'),
        createMockSong('rjkrTnma013', 'Chaleya Zinda Banda', 'Anirudh Ravichander'),
      ];
      final artistB = [
        createMockSong('rjkrTnma021', 'Inkem Inkem Inkem Kaavaale', 'Sid Sriram'),
        createMockSong('rjkrTnma022', 'Samajavaragamana Ala Vaikunthapurramuloo', 'Sid Sriram'),
      ];
      final artistC = [
        createMockSong('rjkrTnma031', 'Deewani Mastani Bajirao', 'Shreya Ghoshal'),
        createMockSong('rjkrTnma032', 'Sun Raha Hai Na Tu Aashiqui', 'Shreya Ghoshal'),
        createMockSong('rjkrTnma033', 'Ghoomar Padmavat', 'Shreya Ghoshal'),
      ];

      final artistTrackLists = [artistA, artistB, artistC];
      final candidates = <Video>[];

      int maxLen = 0;
      for (final list in artistTrackLists) {
        if (list.length > maxLen) maxLen = list.length;
      }
      for (int i = 0; i < maxLen; i++) {
        for (final list in artistTrackLists) {
          if (i < list.length) {
            candidates.add(list[i]);
          }
        }
      }

      // Check interleaving: A1, B1, C1, A2, B2, C2, A3, C3
      expect(candidates.map((c) => c.author).toList(), [
        'Anirudh Ravichander',
        'Sid Sriram',
        'Shreya Ghoshal',
        'Anirudh Ravichander',
        'Sid Sriram',
        'Shreya Ghoshal',
        'Anirudh Ravichander',
        'Shreya Ghoshal',
      ]);

      // Deduplication against existing playlist
      final existingPlaylist = [artistA[0]]; // Already has Hukum
      final fresh = CanonicalSongDedup.deduplicateList(existingPlaylist, candidates);

      expect(fresh.any((c) => c.id.value == 'rjkrTnma011'), isFalse);
      expect(fresh.length, 7);

      // Balanced spacing
      final balanced = CanonicalSongDedup.balanceArtistDistribution(fresh);
      for (int i = 0; i < balanced.length - 1; i++) {
        expect(
          CanonicalSongDedup.cleanArtist(balanced[i].author),
          isNot(equals(CanonicalSongDedup.cleanArtist(balanced[i + 1].author))),
          reason: 'No two consecutive songs should be by the exact same artist at index $i',
        );
      }
    });
  });
}
