import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/curated_playlist_screen.dart';
import 'package:music_app/screens/home_screen.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _createMockVideo(String seedId, String title, String author) {
  final id = seedId.padRight(11, '0').substring(0, 11);
  return Video(
    VideoId(id),
    title,
    author,
    ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
    DateTime.now(),
    '',
    null,
    '',
    const Duration(minutes: 3),
    ThumbnailSet(id),
    null,
    Engagement(100, null, null),
    false,
  );
}

void main() {
  group('HomeQuickAccessItem 4-Tier Artwork Cascade Unit Tests', () {
    test(
      'Tier 3: Cold-start "New Releases" resolves authentic curated artwork',
      () {
        final item = HomeQuickAccessItem(
          title: 'New Releases',
          icon: Icons.album_rounded,
          onTap: () {},
        );

        final artwork = item.resolveArtwork();
        expect(artwork, isNotNull);
        expect(artwork, isNotEmpty);
        expect(artwork, contains('images.unsplash.com'));
        expect(
          artwork,
          equals(CuratedPlaylistScreen.getCuratedGenreFallback('New Releases')),
        );
      },
    );

    test(
      'Tier 2: "New Releases" with loaded songs resolves first track artwork',
      () {
        final video = _createMockVideo(
          'dQw4w9WgXcQ',
          'Never Gonna Give You Up',
          'Rick Astley',
        );

        final item = HomeQuickAccessItem(
          title: 'New Releases',
          icon: Icons.album_rounded,
          songs: [video],
          onTap: () {},
        );

        final artwork = item.resolveArtwork();
        expect(artwork, isNotNull);
        expect(artwork, isNotEmpty);
        expect(artwork, contains('i.ytimg.com/vi/dQw4w9WgXcQ'));
      },
    );

    test(
      'Tier 1: Explicit entity thumbnail takes precedence over songs and fallback',
      () {
        const explicitUrl = 'https://example.com/custom_cover.jpg';
        final item = HomeQuickAccessItem(
          title: 'New Releases',
          icon: Icons.album_rounded,
          imageUrl: explicitUrl,
          onTap: () {},
        );

        final artwork = item.resolveArtwork();
        expect(artwork, equals(explicitUrl));
      },
    );

    test(
      'Tier 4 trigger: Liked Songs with zero tracks returns null to use signature heart gradient',
      () {
        final item = HomeQuickAccessItem(
          title: 'Liked Songs',
          icon: Icons.favorite_rounded,
          onTap: () {},
        );

        final artwork = item.resolveArtwork();
        expect(artwork, isNull);
      },
    );

    test(
      'Curated fallback maps Top Charts, Trending, and Daily Mix correctly',
      () {
        expect(
          CuratedPlaylistScreen.getCuratedGenreFallback('Top Charts India'),
          contains('images.unsplash.com'),
        );
        expect(
          CuratedPlaylistScreen.getCuratedGenreFallback('Trending Now'),
          contains('images.unsplash.com'),
        );
        expect(
          CuratedPlaylistScreen.getCuratedGenreFallback('Daily Mix 1'),
          contains('images.unsplash.com'),
        );
      },
    );
  });

  group('HomeShortcutCard Widget Presentation Tests', () {
    testWidgets('Renders New Releases card without plain NEW text/icon box', (
      tester,
    ) async {
      final item = HomeQuickAccessItem(
        title: 'New Releases',
        icon: Icons.album_rounded,
        solidColor: const Color(0xFF1E382A),
        iconGradient: const [Color(0xFF1E382A), Color(0xFF12241A)],
        onTap: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 52,
                child: HomeShortcutCard(item: item),
              ),
            ),
          ),
        ),
      );

      // Verify "New Releases" text is rendered
      expect(find.text('New Releases'), findsOneWidget);

      // Verify Icons.fiber_new and Icons.fiber_new_rounded are completely eradicated
      expect(find.byIcon(Icons.fiber_new), findsNothing);
      expect(find.byIcon(Icons.fiber_new_rounded), findsNothing);
    });

    testWidgets(
      'Offline/Error Tier 4 fallback renders subtle album_rounded icon on theme gradient',
      (tester) async {
        // An item whose resolveArtwork returns null forces the Tier 4 fallback builder
        final item = HomeQuickAccessItem(
          title: 'Offline Release Mix',
          icon: Icons.album_rounded,
          solidColor: const Color(0xFF1E382A),
          iconGradient: const [Color(0xFF1E382A), Color(0xFF12241A)],
          onTap: () {},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 52,
                  child: HomeShortcutCard(item: item),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Offline Release Mix'), findsOneWidget);
        expect(find.byIcon(Icons.fiber_new), findsNothing);
      },
    );

    testWidgets(
      'Desktop viewport (>= 1024px) reveals 32x32 green circular play button on hover and triggers onPlay',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool playCalled = false;
        bool tapCalled = false;

        final item = HomeQuickAccessItem(
          title: 'New Releases',
          icon: Icons.album_rounded,
          onTap: () => tapCalled = true,
          onPlay: () => playCalled = true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 52,
                  child: HomeShortcutCard(item: item),
                ),
              ),
            ),
          ),
        );

        expect(find.text('New Releases'), findsOneWidget);

        // Initially play icon should have opacity 0.0 (hidden)
        final playIconFinder = find.byIcon(Icons.play_arrow_rounded);
        expect(playIconFinder, findsOneWidget);
        final animatedOpacityBefore = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: playIconFinder,
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(animatedOpacityBefore.opacity, 0.0);

        // Hover over the shortcut card
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(find.byType(HomeShortcutCard)));
        await tester.pumpAndSettle();

        // Opacity should now be 1.0 (revealed)
        final animatedOpacityAfter = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: playIconFinder,
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(animatedOpacityAfter.opacity, 1.0);

        // Tap on the play button
        await tester.tap(playIconFinder);
        await tester.pumpAndSettle();

        expect(playCalled, isTrue);
        expect(tapCalled, isFalse);
      },
    );

    testWidgets('Mobile viewport (< 1024px) does not show hover play button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final item = HomeQuickAccessItem(
        title: 'New Releases',
        icon: Icons.album_rounded,
        onTap: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: 52,
                child: HomeShortcutCard(item: item),
              ),
            ),
          ),
        ),
      );

      // Play button is not rendered on mobile viewports
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });
  });
}
