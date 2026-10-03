import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/keyboard_playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'KeyboardPlaybackController triggers play/pause on Space and seek on Arrow keys',
    (WidgetTester tester) async {
      int playPauseCalls = 0;
      final List<Duration> seekCalls = [];

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardPlaybackController(
            onPlayPause: () => playPauseCalls++,
            onSeekRelative: (offset) => seekCalls.add(offset),
            child: const Scaffold(body: Center(child: Text('Main Content'))),
          ),
        ),
      );

      // 1. Press Space -> togglePlayPause
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(playPauseCalls, 1);

      // 2. Press ArrowLeft -> seekRelative(-10s)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seekCalls, [const Duration(seconds: -10)]);

      // 3. Press ArrowRight -> seekRelative(+10s)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(seekCalls, [
        const Duration(seconds: -10),
        const Duration(seconds: 10),
      ]);
    },
  );

  testWidgets(
    'KeyboardPlaybackController ignores Space and Arrow keys when a TextField is focused',
    (WidgetTester tester) async {
      int playPauseCalls = 0;
      final List<Duration> seekCalls = [];
      final textController = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardPlaybackController(
            onPlayPause: () => playPauseCalls++,
            onSeekRelative: (offset) => seekCalls.add(offset),
            child: Scaffold(
              body: Column(
                children: [
                  TextField(controller: textController, autofocus: true),
                  const Text('Main Content'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the TextField to give it primary focus
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Send Space key
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // Send ArrowLeft key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      // Send ArrowRight key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // Playback shortcuts MUST be suppressed because user is typing in a text field
      expect(playPauseCalls, 0);
      expect(seekCalls, isEmpty);
    },
  );
}
