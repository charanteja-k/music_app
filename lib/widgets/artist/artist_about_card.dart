import 'package:flutter/material.dart';
import '../../services/dynamic_artist_service.dart';

/// Renders a verified metadata about card for the artist.
/// Displays genuine catalog statistics without fabricating biographies or monthly listeners.
class ArtistAboutCard extends StatelessWidget {
  final String canonicalName;
  final ArtistItem? artistItem;
  final List<String> languages;
  final int totalTracks;
  final Color themeColor;

  const ArtistAboutCard({
    super.key,
    required this.canonicalName,
    this.artistItem,
    required this.languages,
    required this.totalTracks,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cleanLangs = languages.where((l) => l != 'All').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: themeColor),
                const SizedBox(width: 8),
                Text(
                  'ABOUT $canonicalName'.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Genre & Badge
            if (artistItem != null) ...[
              Text(
                artistItem!.genre,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Catalog summary metrics
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (totalTracks > 0)
                  _buildMetricChip(
                    Icons.music_note_rounded,
                    '$totalTracks+ Tracks Cataloged',
                  ),
                if (cleanLangs.isNotEmpty)
                  _buildMetricChip(
                    Icons.language_rounded,
                    cleanLangs.join(', '),
                  ),
                if (artistItem != null && artistItem!.badge.isNotEmpty)
                  _buildMetricChip(
                    Icons.verified_rounded,
                    'Verified ${artistItem!.badge}',
                    color: themeColor,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D2B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.white54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
