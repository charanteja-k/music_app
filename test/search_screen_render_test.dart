import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/search_screen.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'searchHistory': [
        'snehithuda',
        'Akada Unnadu Ayyappa',
        'ayyappa',
        'kalyani',
        'Maula Mere Maula',
        'perfect',
        'Telugu Top Songs',
        'nanaku prematho',
        'love me',
        'o priya',
      ],
    });
    await PreferencesService().init();
  });

  testWidgets(
    'SearchScreen renders Categories and Recent Searches without layout error',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Browse Categories'), findsOneWidget);
      expect(find.text('snehithuda'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen switches smoothly between Categories and Artists tabs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      // Tap on Artists tab switcher
      final artistsTabFinder = find.widgetWithText(InkWell, 'Artists');
      expect(artistsTabFinder, findsOneWidget);
      await tester.tap(artistsTabFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Featured Artists'), findsOneWidget);

      // Tap back on Categories tab switcher
      final categoriesTabFinder = find.widgetWithText(InkWell, 'Categories');
      expect(categoriesTabFinder, findsOneWidget);
      await tester.tap(categoriesTabFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Browse Categories'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen renders on mobile device portrait size without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchScreen renders on mobile device landscape size without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Outer page navigation keeps Artists tab and Artists content in sync',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pageController = PageController(initialPage: 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pageController,
              children: const [
                SizedBox(key: Key('home_page'), child: Text('Home')),
                SearchScreen(),
                SizedBox(key: Key('library_page'), child: Text('Library')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Artists tab
      final artistsTab = find.widgetWithText(InkWell, 'Artists');
      expect(artistsTab, findsOneWidget);
      await tester.tap(artistsTab);
      await tester.pumpAndSettle();

      expect(find.text('Featured Artists'), findsOneWidget);
      expect(find.text('Browse Categories'), findsNothing);

      // Navigate to Home tab in outer PageView
      pageController.jumpToPage(0);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      // Navigate back to Search tab
      pageController.jumpToPage(1);
      await tester.pumpAndSettle();

      // Check what is displayed
      debugPrint(
        'Found Featured Artists: ${find.text('Featured Artists').evaluate().length}',
      );
      debugPrint(
        'Found Browse Categories: ${find.text('Browse Categories').evaluate().length}',
      );
      expect(find.text('Featured Artists'), findsOneWidget);
      expect(find.text('Browse Categories'), findsNothing);
    },
  );
}
