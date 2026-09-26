import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/animated_lyrics.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AnimatedLyrics parses multi-format LRC timestamps and highlights correctly', (WidgetTester tester) async {
    const rawLrc = '''
[ti:Test Title]
[ar:Test Artist]
[00:02.50]First line of song
[00:05.00]Second line with delay
[00:08.500]Third line with 3-digit ms
[00:12]Fourth line with no ms
''';

    final positionController = StreamController<Duration>.broadcast();

    Duration? seekTarget;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(primaryColor: const Color(0xFFFA2D48)),
        home: Scaffold(
          body: AnimatedLyrics(
            rawLyrics: rawLrc,
            positionStream: positionController.stream,
            onSeek: (target) {
              seekTarget = target;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify all 4 text lines are rendered (metadata tags [ar:...] should be ignored)
    expect(find.text('First line of song'), findsOneWidget);
    expect(find.text('Second line with delay'), findsOneWidget);
    expect(find.text('Third line with 3-digit ms'), findsOneWidget);
    expect(find.text('Fourth line with no ms'), findsOneWidget);

    // Initial position: 0s (no line should be active yet, intro)
    positionController.add(Duration.zero);
    await tester.pumpAndSettle();

    // Emit position 3s -> "First line of song" should be active
    positionController.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));

    // Tap on second line to test seek
    await tester.tap(find.text('Second line with delay'));
    await tester.pump();
    expect(seekTarget, equals(const Duration(seconds: 5)));

    // Emit position 9s -> "Third line with 3-digit ms" should be active
    positionController.add(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 300));

    await positionController.close();
  });

  testWidgets('AnimatedLyrics shows Original, English, and Dual modes for regional Indic lyrics', (WidgetTester tester) async {
    const regionalLrc = '''
[00:02.00]సమాజవరగమనా
[00:05.00]చూసి చూడంగానే
''';

    final positionController = StreamController<Duration>.broadcast();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(primaryColor: const Color(0xFFFA2D48)),
        home: Scaffold(
          body: AnimatedLyrics(
            rawLyrics: regionalLrc,
            positionStream: positionController.stream,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Mode toggle bar buttons should be present for Indic lyrics
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dual'), findsOneWidget);

    // Default mode is Original: Telugu text is visible
    expect(find.text('సమాజవరగమనా'), findsOneWidget);

    // Switch to English Pronunciation mode
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // English transliterated pronunciation should now be displayed
    expect(find.textContaining('Sama'), findsOneWidget);

    // Switch to Dual mode
    await tester.tap(find.text('Dual'));
    await tester.pumpAndSettle();

    // In Dual mode, both original native text and transliterated pronunciation should be visible
    expect(find.text('సమాజవరగమనా'), findsOneWidget);
    expect(find.textContaining('Sama'), findsOneWidget);

    await positionController.close();
  });
}
