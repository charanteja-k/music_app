import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/constants/app_theme_tokens.dart';
import 'package:music_app/screens/intro_splash_screen.dart';
import 'package:music_app/screens/main_screen.dart';
import 'package:music_app/screens/recovery_shell_screen.dart';
import 'package:music_app/services/connectivity_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  testWidgets(
    'IntroSplashScreen renders with obsidian background and skip navigates to MainScreen',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

      // Verify scaffold uses pure obsidian theme
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppThemeTokens.oledBackground);

      // Progress animation slightly to reveal skip button
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.text('Skip'), findsOneWidget);

      // Tap skip to navigate to MainScreen immediately
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(MainScreen), findsOneWidget);
    },
  );

  testWidgets(
    'IntroSplashScreen hides Recovery button on normal startup and navigates via 3-tap emergency gesture',
    (WidgetTester tester) async {
      IntroSplashScreen.hasCompletedSplash = false;
      await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

      // Progress animation slightly (500ms) - logo is visible, but recovery button remains hidden
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Recovery'), findsNothing);
      expect(find.byType(Image), findsOneWidget);

      // Tap logo 3 times to trigger emergency recovery
      await tester.tap(find.byType(Image));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(Image));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(RecoveryShellScreen), findsOneWidget);
    },
  );

  testWidgets(
    'IntroSplashScreen reveals Recovery button after watchdog timeout when startup stalls',
    (WidgetTester tester) async {
      IntroSplashScreen.hasCompletedSplash = false;
      await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

      // Initially hidden
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('Recovery'), findsNothing);

      // Pump past 2400ms watchdog threshold
      await tester.pump(const Duration(milliseconds: 1500));

      // Recovery button now revealed via watchdog
      expect(find.text('Recovery'), findsOneWidget);

      await tester.tap(find.text('Recovery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(RecoveryShellScreen), findsOneWidget);
    },
  );

  testWidgets('IntroSplashScreen routes to Library (Tab 2) when offline', (
    WidgetTester tester,
  ) async {
    IntroSplashScreen.hasCompletedSplash = false;
    ConnectivityService().setOfflineForTesting(true);

    await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final mainScreen = tester.widget<MainScreen>(find.byType(MainScreen));
    expect(mainScreen.initialIndex, 2);

    ConnectivityService().setOfflineForTesting(false);
  });

  testWidgets('IntroSplashScreen routes to Library (Tab 2) when offline', (
    WidgetTester tester,
  ) async {
    IntroSplashScreen.hasCompletedSplash = false;
    ConnectivityService().setOfflineForTesting(true);

    await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final mainScreen = tester.widget<MainScreen>(find.byType(MainScreen));
    expect(mainScreen.initialIndex, 2);

    ConnectivityService().setOfflineForTesting(false);
  });
}
