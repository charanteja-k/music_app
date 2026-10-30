import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/dilse_notification.dart';

void main() {
  testWidgets('DilSeNotification shows pill and auto-dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                DilSeNotification.show(
                  context,
                  message: 'Added to Playlist',
                  subtitle: '50 songs in playlist',
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    // Initial state: No notification
    expect(find.text('Added to Playlist'), findsNothing);

    // Tap to show
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Pill is visible
    expect(find.text('Added to Playlist'), findsOneWidget);
    expect(find.text('50 songs in playlist'), findsOneWidget);

    // Wait for auto-dismiss timer (2800ms + animation)
    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pumpAndSettle();

    expect(find.text('Added to Playlist'), findsNothing);
  });

  testWidgets(
    'DilSeNotification convenience helpers work and show styled icons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () =>
                        DilSeNotification.heart(context, 'Liked Song'),
                    child: const Text('Heart'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        DilSeNotification.download(context, 'Downloaded Song'),
                    child: const Text('Download'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        DilSeNotification.warning(context, 'DRM Warning'),
                    child: const Text('Warning'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Heart helper
      await tester.tap(find.text('Heart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Liked Song'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      // Dismiss manually
      DilSeNotification.dismiss();
      await tester.pumpAndSettle();
      expect(find.text('Liked Song'), findsNothing);

      // Download helper
      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Downloaded Song'), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);

      DilSeNotification.dismiss();
      await tester.pumpAndSettle();

      // Warning helper
      await tester.tap(find.text('Warning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('DRM Warning'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

      DilSeNotification.dismiss();
      await tester.pumpAndSettle();
    },
  );
}
