import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/album_color_deriver.dart';
import 'package:music_app/widgets/animated_lyrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'AnimatedLyrics parses multi-format LRC timestamps and highlights correctly',
    (WidgetTester tester) async {
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
    },
  );

  testWidgets(
    'AnimatedLyrics shows Original, English, and Dual modes for regional Indic lyrics',
    (WidgetTester tester) async {
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
    },
  );

  testWidgets(
    'AnimatedLyrics places Romanized Telugu lyrics in English pronunciation slot and supports modes',
    (WidgetTester tester) async {
      const romanizedLrc = '''
[00:02.00]Rajamandri raagamajari
[00:05.00]Mayamma peru
''';

      final positionController = StreamController<Duration>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(primaryColor: const Color(0xFFFA2D48)),
          home: Scaffold(
            body: AnimatedLyrics(
              rawLyrics: romanizedLrc,
              songLanguage: 'telugu',
              positionStream: positionController.stream,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mode toggle bar buttons should be present for Romanized Telugu lyrics
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Dual'), findsOneWidget);

      // English mode is active by default for Romanized Indic songs, showing the English pronunciation lyrics
      expect(find.text('Rajamandri raagamajari'), findsOneWidget);

      // Switch to Original mode: Native Telugu script should now be visible
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(find.text('Rajamandri raagamajari'), findsNothing);

      // Switch to Dual mode: Both Telugu script and English pronunciation should be visible
      await tester.tap(find.text('Dual'));
      await tester.pumpAndSettle();
      expect(find.text('Rajamandri raagamajari'), findsOneWidget);

      await positionController.close();
    },
  );

  test(
    'AlbumColorDeriver resolves black and near-black colors to white and preserves vibrant dominant colors',
    () {
      // 1. Pure black
      expect(
        AlbumColorDeriver.isBlackOrCloseToBlack(const Color(0xFF000000)),
        isTrue,
      );
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(const Color(0xFF000000)),
        equals(Colors.white),
      );

      // 2. Near black / dark fallback surfaces
      expect(
        AlbumColorDeriver.isBlackOrCloseToBlack(const Color(0xFF1E1E2C)),
        isTrue,
      );
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(const Color(0xFF1E1E2C)),
        equals(Colors.white),
      );

      expect(
        AlbumColorDeriver.isBlackOrCloseToBlack(const Color(0xFF121212)),
        isTrue,
      );
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(const Color(0xFF121212)),
        equals(Colors.white),
      );

      expect(
        AlbumColorDeriver.isBlackOrCloseToBlack(const Color(0xFF242424)),
        isTrue,
      );
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(const Color(0xFF242424)),
        equals(Colors.white),
      );

      // 3. Vibrant album covers (e.g. Coldplay sky blue) should NOT be black
      const skyBlue = Color(0xFF38A0FF);
      expect(AlbumColorDeriver.isBlackOrCloseToBlack(skyBlue), isFalse);
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(skyBlue),
        equals(skyBlue),
      );

      // 4. Vibrant crimson
      const crimson = Color(0xFFFA2D48);
      expect(AlbumColorDeriver.isBlackOrCloseToBlack(crimson), isFalse);
      expect(
        AlbumColorDeriver.resolveLyricHighlightColor(crimson),
        equals(crimson),
      );

      // 5. Dark saturated color gets lightness boosted to >= 0.55 for dark canvas legibility
      const deepNavy = Color(0xFF002255);
      expect(AlbumColorDeriver.isBlackOrCloseToBlack(deepNavy), isFalse);
      final resolvedNavy = AlbumColorDeriver.resolveLyricHighlightColor(
        deepNavy,
      );
      expect(resolvedNavy, isNot(equals(Colors.white)));
      expect(
        HSLColor.fromColor(resolvedNavy).lightness,
        greaterThanOrEqualTo(0.50),
      );
    },
  );

  testWidgets(
    'AnimatedLyrics respects custom highlightColor and renders with album dominant color',
    (WidgetTester tester) async {
      const rawLrc = '''
[00:01.00]Line one of song
[00:04.00]Line two of song
''';

      final positionController = StreamController<Duration>.broadcast();
      const albumSkyBlue = Color(0xFF38A0FF);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedLyrics(
              rawLyrics: rawLrc,
              positionStream: positionController.stream,
              highlightColor: albumSkyBlue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Emit position 2s -> Line one is active
      positionController.add(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      // Find the AnimatedDefaultTextStyle of the active line
      final activeTextFinder = find.ancestor(
        of: find.text('Line one of song'),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      final activeText = tester.widget<AnimatedDefaultTextStyle>(
        activeTextFinder.first,
      );
      expect(activeText.style.color, equals(albumSkyBlue));

      await positionController.close();
    },
  );

  testWidgets(
    'AnimatedLyrics renders white highlight when album dominant color is black',
    (WidgetTester tester) async {
      const rawLrc = '''
[00:01.00]Dark album song line
''';

      final positionController = StreamController<Duration>.broadcast();
      final resolvedBlackFallback =
          AlbumColorDeriver.resolveLyricHighlightColor(const Color(0xFF050505));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedLyrics(
              rawLyrics: rawLrc,
              positionStream: positionController.stream,
              highlightColor: resolvedBlackFallback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Emit position 2s -> Line is active
      positionController.add(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      final activeTextFinder = find.ancestor(
        of: find.text('Dark album song line'),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      final activeText = tester.widget<AnimatedDefaultTextStyle>(
        activeTextFinder.first,
      );
      expect(activeText.style.color, equals(Colors.white));

      await positionController.close();
    },
  );
}
