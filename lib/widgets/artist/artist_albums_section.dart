import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/jio_album.dart';
import '../../screens/album_screen.dart';
import '../dilse_tooltip.dart';

/// Renders a horizontal carousel of official albums & soundtracks for an artist.
class ArtistAlbumsSection extends StatelessWidget {
  final List<JioAlbum> albums;
  final bool isLoading;
  final Color themeColor;

  const ArtistAlbumsSection({
    super.key,
    required this.albums,
    this.isLoading = false,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty && !isLoading) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'SOUNDTRACKS & ALBUMS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (albums.isNotEmpty)
                Text(
                  '${albums.length} Releases',
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 175,
          child: isLoading && albums.isEmpty
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 4,
                  itemBuilder: (context, _) => _buildShimmerAlbumCard(),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return _buildAlbumCard(context, album);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(BuildContext context, JioAlbum album) {
    return Container(
      width: 124,
      margin: const EdgeInsets.only(right: 12),
      child: DilSeTooltip(
        message: 'Open "${album.title}" album',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlbumScreen(album: album)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: album.artwork.isNotEmpty
                      ? Image.network(
                          album.artwork,
                          fit: BoxFit.cover,
                          cacheWidth: 250,
                          cacheHeight: 250,
                          errorBuilder: (_, _, _) => _buildAlbumFallback(),
                        )
                      : _buildAlbumFallback(),
                ),
              ),
              const SizedBox(height: 6),
              // Album title
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              // Subtitle (year / songCount)
              Text(
                [
                  if (album.year.isNotEmpty) album.year,
                  if (album.songCount > 0) '${album.songCount} tracks',
                ].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumFallback() {
    return Container(
      color: const Color(0xFF1B1B26),
      child: const Center(
        child: Icon(Icons.album_rounded, color: Colors.white30, size: 40),
      ),
    );
  }

  Widget _buildShimmerAlbumCard() {
    return Container(
      width: 124,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A26),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 90,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A26),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
