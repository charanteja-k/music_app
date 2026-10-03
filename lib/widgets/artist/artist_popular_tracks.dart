import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../services/music_service.dart';
import '../animated_equalizer.dart';
import '../dilse_tooltip.dart';
import '../song_options_bottom_sheet.dart';

/// Renders the top ranked (1–5) popular tracks for an artist.
class ArtistPopularTracks extends StatelessWidget {
  final List<Video> songs;
  final Color themeColor;

  const ArtistPopularTracks({
    super.key,
    required this.songs,
    required this.themeColor,
  });

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final popular = songs.take(5).toList();
    if (popular.isEmpty) return const SizedBox.shrink();

    final musicService = MusicService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                'POPULAR TRACKS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                'Top 5',
                style: TextStyle(
                  color: themeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: popular.length,
          itemBuilder: (context, index) {
            final song = popular[index];
            final rank = index + 1;
            final isCurrentSong =
                musicService.currentSong?.id.value == song.id.value;
            final hdThumbnail = MusicService.getHdThumbnail(song.id.value);

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rank index
                  SizedBox(
                    width: 22,
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: rank == 1
                            ? themeColor
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: rank == 1
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Artwork
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      hdThumbnail,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      errorBuilder: (_, _, _) => Image.network(
                        song.thumbnails.lowResUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                        cacheHeight: 120,
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrentSong ? themeColor : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                _formatDuration(song.duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCurrentSong)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedEqualizer(
                        isPlaying: musicService.isPlaying,
                        barCount: 3,
                        color: themeColor,
                        size: 16,
                      ),
                    ),
                  DilSeTooltip(
                    message: 'Song options',
                    child: IconButton(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white54,
                      ),
                      onPressed: () =>
                          showSongOptionsBottomSheet(context, song),
                    ),
                  ),
                ],
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                musicService.playPlaylist(songs, index);
              },
            );
          },
        ),
      ],
    );
  }
}
