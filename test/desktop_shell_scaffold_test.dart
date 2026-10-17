import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/layouts/desktop_app_shell.dart';
import 'package:music_app/layouts/desktop_layout_state.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/desktop/desktop_top_nav_bar.dart';
import 'package:music_app/widgets/desktop/desktop_right_panel.dart';

void main() {
  group('DesktopLayoutState Unit Tests', () {
    setUp(() {
      DesktopLayoutState.leftSidebarWidth.value = 280.0;
      DesktopLayoutState.isLeftSidebarCollapsed.value = false;
      DesktopLayoutState.isRightPanelVisible.value = true;
      DesktopLayoutState.contextTab.value = DesktopContextTab.nowPlaying;
    });

    test('updateLeftSidebarWidth clamps between 72 and 398', () {
      DesktopLayoutState.updateLeftSidebarWidth(350.0);
      expect(DesktopLayoutState.leftSidebarWidth.value, 350.0);
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);

      DesktopLayoutState.updateLeftSidebarWidth(500.0);
      expect(DesktopLayoutState.leftSidebarWidth.value, 398.0);
    });

    test('updateLeftSidebarWidth snaps to 72 when dragged below 120', () {
      DesktopLayoutState.updateLeftSidebarWidth(110.0);
      expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
    });

    test('toggleLeftSidebar switches between 280 and 72', () {
      DesktopLayoutState.toggleLeftSidebar();
      expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);

      DesktopLayoutState.toggleLeftSidebar();
      expect(DesktopLayoutState.leftSidebarWidth.value, 280.0);
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);
    });

    test('toggleRightPanel and setContextTab work properly', () {
      DesktopLayoutState.toggleRightPanel();
      expect(DesktopLayoutState.isRightPanelVisible.value, false);

      DesktopLayoutState.setContextTab(DesktopContextTab.lyrics);
      expect(DesktopLayoutState.contextTab.value, DesktopContextTab.lyrics);
      expect(DesktopLayoutState.isRightPanelVisible.value, true);
    });
  });

  group('PreferencesService Contrast Guard Tests', () {
    test('ensureLegibleColor leaves already bright colors intact', () {
      const red = Color(0xFFFA2D48);
      final legible = PreferencesService.ensureLegibleColor(red);
      expect(legible, red);
    });

    test(
      'ensureLegibleColor boosts ultra dark colors to minimum luminance',
      () {
        const darkColor = Color(0xFF0A0515);
        final legible = PreferencesService.ensureLegibleColor(darkColor);
        expect(legible.computeLuminance(), greaterThanOrEqualTo(0.18));
        expect(legible, isNot(darkColor));
      },
    );
  });

  group('DesktopAppShell Widget Tests', () {
    setUp(() {
      DesktopLayoutState.leftSidebarWidth.value = 280.0;
      DesktopLayoutState.isLeftSidebarCollapsed.value = false;
      DesktopLayoutState.isRightPanelVisible.value = true;
      DesktopLayoutState.contextTab.value = DesktopContextTab.nowPlaying;
    });

    testWidgets('Renders mobileBody on true mobile screen (< 500px)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        tester.view.physicalSize = const Size(450, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: DesktopAppShell(mobileBody: Text('Mobile Body Content')),
          ),
        );

        expect(find.text('Mobile Body Content'), findsOneWidget);
        expect(find.byType(DesktopTopNavBar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Renders constrained compact desktop shell (500px - 800px) with slide-over right panel',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          tester.view.physicalSize = const Size(600, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            const MaterialApp(
              home: DesktopAppShell(mobileBody: Text('Mobile Body Content')),
            ),
          );

          expect(find.text('Mobile Body Content'), findsNothing);
          expect(find.byType(DesktopTopNavBar), findsOneWidget);
          expect(find.byType(DesktopRightPanel), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Renders compact desktop shell (800px - 1100px) with docked right panel',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          tester.view.physicalSize = const Size(900, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            const MaterialApp(
              home: DesktopAppShell(mobileBody: Text('Mobile Body Content')),
            ),
          );

          expect(find.text('Mobile Body Content'), findsNothing);
          expect(find.byType(DesktopTopNavBar), findsOneWidget);
          expect(find.byType(DesktopRightPanel), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Renders wide desktop shell (Tier 1: >= 1100px) with desktop navigation',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            const MaterialApp(
              home: DesktopAppShell(mobileBody: Text('Mobile Body Content')),
            ),
          );

          expect(find.text('Mobile Body Content'), findsNothing);
          expect(find.byType(DesktopTopNavBar), findsOneWidget);
          expect(find.byType(DesktopRightPanel), findsOneWidget);

          // Verify single authoritative sidebar toggle in left sidebar
          expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
          await tester.tap(find.byTooltip('Collapse sidebar'));
          await tester.pump();
          expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
          expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);

          // Reopen via expand button
          expect(find.byTooltip('Expand sidebar'), findsOneWidget);
          await tester.tap(find.byTooltip('Expand sidebar'));
          await tester.pump();
          expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);
          expect(DesktopLayoutState.leftSidebarWidth.value, 280.0);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
