import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_app/services/auth_service.dart';
import 'package:music_app/services/preferences_service.dart';
import 'package:music_app/services/youtube_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthService & YouTubeLibraryService Verification', () {
    test(
      'AuthService initializes cleanly as singleton with unauthenticated state',
      () {
        final auth1 = AuthService();
        final auth2 = AuthService();
        expect(identical(auth1, auth2), isTrue);
        expect(auth1.isAuthenticated, isFalse);
        expect(auth1.currentUser, isNull);
        expect(auth1.accessToken, isNull);
        expect(auth1.userDisplayName, isNull);
      },
    );

    test('YouTubePlaylist parses JSON correctly from YouTube Data API', () {
      final sampleJson = {
        'id': 'PL1234567890abcdef',
        'snippet': {
          'title': 'My Favorite Telugu & Hindi Hits',
          'description': 'Curated personal playlist',
          'thumbnails': {
            'high': {'url': 'https://i.ytimg.com/vi/sample/hqdefault.jpg'},
          },
        },
        'contentDetails': {'itemCount': 42},
      };

      final playlist = YouTubePlaylist.fromJson(sampleJson);
      expect(playlist.id, equals('PL1234567890abcdef'));
      expect(playlist.title, equals('My Favorite Telugu & Hindi Hits'));
      expect(playlist.description, equals('Curated personal playlist'));
      expect(
        playlist.thumbnailUrl,
        equals('https://i.ytimg.com/vi/sample/hqdefault.jpg'),
      );
      expect(playlist.itemCount, equals(42));
    });

    test(
      'YouTubeLibraryService handles unauthenticated state gracefully',
      () async {
        final libService = YouTubeLibraryService();
        expect(libService.playlists, isEmpty);
        expect(libService.likedMusic, isEmpty);

        // Fetching when logged out returns empty without crashing
        final playlists = await libService.fetchUserPlaylists();
        expect(playlists, isEmpty);

        final liked = await libService.fetchLikedMusic();
        expect(liked, isEmpty);

        final resolvedLiked = await libService.fetchLikedMusicResolvedToJio();
        expect(resolvedLiked, isEmpty);

        libService.clear();
        expect(libService.playlists, isEmpty);
        expect(libService.likedMusic, isEmpty);
        expect(libService.likedMusicResolvedToJio, isEmpty);
      },
    );

    test(
      'YouTubeLibraryService resolves Liked Music to JioSaavn studio catalog in Demo mode',
      () async {
        final auth = AuthService();
        await auth.signInDemo(name: 'Demo Listener', email: 'demo@music.app');

        final libService = YouTubeLibraryService();
        final resolvedLiked = await libService.fetchLikedMusicResolvedToJio();

        expect(resolvedLiked, isNotEmpty);
        expect(resolvedLiked.length, equals(6));
        // Verify genuine studio titles (none are literal search queries)
        expect(resolvedLiked.first.title, equals('Kesariya'));
        expect(resolvedLiked.first.author, equals('Pritam, Arijit Singh'));

        // Verify mix synthesizers
        final supermix = await libService.fetchSupermix();
        expect(supermix, isNotEmpty);
        expect(
          supermix.any((s) => s.title.toLowerCase() == 'supermix'),
          isFalse,
        );

        final discoverMix = await libService.fetchDiscoverMix();
        expect(discoverMix, isNotEmpty);
        expect(
          discoverMix.any((s) => s.title.toLowerCase().contains('discover (')),
          isFalse,
        );

        final newReleaseMix = await libService.fetchNewReleaseMix();
        expect(newReleaseMix, isNotEmpty);
        expect(
          newReleaseMix.any((s) => s.title.toLowerCase() == 'new release mix'),
          isFalse,
        );

        final forgottenTracks = await libService.fetchForgottenTracks();
        expect(forgottenTracks, isNotEmpty);
        expect(
          forgottenTracks.any(
            (s) => s.title.toLowerCase() == 'forgotten tracks',
          ),
          isFalse,
        );

        libService.clear();
        expect(libService.likedMusicResolvedToJio, isEmpty);
        expect(libService.forgottenTracks, isEmpty);
        await auth.signOut();
      },
    );

    test(
      'AuthService Demo Mode signs in and exposes user details cleanly',
      () async {
        final auth = AuthService();
        await auth.signInDemo(name: 'Demo Listener', email: 'demo@music.app');

        expect(auth.isAuthenticated, isTrue);
        expect(auth.isDemoMode, isTrue);
        expect(auth.isGuestMode, isFalse);
        expect(auth.userDisplayName, equals('Demo Listener'));
        expect(auth.userEmail, equals('demo@music.app'));
        expect(auth.accessToken, isNotEmpty);

        // Switching to Guest Mode preserves demo session but reports guest
        auth.switchToGuestMode();
        expect(auth.isGuestMode, isTrue);
        expect(auth.isAuthenticated, isFalse);

        // Re-engaging Account Mode
        auth.switchToAccountMode();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.isGuestMode, isFalse);

        // Sign out
        await auth.signOut();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.isDemoMode, isFalse);
        expect(auth.userDisplayName, isNull);
      },
    );

    test(
      'AuthService restores persisted session from SharedPreferences on cold start',
      () async {
        SharedPreferences.setMockInitialValues({
          'dilse_auth_session_type': 'google',
          'dilse_auth_user_id': 'user_persisted_999',
          'dilse_auth_user_name': 'Charan Teja Persisted',
          'dilse_auth_user_email': 'charan.persisted@dilse.app',
          'dilse_auth_user_photo': 'https://example.com/photo.jpg',
          'dilse_auth_access_token': 'persisted_oauth_token_xyz',
        });

        final auth = AuthService();
        await auth.initialize();

        expect(auth.isAuthenticated, isTrue);
        expect(auth.isGuestMode, isFalse);
        expect(auth.userDisplayName, equals('Charan Teja Persisted'));
        expect(auth.userEmail, equals('charan.persisted@dilse.app'));
        expect(auth.userPhotoUrl, equals('https://example.com/photo.jpg'));
        expect(auth.accessToken, equals('persisted_oauth_token_xyz'));

        // Sign out cleans SharedPreferences
        await auth.signOut();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.userDisplayName, isNull);
      },
    );

    test(
      'AuthService restores session without explicit displayName falling back to email prefix and updates PreferencesService',
      () async {
        SharedPreferences.setMockInitialValues({
          'dilse_auth_session_type': 'google',
          'dilse_auth_user_id': '',
          'dilse_auth_user_name': '',
          'dilse_auth_user_email': 'dilseuser@gmail.com',
          'dilse_auth_user_photo': '',
        });

        await PreferencesService().init();
        final auth = AuthService();
        await auth.initialize();

        expect(auth.isAuthenticated, isTrue);
        expect(auth.userDisplayName, equals('dilseuser'));
        expect(auth.userId, equals('dilseuser@gmail.com'));
        expect(PreferencesService().userName, equals('dilseuser'));

        await auth.signOut();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.userDisplayName, isNull);
      },
    );
  });
}
