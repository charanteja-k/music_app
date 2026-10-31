import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/custom_playlist_screen.dart';
import 'package:music_app/services/music_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/widgets/dilse_image_cropper_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> createTestPngBytes({int width = 120, int height = 80}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFF1DB954);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DilSeImageCropperDialog Tests', () {
    late Uint8List testImageBytes;

    setUpAll(() async {
      testImageBytes = await createTestPngBytes(width: 160, height: 120);
    });

    testWidgets(
      'Renders DilSeImageCropperDialog with matte aesthetic and controls',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DilSeImageCropperDialog(
                imageBytes: testImageBytes,
                fileName: 'test_cover.png',
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        // Verify Header
        expect(find.text('Adjust Playlist Cover'), findsOneWidget);
        expect(
          find.text('Drag to reposition • Scroll or pinch to zoom'),
          findsOneWidget,
        );

        // Verify Controls
        expect(find.text('1:1 Square'), findsOneWidget);
        expect(find.text('Rotate 90°'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
        expect(find.text('Change Photo'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save Artwork'), findsOneWidget);

        // Verify Slider and initial zoom level
        expect(find.byType(Slider), findsOneWidget);
        expect(find.text('1.0x'), findsOneWidget);
      },
    );

    testWidgets('Zoom slider updates zoom level indicator', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DilSeImageCropperDialog(
              imageBytes: testImageBytes,
              fileName: 'test_cover.png',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      await tester.tapAt(tester.getCenter(slider));
      await tester.pumpAndSettle();

      // Zoom indicator should reflect higher scale
      expect(find.text('1.0x'), findsNothing);
    });

    testWidgets('Rotate button cycles rotation and reset restores 1.0x scale', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DilSeImageCropperDialog(
              imageBytes: testImageBytes,
              fileName: 'test_cover.png',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Tap Rotate
      await tester.tap(find.text('Rotate 90°'));
      await tester.pumpAndSettle();

      // Tap Reset
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets(
      'Save Artwork triggers PNG export and closes dialog with bytes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        Uint8List? returnedBytes;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  returnedBytes = await showDialog<Uint8List>(
                    context: context,
                    builder: (ctx) => DilSeImageCropperDialog(
                      imageBytes: testImageBytes,
                      fileName: 'test_cover.png',
                    ),
                  );
                },
                child: const Text('Open Cropper'),
              ),
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Cropper'));
        await tester.pumpAndSettle();

        // Wait for image decoding
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        // Tap Save Artwork
        await tester.tap(find.text('Save Artwork'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        // Verify dialog closed and returned cropped PNG bytes
        expect(find.byType(DilSeImageCropperDialog), findsNothing);
        expect(returnedBytes, isNotNull);
        expect(returnedBytes!.isNotEmpty, isTrue);
      },
    );
  });

  group('CustomPlaylistScreen Cover vs Name Dialog Separation Tests', () {
    late MusicService musicService;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '.',
          );
      SharedPreferences.setMockInitialValues({
        'listeningHistoryJson': '[]',
        'searchHistory': <String>[],
        'custom_playlist_covers_json': '{}',
      });
      await PreferencesService().init();

      musicService = MusicService();
      musicService.customPlaylists.clear();
      musicService.customPlaylists.add({
        'id': 'test_playlist_photo',
        'name': 'English Hits',
        'description': 'Popular English tracks',
        'songs': [
          {
            'id': 'track_1',
            'title': 'Track One',
            'author': 'Artist One',
            'thumbnail': 'https://c.saavncdn.com/1/Song1_150x150.jpg',
            'durationMs': 180000,
          },
        ],
      });
    });

    testWidgets(
      'Clicking Name & details opens Edit details dialog for renaming playlist',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CustomPlaylistScreen(playlistId: 'test_playlist_photo'),
          ),
        );
        await tester.pump();

        // Find "Name & details" button in DesktopPlaylistToolbar
        final nameAndDetailsBtn = find.text('Name & details');
        expect(nameAndDetailsBtn, findsOneWidget);

        await tester.tap(nameAndDetailsBtn);
        await tester.pump();

        // Edit details dialog should be visible with TextField
        expect(find.text('Edit details'), findsOneWidget);
        expect(find.text('Playlist Name'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          findsOneWidget,
        );

        // Cancel dialog
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(find.text('Edit details'), findsNothing);
      },
    );

    testWidgets(
      'Hovering playlist cover reveals Choose photo and tapping cover does NOT open Edit details name modal',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: CustomPlaylistScreen(playlistId: 'test_playlist_photo'),
          ),
        );
        await tester.pump();

        // Unhovered: "Choose photo" is not displayed
        expect(find.text('Choose photo'), findsNothing);

        // Hover over the playlist cover art (find the MouseRegion inside hero banner)
        final heroCoverFinder = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_DesktopHeroCoverBox',
        );
        expect(heroCoverFinder, findsOneWidget);

        final mouseRegionFinder = find.descendant(
          of: heroCoverFinder,
          matching: find.byType(MouseRegion),
        );
        expect(mouseRegionFinder, findsWidgets);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(heroCoverFinder));
        await tester.pump();

        // Hover overlay should now be visible
        expect(find.text('Choose photo'), findsOneWidget);

        // Tapping the cover should NOT open "Edit details" dialog
        await tester.tap(heroCoverFinder);
        await tester.pump();

        expect(find.text('Edit details'), findsNothing);
      },
    );

    testWidgets(
      'PreferencesService stores and retrieves custom playlist covers correctly',
      (WidgetTester tester) async {
        final prefs = PreferencesService();
        expect(prefs.getCustomPlaylistCover('test_playlist_photo'), isNull);

        const fakeCoverUri =
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        await prefs.setCustomPlaylistCover('test_playlist_photo', fakeCoverUri);

        expect(
          prefs.getCustomPlaylistCover('test_playlist_photo'),
          equals(fakeCoverUri),
        );

        // Clearing should remove cover
        await prefs.setCustomPlaylistCover('test_playlist_photo', null);
        expect(prefs.getCustomPlaylistCover('test_playlist_photo'), isNull);
      },
    );
  });
}
