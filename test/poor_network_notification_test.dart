import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/main_screen.dart';
import 'package:music_app/services/connectivity_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'hasPromptedName': true});
    final prefs = PreferencesService();
    await prefs.init();
  });

  testWidgets(
    'MainScreen displays DilSeNotification when network quality degrades',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: MainScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initially good connection
      ConnectivityService().setQualityForTesting(NetworkQuality.good);
      await tester.pump();
      expect(find.text('Weak Internet Connection'), findsNothing);

      // Simulate poor network quality
      ConnectivityService().setQualityForTesting(NetworkQuality.poor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // DilSeNotification warning HUD is visible
      expect(find.text('Weak Internet Connection'), findsOneWidget);

      // Tap notification to switch to Downloads tab (tab 3)
      await tester.tap(find.text('Weak Internet Connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Verify Tab 3 (DownloadsScreen) is selected and visible
      expect(find.text('Downloads'), findsWidgets);
    },
  );
}
