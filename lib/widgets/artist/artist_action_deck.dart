import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../dilse_tooltip.dart';

/// Reusable modular Action Deck for Artist Profile surface.
/// Contains Play All, Shuffle, Radio, and Follow actions.
class ArtistActionDeck extends StatelessWidget {
  final String artistName;
  final List<Video> songs;
  final Color themeColor;

  const ArtistActionDeck({
    super.key,
    required this.artistName,
    required this.songs,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final musicService = MusicService();
    final prefs = PreferencesService();
    final isFollowed = prefs.isArtistFollowed(artistName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          // 1. Play All Primary Button
          Expanded(
            child: DilSeTooltip(
              message: 'Play all ${songs.length} tracks',
              child: ElevatedButton.icon(
                onPressed: songs.isEmpty
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        musicService.playPlaylist(songs, 0);
                      },
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  'Play All (${songs.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Shuffle Button
          DilSeTooltip(
            message: 'Shuffle tracks',
            child: ElevatedButton.icon(
              onPressed: songs.isEmpty
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      final shuffled = List<Video>.from(songs)..shuffle();
                      musicService.playPlaylist(shuffled, 0);
                    },
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              label: const Text(
                'Shuffle',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E2C),
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Smart Artist Radio Button
          DilSeTooltip(
            message: 'Start $artistName smart radio',
            child: ElevatedButton(
              onPressed: songs.isEmpty
                  ? null
                  : () async {
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Starting $artistName Smart Radio…'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: themeColor.withValues(alpha: 0.9),
                        ),
                      );
                      final topSong = songs.first;
                      final radioTracks = await musicService
                          .fetchRadioTracksForSong(topSong, limit: 40);
                      if (radioTracks.isNotEmpty) {
                        musicService.playPlaylist([topSong, ...radioTracks], 0);
                      } else {
                        musicService.playPlaylist(songs, 0);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E2C),
                foregroundColor: themeColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: themeColor.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                elevation: 2,
              ),
              child: const Icon(Icons.auto_awesome_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 8),

          // 4. Follow / Following Toggle Button
          DilSeTooltip(
            message: isFollowed ? 'Unfollow artist' : 'Follow artist',
            child: OutlinedButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                prefs.toggleFollowArtist(artistName);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: isFollowed
                    ? themeColor.withValues(alpha: 0.18)
                    : const Color(0xFF161622),
                foregroundColor: isFollowed ? themeColor : Colors.white70,
                side: BorderSide(
                  color: isFollowed
                      ? themeColor
                      : Colors.white.withValues(alpha: 0.14),
                  width: 1.2,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Icon(
                isFollowed
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: isFollowed ? themeColor : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
