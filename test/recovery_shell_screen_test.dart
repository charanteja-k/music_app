import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/recovery_shell_screen.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory testTempDir;

  setUp(() async {
    testTempDir = Directory.systemTemp.createTempSync('dilse_test_cache_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            return testTempDir.path;
          },
        );
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();
  });

  tearDown(() {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'RecoveryShellScreen renders standalone with sovereign banner and tools',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: RecoveryShellScreen()));

      // Verify Title & Hero Banner
      expect(find.text('Safe Mode & Recovery'), findsOneWidget);
      expect(find.text('Sovereign Recovery Shell'), findsOneWidget);

      // Verify Recovery Action Cards
      expect(
        find.text('Rollback to Previous Versions / Update'),
        findsOneWidget,
      );
      expect(find.text('Restore Safety Snapshot'), findsOneWidget);
      expect(find.text('Purge Corrupt Cache & State'), findsOneWidget);
      expect(find.text('Launch Normal App'), findsOneWidget);

      // Verify System Details Footer
      expect(find.text('SYSTEM & RUNTIME DETAILS'), findsOneWidget);
      expect(find.text('Zero-Black-Screen State'), findsOneWidget);
    },
  );

  testWidgets(
    'RecoveryShellScreen displays Framework Error Intercepted when errorDetails provided',
    (WidgetTester tester) async {
      final fakeError = FlutterErrorDetails(
        exception: Exception('Simulated fatal render pipeline failure'),
        stack: StackTrace.current,
        library: 'widgets library',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryShellScreen(
            errorDetails: fakeError,
            isCrashRecovery: true,
          ),
        ),
      );

      expect(find.text('Framework Error Intercepted'), findsOneWidget);
      expect(
        find.textContaining('Simulated fatal render pipeline failure'),
        findsOneWidget,
      );

      // Stack trace toggle is present
      expect(find.text('View Full Stack Trace'), findsOneWidget);
      await tester.tap(find.text('View Full Stack Trace'));
      await tester.pump();
      expect(find.text('Hide Stack Trace'), findsOneWidget);
    },
  );

  testWidgets('RecoveryShellScreen cache purge confirms and executes cleanly', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'home_cache_vibe': '{"items": []}',
      'last_playback_session': 'song123',
    });
    await PreferencesService().init();

    await tester.pumpWidget(const MaterialApp(home: RecoveryShellScreen()));

    // Scroll into view & tap Purge Cache button
    final purgeBtn = find.text('Purge Cache');
    expect(purgeBtn, findsOneWidget);
    await tester.ensureVisible(purgeBtn);
    await tester.pumpAndSettle();
    await tester.tap(purgeBtn);
    await tester.pumpAndSettle();

    // Verify Confirmation Dialog appears
    expect(find.text('Clear Cache & Reset State?'), findsOneWidget);

    // Tap Confirm Purge in dialog
    final confirmBtn = find.text('Confirm Purge');
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Check snackbar
    expect(find.textContaining('Transient cache cleaned'), findsOneWidget);
  });

  testWidgets(
    'RecoveryShellScreen self-wraps in MaterialApp when navigator is absent',
    (WidgetTester tester) async {
      // Testing isolation: render directly without MaterialApp wrapper
      await tester.pumpWidget(const RecoveryShellScreen());

      expect(find.text('Safe Mode & Recovery'), findsOneWidget);
      expect(find.text('Sovereign Recovery Shell'), findsOneWidget);
    },
  );

  testWidgets(
    'ErrorWidget.builder returns functional RecoveryShellScreen on widget error',
    (WidgetTester tester) async {
      final defaultBuilder = ErrorWidget.builder;
      try {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return RecoveryShellScreen(
            errorDetails: details,
            isCrashRecovery: true,
          );
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                throw Exception('Test unhandled widget throw');
              },
            ),
          ),
        );

        // Acknowledge the expected framework exception caught by ErrorWidget.builder
        expect(tester.takeException(), isNotNull);

        // Verify that RecoveryShellScreen was rendered by ErrorWidget.builder
        expect(find.byType(RecoveryShellScreen), findsOneWidget);
        expect(find.text('Framework Error Intercepted'), findsOneWidget);
        expect(
          find.textContaining('Test unhandled widget throw'),
          findsOneWidget,
        );
      } finally {
        ErrorWidget.builder = defaultBuilder;
      }
    },
  );
}
