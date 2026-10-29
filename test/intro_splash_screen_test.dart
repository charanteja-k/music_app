import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/constants/app_theme_tokens.dart';
import 'package:music_app/screens/intro_splash_screen.dart';
import 'package:music_app/screens/main_screen.dart';
import 'package:music_app/screens/recovery_shell_screen.dart';
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
    'IntroSplashScreen renders Recovery button and tapping it navigates to RecoveryShellScreen',
    (WidgetTester tester) async {
      IntroSplashScreen.hasCompletedSplash = false;
      await tester.pumpWidget(const MaterialApp(home: IntroSplashScreen()));

      // Progress animation slightly to reveal recovery button
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.text('Recovery'), findsOneWidget);

      // Tap recovery to navigate to RecoveryShellScreen immediately
      await tester.tap(find.text('Recovery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(RecoveryShellScreen), findsOneWidget);
    },
  );
}
