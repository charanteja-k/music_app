import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Spotify-grade Editorial Category Card.
///
/// Features:
/// 1. Aspect Ratio ~1.6:1 with BorderRadius 8px.
/// 2. Deep matte obsidian (#141416) surface with hairline border (#1E1E1E / white 0.06).
/// 3. Crisp white typography pinned top-left with 12px padding.
/// 4. 25-degree tilted square album cover thumbnail (68x68) overflowing bottom-right corner with drop shadow.
/// 5. Subtle micro-interaction on hover (1.02x scale, subtle brightness shift).
class CategoryCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String query;
  final List<Color>? colors;
  final IconData? icon;
  final String? thumbnailUrl;
  final String? badgeText;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.query,
    this.colors,
    this.icon,
    this.thumbnailUrl,
    this.badgeText,
    required this.onTap,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.97 : (_isHovered ? 1.02 : 1.0);

    final baseColor = widget.colors != null && widget.colors!.isNotEmpty
        ? widget.colors!.first
        : const Color(0xFFE13300);
    final cardColor = _isHovered
        ? Color.lerp(baseColor, Colors.white, 0.08)!
        : baseColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Stack(
                children: [
                  // 1. Tilted Cover Artwork Thumbnail overflowing bottom-right corner (rotate 25 deg)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Transform.rotate(
                      angle: 25 * (math.pi / 180), // 25 degrees
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.40),
                              blurRadius: 10,
                              offset: const Offset(2, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child:
                              widget.thumbnailUrl != null &&
                                  widget.thumbnailUrl!.isNotEmpty
                              ? Image.network(
                                  widget.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildFallbackThumbnail(),
                                )
                              : _buildFallbackThumbnail(),
                        ),
                      ),
                    ),
                  ),

                  // 2. Bold White Title pinned top-left with 14px padding
                  Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.70,
                        child: Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    final color = widget.colors != null && widget.colors!.isNotEmpty
        ? widget.colors!.first
        : const Color(0xFF242428);
    return Container(
      color: color,
      child: Center(
        child: Icon(
          widget.icon ?? Icons.music_note_rounded,
          color: Colors.white70,
          size: 30,
        ),
      ),
    );
  }
}
