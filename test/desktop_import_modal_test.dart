import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_app/services/spotify_import_service.dart';
import 'package:music_app/widgets/desktop/desktop_import_modal.dart';
import 'package:music_app/widgets/desktop/desktop_left_sidebar.dart';
import 'package:music_app/layouts/desktop_layout_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SpotifyImportService parseExportifyCsvString Tests', () {
    test(
      'Correctly parses Exportify CSV string with standard headers and quoted columns',
      () async {
        const csvData = '''
Spotify ID,Artist Name(s),Track Name,Album Name,Artist Genres,Track Duration (ms)
4Dvkj6JhhA12EX05fT7y2e,"Sid Sriram, Sanapati Bharadwaj Patrudu","Samajavaragamana","Ala Vaikunthapurramuloo",tollywood,222000
5yJg2gW7dK8bH0J19bW78A,"Anirudh Ravichander, Jonita Gandhi","Arabic Kuthu - Halamithi Habibo","Beast",kollywood,279000
1w3rhv2y8g218h91h281h9,"Arijit Singh, Pritam","Kesariya (From ""Brahmastra"")","Kesariya",bollywood,268000
''';

        final service = SpotifyImportService();
        final tracks = await service.parseExportifyCsvString(csvData);

        expect(tracks.length, equals(3));
        expect(tracks[0]['Track Name'], equals('Samajavaragamana'));
        expect(
          tracks[0]['Artist Name(s)'],
          equals('Sid Sriram, Sanapati Bharadwaj Patrudu'),
        );
        expect(tracks[0]['Album Name'], equals('Ala Vaikunthapurramuloo'));
        expect(tracks[0]['Track Duration (ms)'], equals('222000'));

        expect(
          tracks[1]['Track Name'],
          equals('Arabic Kuthu - Halamithi Habibo'),
        );
        expect(
          tracks[1]['Artist Name(s)'],
          equals('Anirudh Ravichander, Jonita Gandhi'),
        );

        expect(tracks[2]['Track Name'], equals('Kesariya (From "Brahmastra")'));
        expect(tracks[2]['Artist Name(s)'], equals('Arijit Singh, Pritam'));
      },
    );

    test('Handles alternate headers, spaces, and empty lines safely', () async {
      const altCsv = '''
Track,Artist,Album,Duration
"Naatu Naatu","Rahul Sipligunj, Kaala Bhairava","RRR",215000

"Komuram Bheemudo","Kaala Bhairava","RRR",255000
''';

      final service = SpotifyImportService();
      final tracks = await service.parseExportifyCsvString(altCsv);

      expect(tracks.length, equals(2));
      expect(tracks[0]['Track Name'], equals('Naatu Naatu'));
      expect(
        tracks[0]['Artist Name(s)'],
        equals('Rahul Sipligunj, Kaala Bhairava'),
      );
      expect(tracks[1]['Track Name'], equals('Komuram Bheemudo'));
    });

    test('Returns empty list for empty or blank CSV string', () async {
      final service = SpotifyImportService();
      final tracks = await service.parseExportifyCsvString('');
      expect(tracks, isEmpty);
    });
  });

  group('DesktopImportModal Widget Tests', () {
    testWidgets(
      'Renders dual tabs and switches to Paste Spotify URL / CSV Content',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: DesktopImportModal())),
        );

        // Verify Header and Tab 1
        expect(find.text('Import Playlist'), findsOneWidget);
        expect(find.text('Upload Exportify CSV'), findsOneWidget);
        expect(find.text('Paste Spotify URL / CSV Content'), findsOneWidget);
        expect(
          find.text('Click to select Exportify .csv or .zip file'),
          findsOneWidget,
        );

        // Switch to Tab 2
        await tester.tap(find.text('Paste Spotify URL / CSV Content'));
        await tester.pumpAndSettle();

        // Verify Tab 2 text fields (paste well & playlist name) and resolve button
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.text('Resolve & Import'), findsOneWidget);
      },
    );

    testWidgets(
      'Shows error in Tab 2 when clicking Resolve & Import with empty content',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: DesktopImportModal())),
        );

        // Switch to Tab 2
        await tester.tap(find.text('Paste Spotify URL / CSV Content'));
        await tester.pumpAndSettle();

        // Click Resolve & Import
        await tester.tap(find.text('Resolve & Import'));
        await tester.pump();

        expect(
          find.text(
            'Please paste a Spotify playlist URL or Exportify CSV content.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('DesktopLeftSidebar Import Entry Points Tests', () {
    testWidgets(
      'Shows dedicated Spotify and Add Playlist buttons and opens import modal',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 350.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = false;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 350.0,
                child: DesktopLeftSidebar(width: 350.0),
              ),
            ),
          ),
        );

        // Verify dedicated Spotify Import and Add Playlist buttons in expanded mode
        final addIcon = find.byIcon(Icons.add_rounded);
        expect(addIcon, findsOneWidget);

        final spotifyTooltip = find.byTooltip(
          'Import from Spotify / Exportify',
        );
        expect(spotifyTooltip, findsOneWidget);

        final createTooltip = find.byTooltip('Create Playlist');
        expect(createTooltip, findsOneWidget);

        // Tapping the dedicated Spotify import button directly opens DesktopImportModal
        await tester.tap(spotifyTooltip);
        await tester.pumpAndSettle();

        expect(find.byType(DesktopImportModal), findsOneWidget);
        expect(find.text('Import Playlist'), findsOneWidget);
      },
    );

    testWidgets(
      'Filtering by "Imported from Spotify" hides Liked Songs and shows empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        DesktopLayoutState.leftSidebarWidth.value = 600.0;
        DesktopLayoutState.isLeftSidebarCollapsed.value = false;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                child: DesktopLeftSidebar(width: 600.0),
              ),
            ),
          ),
        );

        // Before filter: Liked Songs is visible
        expect(find.text('Liked Songs'), findsOneWidget);

        // Tap "Imported from Spotify" filter chip
        final importedChip = find.text('Imported from Spotify');
        expect(importedChip, findsOneWidget);
        await tester.tap(importedChip);
        await tester.pumpAndSettle();

        // When filtering by Imported from Spotify: Liked Songs is hidden
        expect(find.text('Liked Songs'), findsNothing);

        // Empty state is rendered with import action button
        expect(find.text('No imported playlists yet'), findsOneWidget);
        expect(find.text('Import from Exportify / Spotify'), findsOneWidget);
      },
    );
  });
}
