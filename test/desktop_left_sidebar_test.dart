import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/layouts/desktop_layout_state.dart';
import 'package:music_app/widgets/desktop/desktop_left_sidebar.dart';

void main() {
  group('DesktopLeftSidebar Widget Tests', () {
    setUp(() {
      DesktopLayoutState.leftSidebarWidth.value = 280.0;
      DesktopLayoutState.isLeftSidebarCollapsed.value = false;
      DesktopLayoutState.isRightPanelVisible.value = true;
    });

    testWidgets(
      'Renders Compact Mode with top expand control when width <= 96px',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 72.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 72.0,
                child: DesktopLeftSidebar(width: 72.0),
              ),
            ),
          ),
        );

        // Verify authoritative Library expand control and compact navigation icons exist
        expect(find.byIcon(Icons.view_sidebar_rounded), findsOneWidget);
        expect(find.byIcon(Icons.home_filled), findsOneWidget);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget);
        expect(find.byIcon(Icons.add_rounded), findsOneWidget);
        expect(find.byIcon(Icons.favorite), findsOneWidget);

        // Test expanding sidebar from compact mode via Library expand control
        await tester.tap(find.byIcon(Icons.view_sidebar_rounded));
        await tester.pump();
        expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);
        expect(DesktopLayoutState.leftSidebarWidth.value, 280.0);
      },
    );

    testWidgets('Renders Expanded Mode with filter chips & search toolbar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 398.0,
              child: DesktopLeftSidebar(width: 398.0),
            ),
          ),
        ),
      );

      // Primary navigation rows
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);

      // Card 2 Library Header
      expect(find.text('Your Library'), findsOneWidget);
      expect(find.byIcon(Icons.view_sidebar_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      // Filter Chips
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Imported from Spotify'), findsOneWidget);

      // Scroll horizontal carousel to verify History chip
      await tester.scrollUntilVisible(
        find.text('History'),
        50.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('History'), findsOneWidget);

      // Toolbar elements
      expect(find.text('Recents'), findsOneWidget);
      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);

      // Liked songs row
      expect(find.text('Liked Songs'), findsOneWidget);

      // Test collapsing sidebar via collapse button
      await tester.tap(find.byIcon(Icons.view_sidebar_rounded));
      await tester.pump();
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
      expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
    });

    testWidgets('Filter chip toggles correctly on tap', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 398.0,
              child: DesktopLeftSidebar(width: 398.0),
            ),
          ),
        ),
      );

      // Initially Liked Songs is visible
      expect(find.text('Liked Songs'), findsOneWidget);

      // Tap Albums chip
      await tester.tap(find.text('Albums'));
      await tester.pump();

      // Liked Songs row should hide when Albums filter is active
      expect(find.text('Liked Songs'), findsNothing);

      // Tap Albums chip again to deselect
      await tester.tap(find.text('Albums'));
      await tester.pump();

      // Liked songs is visible again
      expect(find.text('Liked Songs'), findsOneWidget);
    });

    testWidgets(
      'Shows (X) clear filters button when active and resets filters',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 398.0,
                child: DesktopLeftSidebar(width: 398.0),
              ),
            ),
          ),
        );

        // (X) button is initially not present
        expect(find.byIcon(Icons.close_rounded), findsNothing);

        // Tap Playlists chip
        await tester.tap(find.text('Playlists'));
        await tester.pump();

        // (X) clear button should appear
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        // Tap (X) clear button
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();

        // (X) button should disappear
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      },
    );

    testWidgets(
      'Tapping Liked Songs row in expanded sidebar opens liked_songs',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 398.0,
                child: DesktopLeftSidebar(width: 398.0),
              ),
            ),
          ),
        );

        expect(find.text('Liked Songs'), findsOneWidget);
        await tester.tap(find.text('Liked Songs'));
        await tester.pump();

        expect(
          DesktopLayoutState.activeNavTab.value,
          DesktopNavTab.customPlaylist,
        );
        expect(DesktopLayoutState.activePlaylistId.value, 'liked_songs');
      },
    );

    testWidgets(
      'Tapping Liked Songs icon in compact sidebar opens liked_songs',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 72.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 72.0,
                child: DesktopLeftSidebar(width: 72.0),
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.favorite), findsOneWidget);
        await tester.tap(find.byIcon(Icons.favorite));
        await tester.pump();

        expect(
          DesktopLayoutState.activeNavTab.value,
          DesktopNavTab.customPlaylist,
        );
        expect(DesktopLayoutState.activePlaylistId.value, 'liked_songs');
      },
    );

    testWidgets(
      'Repeated expand and collapse toggles remain stable and preserve active state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 280.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = false;
        DesktopLayoutState.setNavTab(DesktopNavTab.search);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<double>(
                valueListenable: DesktopLayoutState.leftSidebarWidth,
                builder: (context, width, _) {
                  return SizedBox(
                    width: width,
                    child: DesktopLeftSidebar(width: width),
                  );
                },
              ),
            ),
          ),
        );

        // 1. Initially Expanded
        expect(find.text('Your Library'), findsOneWidget);
        expect(DesktopLayoutState.activeNavTab.value, DesktopNavTab.search);

        // 2. Collapse via collapse button
        await tester.tap(find.byTooltip('Collapse sidebar'));
        await tester.pump();
        expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
        expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
        expect(find.byTooltip('Expand sidebar'), findsOneWidget);
        expect(DesktopLayoutState.activeNavTab.value, DesktopNavTab.search);

        // 3. Expand via top expand button
        await tester.tap(find.byTooltip('Expand sidebar'));
        await tester.pump();
        expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);
        expect(DesktopLayoutState.leftSidebarWidth.value, 280.0);
        expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
        expect(DesktopLayoutState.activeNavTab.value, DesktopNavTab.search);

        // 4. Collapse again to ensure roundtrip durability
        await tester.tap(find.byTooltip('Collapse sidebar'));
        await tester.pump();
        expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
        expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
        expect(find.byTooltip('Expand sidebar'), findsOneWidget);
      },
    );

    testWidgets('Tapping Your Library header title collapses the sidebar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      DesktopLayoutState.leftSidebarWidth.value = 280.0;
      DesktopLayoutState.isLeftSidebarCollapsed.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: DesktopLayoutState.leftSidebarWidth,
              builder: (context, width, _) {
                return SizedBox(
                  width: width,
                  child: DesktopLeftSidebar(width: width),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Your Library'), findsOneWidget);
      await tester.tap(find.text('Your Library'));
      await tester.pump();

      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
      expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);
    });

    testWidgets('Preserves custom expanded width across collapse and expand', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // User customizes width to 340px
      DesktopLayoutState.updateLeftSidebarWidth(340.0);
      expect(DesktopLayoutState.leftSidebarWidth.value, 340.0);
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: DesktopLayoutState.leftSidebarWidth,
              builder: (context, width, _) {
                return SizedBox(
                  width: width,
                  child: DesktopLeftSidebar(width: width),
                );
              },
            ),
          ),
        ),
      );

      // Collapse via collapse button
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, true);
      expect(DesktopLayoutState.leftSidebarWidth.value, 72.0);

      // Reopen via expand button -> restores 340px
      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pump();
      expect(DesktopLayoutState.isLeftSidebarCollapsed.value, false);
      expect(DesktopLayoutState.leftSidebarWidth.value, 340.0);
    });

    testWidgets(
      'Compact Mode renders 48x48 Liked Songs album tile & playlist covers',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 72.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 72.0,
                child: DesktopLeftSidebar(width: 72.0),
              ),
            ),
          ),
        );
        await tester.pump();

        // Liked songs 48x48 tile with white heart icon
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(find.byTooltip('Liked Songs • 0 songs'), findsOneWidget);

        // Verify tapping Liked Songs opens liked_songs playlist in layout state
        await tester.tap(find.byIcon(Icons.favorite));
        await tester.pump();
        expect(DesktopLayoutState.activePlaylistId.value, 'liked_songs');
        expect(
          DesktopLayoutState.activeNavTab.value,
          DesktopNavTab.customPlaylist,
        );
      },
    );
  });
}
