import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/keyboard_playback_controller.dart';
import '../widgets/desktop/desktop_top_nav_bar.dart';
import '../widgets/desktop/desktop_resize_divider.dart';
import '../widgets/desktop/desktop_now_playing_bar.dart';
import '../widgets/desktop/desktop_left_sidebar.dart';
import '../widgets/desktop/desktop_right_panel.dart';
import 'desktop_main_viewport.dart';
import 'desktop_layout_state.dart';

/// Spotify-grade 3-Column Desktop Application Shell.
///
/// Automatically branches based on viewport width:
/// - Tier 1 (Wide Desktop: Width >= 1100px): Wide 3-column spatial layout with resizable sidebars.
/// - Tier 2 (Tiled / Compact Desktop: 500px <= Width < 1100px): Spotify compact mode with 72px icon strip,
///   flexible center view, slide-over or docked right panel, and edge-to-edge desktop player deck.
/// - Tier 3 (True Mobile / Narrow: Width < 500px or Native Phone): Standard mobile layout with floating dock.
class DesktopAppShell extends StatelessWidget {
  final Widget mobileBody;

  const DesktopAppShell({super.key, required this.mobileBody});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktopPlatform =
            kIsWeb ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux;

        // Tier 3: True Mobile Viewport or Native Mobile Platforms below 500px
        if (!isDesktopPlatform || width < 500.0) {
          return mobileBody;
        }

        // Tier 2: Compact / Tiled Desktop Viewport (500px <= width < 1100px)
        final isCompactMode = width < 1100.0;
        final isConstrainedCompact = width < 800.0;

        return KeyboardPlaybackController(
          child: Scaffold(
            backgroundColor: const Color(0xFF000000),
            body: Column(
              children: [
                // 1. Top Navigation Bar (64px)
                const SizedBox(
                  height: 64.0,
                  child: RepaintBoundary(child: DesktopTopNavBar()),
                ),

                // 2. Center 3-Column Spatial Grid
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Sidebar (Compact 72px when collapsed or clamped 72px-280px in Tier 2, resizable 72px-398px in Tier 1)
                          ValueListenableBuilder<double>(
                            valueListenable:
                                DesktopLayoutState.leftSidebarWidth,
                            builder: (context, sidebarWidth, _) {
                              final effectiveWidth = isCompactMode
                                  ? (sidebarWidth <= 72.0
                                        ? 72.0
                                        : sidebarWidth.clamp(72.0, 280.0))
                                  : sidebarWidth;
                              return SizedBox(
                                width: effectiveWidth,
                                child: RepaintBoundary(
                                  child: DesktopLeftSidebar(
                                    width: effectiveWidth,
                                  ),
                                ),
                              );
                            },
                          ),

                          // Tactical Left Resize Divider (Only in Wide Tier 1)
                          if (!isCompactMode)
                            const DesktopResizeDivider(isRightSide: false),

                          // Center Main Content Viewport (Expanded flex 1)
                          const Expanded(
                            child: RepaintBoundary(
                              child: DesktopMainViewport(),
                            ),
                          ),

                          // Right Contextual Panel with Resizer (Docked when width >= 800px)
                          if (!isConstrainedCompact)
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  DesktopLayoutState.isRightPanelVisible,
                              builder: (context, isVisible, _) {
                                if (!isVisible) return const SizedBox.shrink();

                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!isCompactMode)
                                      const DesktopResizeDivider(
                                        isRightSide: true,
                                      ),
                                    ValueListenableBuilder<double>(
                                      valueListenable:
                                          DesktopLayoutState.rightPanelWidth,
                                      builder: (context, panelWidth, _) {
                                        final effectiveRightWidth =
                                            isCompactMode
                                            ? panelWidth.clamp(240.0, 260.0)
                                            : panelWidth;
                                        return SizedBox(
                                          width: effectiveRightWidth,
                                          child: const RepaintBoundary(
                                            child: DesktopRightPanel(),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),

                      // Overlay Right Contextual Panel (Slide-Over when width < 800px)
                      if (isConstrainedCompact)
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              DesktopLayoutState.isRightPanelVisible,
                          builder: (context, isVisible, _) {
                            if (!isVisible) return const SizedBox.shrink();

                            return Positioned.fill(
                              left: 72.0, // Anchor after left sidebar
                              child: Row(
                                children: [
                                  // Dismissible Backdrop Scrim
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        DesktopLayoutState
                                                .isRightPanelVisible
                                                .value =
                                            false;
                                      },
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Floating Right Panel
                                  Container(
                                    width: 260.0,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF121212),
                                      border: const Border(
                                        left: BorderSide(
                                          color: Color(0xFF1E1E1E),
                                          width: 1,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          blurRadius: 16,
                                          offset: const Offset(-4, 0),
                                        ),
                                      ],
                                    ),
                                    child: const RepaintBoundary(
                                      child: DesktopRightPanel(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // 3. Bottom Edge-to-Edge Player Deck (90px)
                const SizedBox(
                  height: 90.0,
                  child: RepaintBoundary(child: DesktopNowPlayingBar()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
