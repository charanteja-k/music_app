import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/recent_search_item.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecentSearchItem Model Tests', () {
    test('serializes to and from JSON accurately', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final item = RecentSearchItem(
        query: 'Anirudh',
        type: 'artist',
        timestamp: nowMs,
      );

      final json = item.toJson();
      expect(json['query'], 'Anirudh');
      expect(json['type'], 'artist');
      expect(json['timestamp'], nowMs);

      final reconstituted = RecentSearchItem.fromJson(json);
      expect(reconstituted.query, item.query);
      expect(reconstituted.type, item.type);
      expect(reconstituted.timestamp, item.timestamp);
    });

    test('implements value equality and hashCode based on query', () {
      final nowMs = 1700000000000;
      final item1 = RecentSearchItem(
        query: 'Sid Sriram',
        type: 'artist',
        timestamp: nowMs,
      );
      final item2 = RecentSearchItem(
        query: 'sid sriram',
        type: 'artist',
        timestamp: nowMs + 1000,
      );
      final item3 = RecentSearchItem(
        query: 'Devi Sri Prasad',
        type: 'query',
        timestamp: nowMs,
      );

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));
      expect(item1, isNot(equals(item3)));
    });
  });

  group('PreferencesService Structured Search History Tests', () {
    late PreferencesService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService();
      prefs.resetForTesting();
      await prefs.init();
    });

    test('adds and retrieves structured search history items', () async {
      await prefs.addToSearchHistory('Thaman S', type: 'artist');
      await prefs.addToSearchHistory('Leo', type: 'album');

      final structured = prefs.structuredSearchHistory;
      expect(structured.length, 2);
      expect(structured.first.query, 'Leo');
      expect(structured.first.type, 'album');
      expect(structured.last.query, 'Thaman S');
      expect(structured.last.type, 'artist');

      // Legacy string list should also stay synchronized
      expect(prefs.searchHistory, ['Leo', 'Thaman S']);
    });

    test(
      'deduplicates existing queries and bumps to top with new type',
      () async {
        await prefs.addToSearchHistory('Harris Jayaraj', type: 'query');
        await prefs.addToSearchHistory('Harris Jayaraj', type: 'artist');

        final structured = prefs.structuredSearchHistory;
        expect(structured.length, 1);
        expect(structured.first.query, 'Harris Jayaraj');
        expect(structured.first.type, 'artist');
      },
    );

    test('removes and clears search history across both collections', () async {
      await prefs.addToSearchHistory('A.R. Rahman', type: 'artist');
      await prefs.addToSearchHistory('Yuvan Shankar Raja', type: 'artist');

      await prefs.removeFromSearchHistory('A.R. Rahman');
      expect(prefs.structuredSearchHistory.length, 1);
      expect(prefs.structuredSearchHistory.first.query, 'Yuvan Shankar Raja');
      expect(prefs.searchHistory, ['Yuvan Shankar Raja']);

      await prefs.clearSearchHistory();
      expect(prefs.structuredSearchHistory, isEmpty);
      expect(prefs.searchHistory, isEmpty);
    });
  });
}
