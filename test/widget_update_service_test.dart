import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/widget_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetUpdateService Unit Tests', () {
    late List<MethodCall> channelCalls;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      channelCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WidgetUpdateService.channel, (call) async {
            channelCalls.add(call);
            return true;
          });
      WidgetUpdateService().resetForTesting();
    });

    test(
      'updateWidget saves playback state, dominant color, and progress to SharedPreferences and invokes native channel',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        final service = WidgetUpdateService();
        await service.updateWidget(
          title: 'Naatu Naatu',
          artist: 'MM Keeravaani',
          isPlaying: true,
          artworkPath: '/data/user/0/com.example.music_app/cache/artwork.jpg',
          trackId: 'track_123',
          dominantColor: 0xFFFF5722,
          position: const Duration(minutes: 1, seconds: 24),
          duration: const Duration(minutes: 3, seconds: 45),
          isShuffle: true,
          isRepeat: false,
          topPlaylists: [
            {'id': 'daily_mix', 'title': 'Daily\nMix', 'query': 'Keeravaani'},
            {'id': 'favorites', 'title': 'Favorites', 'query': 'favorites'},
          ],
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('widget_title'), equals('Naatu Naatu'));
        expect(prefs.getString('widget_artist'), equals('Mm Keeravaani'));
        expect(prefs.getBool('widget_is_playing'), isTrue);
        expect(prefs.getBool('widget_is_shuffle'), isTrue);
        expect(prefs.getBool('widget_is_repeat'), isFalse);
        expect(
          prefs.getString('widget_artwork_path'),
          equals('/data/user/0/com.example.music_app/cache/artwork.jpg'),
        );
        expect(prefs.getInt('widget_dominant_color'), equals(0xFFFF5722));
        expect(prefs.getInt('widget_position_ms'), equals(84000));
        expect(prefs.getInt('widget_duration_ms'), equals(225000));
        expect(prefs.getString('widget_position_text'), equals('1:24'));
        expect(prefs.getString('widget_duration_text'), equals('3:45'));

        final rawPlaylists = prefs.getString('widget_top_playlists_json');
        expect(rawPlaylists, isNotNull);
        final decoded = json.decode(rawPlaylists!) as List;
        expect(decoded.length, equals(2));
        expect(decoded.first['id'], equals('daily_mix'));

        expect(channelCalls.length, equals(1));
        expect(channelCalls.first.method, equals('updateWidget'));

        debugDefaultTargetPlatformOverride = null;
      },
    );

    test(
      'updateWidget deduplicates successive identical updates to prevent battery drain',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        final service = WidgetUpdateService();
        await service.updateWidget(
          title: 'Same Song',
          artist: 'Same Artist',
          isPlaying: true,
          trackId: 'same_id',
        );
        expect(channelCalls.length, equals(1));

        // Duplicate invocation with identical state
        await service.updateWidget(
          title: 'Same Song',
          artist: 'Same Artist',
          isPlaying: true,
          trackId: 'same_id',
        );
        // Must not invoke channel again
        expect(channelCalls.length, equals(1));

        // State changes (paused)
        await service.updateWidget(
          title: 'Same Song',
          artist: 'Same Artist',
          isPlaying: false,
          trackId: 'same_id',
        );
        expect(channelCalls.length, equals(2));

        debugDefaultTargetPlatformOverride = null;
      },
    );

    test(
      'initWidgetActionHandler handles incoming shuffle, repeat, and playlist actions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        bool shuffleToggled = false;
        bool repeatToggled = false;
        String? playedPlaylistId;

        final service = WidgetUpdateService();
        service.initWidgetActionHandler(
          onToggleShuffle: () => shuffleToggled = true,
          onToggleRepeat: () => repeatToggled = true,
          onPlayPlaylist: (index, id, query) async {
            playedPlaylistId = id;
          },
        );

        // Simulate native incoming calls
        final binding = TestDefaultBinaryMessengerBinding.instance;
        final codec = const StandardMethodCodec();

        // 1. Toggle Shuffle
        final byteDataShuffle = codec.encodeMethodCall(
          const MethodCall('toggleShuffle'),
        );
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          'com.example.music_app/widget',
          byteDataShuffle,
          (ByteData? reply) {},
        );
        expect(shuffleToggled, isTrue);

        // 2. Toggle Repeat
        final byteDataRepeat = codec.encodeMethodCall(
          const MethodCall('toggleRepeat'),
        );
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          'com.example.music_app/widget',
          byteDataRepeat,
          (ByteData? reply) {},
        );
        expect(repeatToggled, isTrue);

        // 3. Play Playlist
        final byteDataPlaylist = codec.encodeMethodCall(
          const MethodCall('playPlaylist', {
            'index': 1,
            'id': 'favorites',
            'query': 'favorites',
          }),
        );
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          'com.example.music_app/widget',
          byteDataPlaylist,
          (ByteData? reply) {},
        );
        expect(playedPlaylistId, equals('favorites'));

        debugDefaultTargetPlatformOverride = null;
      },
    );

    test('toTitleCase capitalizes first letter of each word properly', () {
      expect(
        WidgetUpdateService.toTitleCase('swagatham krishna'),
        'Swagatham Krishna',
      );
      expect(
        WidgetUpdateService.toTitleCase('niranjana ramanan'),
        'Niranjana Ramanan',
      );
      expect(WidgetUpdateService.toTitleCase('DILSE MUSIC'), 'Dilse Music');
      expect(WidgetUpdateService.toTitleCase(''), '');
    });

    test('initWidgetActionHandler handles seekTo native action', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      Duration? soughtPos;
      final service = WidgetUpdateService();
      service.initWidgetActionHandler(
        onToggleShuffle: () {},
        onToggleRepeat: () {},
        onPlayPlaylist: (index, id, query) async {},
        onSeekTo: (pos) async {
          soughtPos = pos;
        },
      );

      final binding = TestDefaultBinaryMessengerBinding.instance;
      final codec = const StandardMethodCodec();

      final byteDataSeek = codec.encodeMethodCall(
        const MethodCall('seekTo', {'positionMs': 45000}),
      );
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'com.example.music_app/widget',
        byteDataSeek,
        (ByteData? reply) {},
      );
      expect(soughtPos, equals(const Duration(seconds: 45)));

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
