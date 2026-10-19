import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/screens/curated_playlist_screen.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _makeTestVideo(
  String id,
  String title,
  String author, {
  Duration? duration,
}) {
  return Video(
    VideoId(id.padRight(11, '0')),
    title,
    author,
    ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
    DateTime.now(),
    '',
    null,
    '',
    duration ?? const Duration(minutes: 3, seconds: 45),
    ThumbnailSet(id.padRight(11, '0')),
    null,
    Engagement(0, null, null),
    false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'CuratedPlaylistScreen renders hero metadata, action buttons, and tracks list',
    (WidgetTester tester) async {
      final mockSongs = [
        _makeTestVideo(
          'v1',
          'Hukum - Thalaivar Alappara',
          'Anirudh Ravichander',
        ),
        _makeTestVideo('v2', 'Chaleya', 'Anirudh Ravichander'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: CuratedPlaylistScreen(
            title: 'Top Hits',
            subtitle: 'Best curated songs',
            initialSongs: mockSongs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top Hits'), findsAtLeastNWidgets(1));
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Popular Tracks (2)'), findsOneWidget);
      expect(find.text('Hukum - Thalaivar Alappara'), findsOneWidget);
      expect(find.text('Chaleya'), findsOneWidget);
      expect(find.text('3:45'), findsNWidgets(2));
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border_rounded), findsNWidgets(2));

      // Test tapping Save button
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);

      // Test tapping inline like button
      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pump();
    },
  );

  testWidgets(
    'CuratedPlaylistScreen renders error state with retry button on failure',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CuratedPlaylistScreen(
            title: 'Empty Playlist',
            subtitle: 'Will have no tracks',
            fetchSongs: () async => <Video>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tracks found in this playlist.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'CuratedPlaylistScreen renders safely with single gradient color and category imageUrl',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CuratedPlaylistScreen(
            title: 'Telugu Beats',
            subtitle: 'Groove, Melodies & Mass',
            gradientColors: [Color(0xFFB06239)],
            imageUrl:
                'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&q=80',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Telugu Beats'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Groove, Melodies & Mass'), findsOneWidget);
      expect(find.byType(CuratedPlaylistScreen), findsOneWidget);
    },
  );
}
