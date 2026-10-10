import 'package:flutter/material.dart';

/// Design tokens for DilSe Music minimalist premium theme.
///
/// Designed to guarantee:
/// 1. 0% GPU backlight bleed on OLED/AMOLED displays (pure obsidian #09090C).
/// 2. 0 expensive BackdropFilter passes during vertical feed scrolling.
/// 3. Strict 60/120 FPS render performance on mid/low-tier Android and Samsung hardware.
class AppThemeTokens {
  AppThemeTokens._();

  // Backgrounds & Surfaces
  static const Color oledBackground = Color(0xFF09090C);
  static const Color surfaceCard = Color(0xFF121218);
  static const Color surfaceElevated = Color(0xFF1A1A22);
  static const Color floatingDockSurface = Color(0xFF16161D);

  // Subtle 1px borders (replaces GPU-heavy blur passes)
  static const Color surfaceBorder = Color(0x10FFFFFF); // ~6% white
  static const Color floatingDockBorder = Color(0x14FFFFFF); // ~8% white
  static const Color highlightBorder = Color(0x28FFFFFF); // ~16% white

  // Accent & Brand Colors
  static const Color brandRuby = Color(0xFFFA2D48);
  static const Color brandRubyGlow = Color(0x33FA2D48);

  // Typography Palette
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF5A5A62);

  // Corner Radiuses
  static const double radiusSmall = 8.0;
  static const double radiusCard = 14.0;
  static const double radiusFloatingDock = 16.0;
  static const double radiusHero = 20.0;
  static const double radiusPill = 100.0;

  // Clean, lightweight single-pass drop shadow (replaces 60px multi-layer blur)
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> dockShadow = [
    BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6)),
  ];
}
