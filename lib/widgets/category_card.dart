import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
                                  cacheWidth: 320,
                                  cacheHeight: 320,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildFallbackThumbnail(),
                                )
                              : _buildFallbackThumbnail(),
                        ),
                      ),
                    ),
                  ),
                  // Card Content
                  LayoutBuilder(
                    builder: (context, cardConstraints) {
                      final isVeryCompact = cardConstraints.maxHeight < 68;
                      final isCompact = cardConstraints.maxHeight < 85;
                      final isNarrow = cardConstraints.maxWidth < 130;
                      final padH = isNarrow ? 8.0 : 14.0;
                      final padV = isVeryCompact
                          ? 4.0
                          : (isCompact ? 6.0 : 12.0);

                      return ClipRect(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: padH,
                            vertical: padV,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Top Header: Badge + Hover Play Micro-Button
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Frosted Category Pill
                                  Flexible(
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isNarrow ? 6 : 8,
                                        vertical: isCompact ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.28,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            widget.icon,
                                            size: isCompact ? 9 : 11,
                                            color: Colors.white.withValues(
                                              alpha: 0.95,
                                            ),
                                          ),
                                          if (widget.badgeText != null &&
                                              widget.badgeText!.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                widget.badgeText!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: isCompact
                                                      ? 8.5
                                                      : 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.6,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!isNarrow) ...[
                                    const SizedBox(width: 4),
                                    // Micro Hover Play Trigger
                                    AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      opacity: _isHovered ? 1.0 : 0.0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.3,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              // Bottom Titles
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isCompact ? 13 : 15,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    if (widget.subtitle != null &&
                                        (!isCompact ||
                                            cardConstraints.maxHeight >
                                                65)) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        widget.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.82,
                                          ),
                                          fontSize: isCompact ? 9.5 : 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
