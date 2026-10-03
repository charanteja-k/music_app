import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/dilse_tooltip.dart';

void main() {
  testWidgets('DilSeTooltip renders child and binds semantic tooltip label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DilSeTooltip(
              message: 'Play or Pause',
              child: Icon(Icons.play_arrow),
            ),
          ),
        ),
      ),
    );

    // Verify child is rendered
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Verify Tooltip widget exists in the tree with proper message
    final tooltipFinder = find.byType(Tooltip);
    expect(tooltipFinder, findsOneWidget);

    final tooltipWidget = tester.widget<Tooltip>(tooltipFinder);
    expect(tooltipWidget.message, 'Play or Pause');

    // On mobile touch (Android/iOS), triggerMode is manual to prevent gesture stealing.
    // On Desktop/Web, triggerMode is default (hover/focus).
    final isDesktopOrWeb =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (isDesktopOrWeb) {
      expect(tooltipWidget.triggerMode, isNull);
    } else {
      expect(tooltipWidget.triggerMode, TooltipTriggerMode.manual);
    }
  });

  testWidgets('DilSeTooltip empty message does not render Tooltip wrapper', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DilSeTooltip(message: '', child: Icon(Icons.volume_up)),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });
}
