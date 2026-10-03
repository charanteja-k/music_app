import 'package:flutter/material.dart';
import '../../services/dynamic_artist_service.dart';
import '../dilse_tooltip.dart';

/// Reusable modular Hero SliverAppBar for the Artist Profile surface.
class ArtistHeader extends StatelessWidget {
  final String canonicalName;
  final ArtistItem? artistItem;
  final Color themeColor;
  final VoidCallback onBack;

  const ArtistHeader({
    super.key,
    required this.canonicalName,
    this.artistItem,
    required this.themeColor,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0B0B0F),
      expandedHeight: 280.0,
      pinned: true,
      elevation: 0,
      leading: DilSeTooltip(
        message: 'Back',
        child: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          onPressed: onBack,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient gradient background derived from artist portrait
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    themeColor.withValues(alpha: 0.35),
                    const Color(0xFF141420),
                    const Color(0xFF0B0B0F),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // High-Resolution Artist Circle Avatar
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withValues(alpha: 0.4),
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child:
                          artistItem != null && artistItem!.imageUrl.isNotEmpty
                          ? Image.network(
                              artistItem!.imageUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 240,
                              cacheHeight: 240,
                              errorBuilder: (_, _, _) => _buildAvatarFallback(),
                            )
                          : _buildAvatarFallback(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Artist Canonical Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      canonicalName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Tagline & Badge
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (artistItem != null &&
                            artistItem!.badge.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: themeColor.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              artistItem!.badge,
                              style: TextStyle(
                                color: themeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            artistItem?.genre ?? 'Official Discography',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: const Color(0xFF1E1E2C),
      child: const Icon(Icons.person_rounded, size: 52, color: Colors.white54),
    );
  }
}
