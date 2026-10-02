import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CategoryCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String query;
  final List<Color> colors;
  final IconData icon;
  final String? badgeText;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.query,
    required this.colors,
    required this.icon,
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
    final scale = _isPressed ? 0.96 : (_isHovered ? 1.025 : 1.0);

    final solidColor = widget.colors.isNotEmpty
        ? widget.colors.first
        : const Color(0xFF8E2DE2);

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
              color: solidColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.14),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: solidColor.withValues(alpha: _isHovered ? 0.45 : 0.28),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: Offset(0, _isHovered ? 6 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Subtle translucent hover highlight
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: _isHovered ? 0.06 : 0.0,
                      child: Container(color: Colors.white),
                    ),
                  ),

                  // Stylized Angled Watermark Symbol
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: AnimatedScale(
                      scale: _isHovered ? 1.16 : 1.0,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      child: AnimatedRotation(
                        turns: _isHovered ? -0.06 : -0.04,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          widget.icon,
                          size: 78,
                          color: Colors.white.withValues(
                            alpha: _isHovered ? 0.24 : 0.16,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Card Content
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Header: Badge + Hover Play Micro-Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Frosted Category Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.icon,
                                    size: 11,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                  if (widget.badgeText != null &&
                                      widget.badgeText!.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.badgeText!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Micro Hover Play Trigger
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _isHovered ? 1.0 : 0.0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.3),
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
                        ),

                        // Bottom Titles
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
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
}
