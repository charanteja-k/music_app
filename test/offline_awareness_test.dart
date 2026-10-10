import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/connectivity_service.dart';
import 'package:music_app/widgets/offline_barrier.dart';
import 'package:music_app/widgets/offline_indicator_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityService Tests', () {
    test('toggles offline state and notifies listeners', () {
      final connectivity = ConnectivityService();
      bool notified = false;
      connectivity.addListener(() {
        notified = true;
      });

      connectivity.setOfflineForTesting(true);
      expect(connectivity.isOffline, isTrue);
      expect(connectivity.isOnline, isFalse);
      expect(notified, isTrue);

      notified = false;
      connectivity.setOfflineForTesting(false);
      expect(connectivity.isOffline, isFalse);
      expect(connectivity.isOnline, isTrue);
      expect(notified, isTrue);
    });
  });

  group('OfflineIndicatorBanner Widget Tests', () {
    testWidgets('renders when offline and fires onGoToDownloads callback', (
      WidgetTester tester,
    ) async {
      bool goToDownloadsFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              isOfflineOverride: true,
              onGoToDownloads: () {
                goToDownloadsFired = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Playing from Downloads'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();

      expect(goToDownloadsFired, isTrue);
    });

    testWidgets('hides when offline override is false', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              isOfflineOverride: false,
              onGoToDownloads: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You are offline'), findsNothing);
    });
  });

  group('OfflineBarrier Widget Tests', () {
    testWidgets(
      'renders warning, message, and executes onGoToDownloads when tapped',
      (WidgetTester tester) async {
        bool navigatedToDownloads = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OfflineBarrier(
                message: 'Custom offline search notice',
                onGoToDownloads: () {
                  navigatedToDownloads = true;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('You are offline'), findsOneWidget);
        expect(find.text('Custom offline search notice'), findsOneWidget);
        expect(find.text('Go to Downloads'), findsOneWidget);
        expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

        await tester.tap(find.text('Go to Downloads'));
        await tester.pumpAndSettle();

        expect(navigatedToDownloads, isTrue);
      },
    );
  });
}
