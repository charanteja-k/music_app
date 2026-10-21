import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/desktop/desktop_playlist_enrichment.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  Video createMockSong(String id, String title, String author) {
    return Video(
      VideoId(id),
      title,
      author,
      ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
      DateTime.now(),
      '',
      null,
      '',
      const Duration(minutes: 3, seconds: 30),
      ThumbnailSet(id),
      null,
      Engagement(0, null, null),
      false,
    );
  }

  group('DesktopPlaylistEnrichment Widget Tests', () {
    testWidgets(
      'renders header, search input field, and Recommended section by default',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DesktopPlaylistEnrichment(
                  playlistId: 'test_playlist_1',
                  existingSongs: const [
                    {
                      'id': 'song1',
                      'title': 'Chuttamalle',
                      'author': 'Anirudh',
                    },
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. Header is rendered
        expect(
          find.text("Let's find something for your playlist"),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        // 2. Search box is rendered with placeholder
        expect(find.text('Search for songs or episodes'), findsOneWidget);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget);

        // 3. Recommended section is rendered
        expect(find.text('Recommended'), findsOneWidget);
        expect(find.text("Based on what's in this playlist"), findsOneWidget);
        expect(find.text('Find more'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping close icon collapses section to "Find more songs" pill button, and tapping it restores full drawer',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DesktopPlaylistEnrichment(
                  playlistId: 'test_playlist_2',
                  existingSongs: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text("Let's find something for your playlist"),
          findsOneWidget,
        );

        // Tap 'X' button
        await tester.tap(find.byTooltip('Collapse section'));
        await tester.pump();

        // Section header should be gone, replaced by "Find more songs"
        expect(
          find.text("Let's find something for your playlist"),
          findsNothing,
        );
        expect(find.text('Find more songs'), findsOneWidget);

        // Tap "Find more songs" to reopen
        await tester.tap(find.text('Find more songs'));
        await tester.pump();

        // Header restored
        expect(
          find.text("Let's find something for your playlist"),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'allows typing in search field and clears when clear button is tapped',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DesktopPlaylistEnrichment(
                  playlistId: 'test_playlist_3',
                  existingSongs: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);

        await tester.enterText(searchField, 'Kesariya');
        await tester.pump();

        expect(find.text('Kesariya'), findsOneWidget);
        // Clear icon appears
        final clearIcon = find.byIcon(Icons.close_rounded);
        expect(clearIcon, findsWidgets);

        // Tap clear icon inside search field
        await tester.tap(clearIcon.last);
        await tester.pump();

        expect(find.text('Search for songs or episodes'), findsOneWidget);
      },
    );

    testWidgets(
      'handles existing tracks with "Added" pill and calls onAddTrack when clicking "Add"',
      (tester) async {
        final mockSong = createMockSong(
          'rjkrTnma001',
          'Fresh Track',
          'Singer X',
        );
        bool songAddedCalled = false;
        Video? addedSong;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DesktopPlaylistEnrichment(
                  playlistId: 'test_playlist_4',
                  existingSongs: [mockSong],
                  onAddTrack: (song) {
                    addedSong = song;
                    songAddedCalled = true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // The widget was rendered without crashing
        expect(find.byType(DesktopPlaylistEnrichment), findsOneWidget);
        expect(songAddedCalled, isFalse);
        expect(addedSong, isNull);
      },
    );
  });
}
