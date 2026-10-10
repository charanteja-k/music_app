import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/dilse_capsule_data.dart';
import 'package:music_app/screens/dilse_capsule_screen.dart';

void main() {
  testWidgets('DilSeCapsuleScreen renders and advances slides smoothly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final testData = DilSeCapsuleData(
      totalMinutes: 1250,
      totalStreams: 350,
      uniqueArtistsCount: 42,
      topArtists: const [
        CapsuleArtist(name: 'A.R. Rahman', playCount: 80, percentage: 35.0),
        CapsuleArtist(name: 'Arijit Singh', playCount: 50, percentage: 22.0),
      ],
      topTracks: const [
        CapsuleTrack(
          id: 'test_1',
          title: 'Chaiyya Chaiyya',
          author: 'A.R. Rahman',
          thumbnail: '',
          playCount: 45,
        ),
      ],
      personaTitle: 'The Midnight Dreamer',
      personaDescription: 'Late-night frequencies are your sanctuary.',
      personaEmoji: '🌙',
      topLanguages: const ['Hindi', 'Tamil'],
      peakTimeDescription: 'Late Night (11 PM – 5 AM)',
      vibeScores: const {'Energy': 0.8, 'Chill': 0.7},
      generatedAt: DateTime.now(),
      hasEnoughData: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DilSeCapsuleScreen(initialData: testData, autoAdvance: false),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Slide 0 renders
    expect(find.text('DILSE CAPSULE'), findsOneWidget);
    expect(find.text('2026 CELEBRATION'), findsOneWidget);
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('MINUTES'), findsOneWidget);

    // Tap right to advance to Slide 1 (Top Tracks)
    await tester.tapAt(const Offset(300, 400));
    await tester.pumpAndSettle();

    expect(find.text('Your Top Tracks'), findsOneWidget);
    expect(find.text('Chaiyya Chaiyya'), findsOneWidget);
    expect(find.text('#1 MOST PLAYED'), findsOneWidget);

    // Tap right to advance to Slide 2 (Top Artists)
    await tester.tapAt(const Offset(300, 400));
    await tester.pumpAndSettle();

    expect(find.text('Artists Who Moved You'), findsOneWidget);
    expect(find.text('A.R. Rahman'), findsOneWidget);
    expect(find.text('YOUR #1 ARTIST'), findsOneWidget);

    // Tap right to advance to Slide 3 (Persona)
    await tester.tapAt(const Offset(300, 400));
    await tester.pumpAndSettle();

    expect(find.text('The Midnight Dreamer'), findsOneWidget);
    expect(find.text('🌙'), findsOneWidget);

    // Tap right to advance to Slide 4 (Grand Card)
    await tester.tapAt(const Offset(300, 400));
    await tester.pumpAndSettle();

    expect(find.text('Save Card'), findsOneWidget);
    expect(find.text('Copy Text'), findsOneWidget);
    expect(find.text('2026 CAPSULE'), findsOneWidget);

    // Tap left to return to Slide 3
    await tester.tapAt(const Offset(50, 400));
    await tester.pumpAndSettle();

    expect(find.text('The Midnight Dreamer'), findsOneWidget);
  });
}
