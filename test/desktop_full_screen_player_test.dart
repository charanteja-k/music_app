import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/desktop/desktop_full_screen_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Video mockSong;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    prefs.resetForTesting();
    await prefs.init();
    await MusicService().audioPlayer.setVolume(1.0);

    mockSong = Video(
      VideoId('BddP6PYo2gs'),
      'Tum Hi Ho (Aashiqui 2)',
      'Arijit Singh',
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      const Duration(minutes: 4, seconds: 22),
      ThumbnailSet('BddP6PYo2gs'),
      null,
      Engagement(1000000, null, null),
      true,
    );
  });

  group('DesktopFullScreenPlayer Widget Tests', () {
    testWidgets('Renders cinema hero stage, metadata, and controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopFullScreenPlayer(
              song: mockSong,
              isPlaying: true,
              isLoading: false,
              isLiked: false,
              dominantColor: const Color(0xFF1E3A8A),
              vibrantColor: const Color(0xFF3B82F6),
              darkVibrantColor: const Color(0xFF0F172A),
              artworkStyle: ArtworkStyle.card,
              onClose: () => closed = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Top bar header verification
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('320 KBPS • HQ'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Hero track metadata
      expect(find.text('Tum Hi Ho (Aashiqui 2)'), findsOneWidget);
      expect(find.text('Arijit Singh'), findsOneWidget);

      // Playback deck controls
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      // Desktop volume control
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

      // Close button test
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      expect(closed, isTrue);
    });

    testWidgets('Switches tabs between Now Playing, Lyrics, and Queue', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopFullScreenPlayer(
              song: mockSong,
              isPlaying: false,
              isLoading: false,
              isLiked: true,
              dominantColor: const Color(0xFF6B21A8),
              vibrantColor: const Color(0xFFA855F7),
              darkVibrantColor: const Color(0xFF3B0764),
              artworkStyle: ArtworkStyle.card,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Switch to Lyrics tab
      final lyricsTab = find.text('Lyrics');
      expect(lyricsTab, findsOneWidget);
      await tester.tap(lyricsTab);
      await tester.pump();

      // In Cinema lyrics mode, split screen shows artwork and lyrics
      expect(find.text('Arijit Singh'), findsAtLeastNWidgets(1));

      // Switch to Queue tab
      final queueTab = find.byIcon(Icons.queue_music_rounded);
      expect(queueTab, findsOneWidget);
      await tester.tap(queueTab);
      await tester.pump();

      // Queue tab shows Up Next in Queue header
      expect(find.text('Up Next in Queue'), findsOneWidget);
    });

    testWidgets('Desktop tab enum has all valid states', (tester) async {
      expect(DesktopPlayerTab.values, contains(DesktopPlayerTab.nowPlaying));
      expect(DesktopPlayerTab.values, contains(DesktopPlayerTab.lyrics));
      expect(DesktopPlayerTab.values, contains(DesktopPlayerTab.queue));
      expect(DesktopPlayerTab.values.length, 3);
    });

    testWidgets('Toggles volume mute and unmute via speaker icon button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopFullScreenPlayer(
              song: mockSong,
              isPlaying: true,
              isLoading: false,
              isLiked: false,
              dominantColor: const Color(0xFF1E3A8A),
              vibrantColor: const Color(0xFF3B82F6),
              darkVibrantColor: const Color(0xFF0F172A),
              artworkStyle: ArtworkStyle.card,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially unmuted at 100%
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Tap Mute button
      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();

      // Now muted at 0% with volume_off icon and Unmute tooltip
      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);

      // Tap Unmute button
      await tester.tap(find.byTooltip('Unmute'));
      await tester.pump();

      // Restored back to 100%
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets(
      'Adjusts volume and mutes via keyboard shortcuts in fullscreen',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopFullScreenPlayer(
                song: mockSong,
                isPlaying: true,
                isLoading: false,
                isLiked: false,
                dominantColor: const Color(0xFF1E3A8A),
                vibrantColor: const Color(0xFF3B82F6),
                darkVibrantColor: const Color(0xFF0F172A),
                artworkStyle: ArtworkStyle.card,
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        // Initial state is 100%
        expect(find.text('100%'), findsOneWidget);

        // Press ArrowDown key to decrease volume by 5%
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(find.text('95%'), findsOneWidget);

        // Press 'M' key to toggle mute
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await tester.pump();
        expect(find.text('0%'), findsOneWidget);
        expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

        // Press 'M' key again to unmute
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await tester.pump();
        expect(find.text('95%'), findsOneWidget);
      },
    );

    testWidgets(
      'Controls volume mixer directly via interactive volume slider scrubber',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopFullScreenPlayer(
                song: mockSong,
                isPlaying: true,
                isLoading: false,
                isLiked: false,
                dominantColor: const Color(0xFF1E3A8A),
                vibrantColor: const Color(0xFF3B82F6),
                darkVibrantColor: const Color(0xFF0F172A),
                artworkStyle: ArtworkStyle.card,
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        // Initial state is 100%
        expect(find.text('100%'), findsOneWidget);

        // Find the volume slider by key
        final volumeSliderFinder = find.byKey(
          const Key('desktop_fullscreen_volume_slider'),
        );
        expect(volumeSliderFinder, findsOneWidget);

        // Drag/scrub volume slider towards middle (approx 50%)
        final sliderTopLeft = tester.getTopLeft(volumeSliderFinder);
        final sliderBottomRight = tester.getBottomRight(volumeSliderFinder);
        final sliderCenter = (sliderTopLeft + sliderBottomRight) / 2.0;

        await tester.tapAt(sliderCenter);
        await tester.pump();

        // The volume percentage should have updated to around 50%
        expect(find.text('100%'), findsNothing);
      },
    );
  });
}
