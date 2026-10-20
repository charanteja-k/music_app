import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// Authentication Service managing Google Sign-In with standard email profile access.
///
/// Invariant: Strictly READ-ONLY. Requests ONLY `email`.
/// Never requests sensitive scopes or write permissions; works globally for any Google account.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Default configured OAuth 2.0 Client ID for DilSe
  static const String defaultClientId =
      '130201428767-i1tt2et39of41d7mfs4j3d7fmnab5ug4.apps.googleusercontent.com';

  static const String _prefSessionType = 'dilse_auth_session_type';
  static const String _prefUserId = 'dilse_auth_user_id';
  static const String _prefUserName = 'dilse_auth_user_name';
  static const String _prefUserEmail = 'dilse_auth_user_email';
  static const String _prefUserPhoto = 'dilse_auth_user_photo';
  static const String _prefAccessToken = 'dilse_auth_access_token';

  GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? defaultClientId : null,
    serverClientId: kIsWeb ? null : defaultClientId,
    scopes: const <String>['email'],
  );

  GoogleSignInAccount? _currentUser;
  String? _accessToken;
  bool _isInitializing = false;
  bool _isDemoMode = false;
  bool _isExplicitGuestMode = false;
  String? _clientId = defaultClientId;
  String? _lastError;
  bool _isMissingClientId = false;

  // Cached user fields (restored from SharedPreferences)
  String? _cachedUserId;
  String? _cachedUserName;
  String? _cachedUserEmail;
  String? _cachedUserPhoto;
  bool _hasCachedGoogleUser = false;

  // Demo user fields
  String? _demoUserId;
  String? _demoUserName;
  String? _demoUserEmail;
  String? _demoUserPhotoUrl;

  /// Current signed-in Google account (null if signed out or in demo mode).
  GoogleSignInAccount? get currentUser => _currentUser;

  /// Whether a user is currently signed in (real, cached, or demo).
  bool get isAuthenticated =>
      !_isExplicitGuestMode &&
      (_currentUser != null || _hasCachedGoogleUser || _isDemoMode);

  /// Convenient alias for isAuthenticated.
  bool get isSignedIn => isAuthenticated;

  /// Whether Guest Mode is currently active.
  bool get isGuestMode => !isAuthenticated;

  /// Whether running in Demo Account mode for UI testing.
  bool get isDemoMode => _isDemoMode && !_isExplicitGuestMode;

  /// Last error message encountered during sign-in, if any.
  String? get lastError => _lastError;

  /// Whether sign-in failed specifically due to a missing OAuth Client ID.
  bool get isMissingClientId => _isMissingClientId;

  /// Configured OAuth 2.0 Web Client ID.
  String? get configuredClientId => _clientId;

  /// Current cached OAuth 2.0 access token.
  String? get accessToken => _accessToken;

  /// Display name of the signed-in user.
  String? get userDisplayName =>
      _currentUser?.displayName ??
      (_isDemoMode ? _demoUserName : _cachedUserName);

  /// Email address of the signed-in user.
  String? get userEmail =>
      _currentUser?.email ?? (_isDemoMode ? _demoUserEmail : _cachedUserEmail);

  /// Profile photo URL of the signed-in user.
  String? get userPhotoUrl =>
      _currentUser?.photoUrl ??
      (_isDemoMode ? _demoUserPhotoUrl : _cachedUserPhoto);

  /// Unique Google account identifier.
  String? get userId =>
      _currentUser?.id ?? (_isDemoMode ? _demoUserId : _cachedUserId);

  /// Stream of user sign-in state changes.
  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged;

  Future<void> _persistSession({
    required String type,
    String? id,
    String? name,
    String? email,
    String? photo,
    String? token,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSessionType, type);
      if (id != null) {
        await prefs.setString(_prefUserId, id);
      } else {
        await prefs.remove(_prefUserId);
      }
      if (name != null) {
        await prefs.setString(_prefUserName, name);
      } else {
        await prefs.remove(_prefUserName);
      }
      if (email != null) {
        await prefs.setString(_prefUserEmail, email);
      } else {
        await prefs.remove(_prefUserEmail);
      }
      if (photo != null) {
        await prefs.setString(_prefUserPhoto, photo);
      } else {
        await prefs.remove(_prefUserPhoto);
      }
      if (token != null) {
        await prefs.setString(_prefAccessToken, token);
      } else {
        await prefs.remove(_prefAccessToken);
      }
    } catch (e) {
      debugPrint('[AuthService] Error persisting session: $e');
    }
  }

  Future<void> _clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefSessionType);
      await prefs.remove(_prefUserId);
      await prefs.remove(_prefUserName);
      await prefs.remove(_prefUserEmail);
      await prefs.remove(_prefUserPhoto);
      await prefs.remove(_prefAccessToken);
    } catch (e) {
      debugPrint('[AuthService] Error clearing session: $e');
    }
  }

  /// Configures custom Google OAuth Client ID and re-initializes client.
  void configure({String? clientId}) {
    if (clientId != null && clientId.trim().isNotEmpty) {
      _clientId = clientId.trim();
      _isMissingClientId = false;
      _googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? _clientId : null,
        serverClientId: kIsWeb ? null : _clientId,
        scopes: const <String>['email'],
      );
    }
  }

  /// Initializes authentication listener and attempts silent sign-in.
  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // 1. Immediately hydrate cached session from SharedPreferences for instant UI rendering
      final prefs = await SharedPreferences.getInstance();
      final savedType = prefs.getString(_prefSessionType);
      if (savedType == 'demo') {
        _isDemoMode = true;
        _isExplicitGuestMode = false;
        _hasCachedGoogleUser = false;
        _demoUserId = prefs.getString(_prefUserId) ?? 'demo_user_cached';
        _demoUserName = prefs.getString(_prefUserName) ?? 'Charan Teja (Demo)';
        _demoUserEmail =
            prefs.getString(_prefUserEmail) ?? 'charanteja.demo@gmail.com';
        _demoUserPhotoUrl =
            prefs.getString(_prefUserPhoto) ??
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=120';
        _accessToken = prefs.getString(_prefAccessToken) ?? 'demo_oauth_token';
        notifyListeners();
      } else if (savedType == 'google') {
        _hasCachedGoogleUser = true;
        _isDemoMode = false;
        _isExplicitGuestMode = false;
        _cachedUserId = prefs.getString(_prefUserId);
        _cachedUserName = prefs.getString(_prefUserName);
        _cachedUserEmail = prefs.getString(_prefUserEmail);
        _cachedUserPhoto = prefs.getString(_prefUserPhoto);
        _accessToken = prefs.getString(_prefAccessToken);
        notifyListeners();
      } else if (savedType == 'guest') {
        _isExplicitGuestMode = true;
        notifyListeners();
      }

      // 2. Set up GoogleSignIn stream listener
      _googleSignIn.onCurrentUserChanged.listen((
        GoogleSignInAccount? account,
      ) async {
        _currentUser = account;
        if (account != null) {
          _isDemoMode = false;
          _isExplicitGuestMode = false;
          _hasCachedGoogleUser = true;
          _cachedUserId = account.id;
          _cachedUserName = account.displayName;
          _cachedUserEmail = account.email;
          _cachedUserPhoto = account.photoUrl;
          final auth = await account.authentication;
          _accessToken = auth.accessToken;
          await _persistSession(
            type: 'google',
            id: account.id,
            name: account.displayName,
            email: account.email,
            photo: account.photoUrl,
            token: _accessToken,
          );
          debugPrint(
            '[AuthService] User signed in: ${account.email} (${account.displayName})',
          );
          // Auto-sync library non-destructively in the background
          CloudSyncService().sync().catchError((e) {
            debugPrint('[AuthService] Auto-sync error: $e');
            return const CloudSyncResult(
              success: false,
              status: CloudSyncStatus.error,
              message: 'Auto-sync failed',
            );
          });
        } else if (!_isDemoMode && !_hasCachedGoogleUser) {
          _accessToken = null;
          debugPrint('[AuthService] User signed out');
        }
        notifyListeners();
      });

      // 3. Attempt silent sign-in if Google was previously active or if not in demo mode
      if (savedType == 'google' || savedType == null) {
        await _googleSignIn.signInSilently().catchError((e) {
          debugPrint('[AuthService] Silent sign-in skipped: $e');
          return null;
        });
      }
    } catch (e) {
      debugPrint('[AuthService] Init error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Triggers the native Google Sign-In interactive modal.
  /// Returns `true` if authentication succeeded, `false` if cancelled or failed.
  Future<bool> signIn() async {
    _lastError = null;
    _isMissingClientId = false;

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        debugPrint('[AuthService] Sign-in cancelled by user');
        return false;
      }

      _currentUser = account;
      _isDemoMode = false;
      _isExplicitGuestMode = false;
      _hasCachedGoogleUser = true;
      _cachedUserId = account.id;
      _cachedUserName = account.displayName;
      _cachedUserEmail = account.email;
      _cachedUserPhoto = account.photoUrl;
      final auth = await account.authentication;
      _accessToken = auth.accessToken;
      await _persistSession(
        type: 'google',
        id: account.id,
        name: account.displayName,
        email: account.email,
        photo: account.photoUrl,
        token: _accessToken,
      );
      // Auto-sync library non-destructively in the background
      CloudSyncService().sync().catchError((e) {
        debugPrint('[AuthService] Auto-sync error: $e');
        return const CloudSyncResult(
          success: false,
          status: CloudSyncStatus.error,
          message: 'Auto-sync failed',
        );
      });
      notifyListeners();
      return true;
    } catch (e) {
      final err = e.toString();
      if (err.contains('popup_blocked') || err.contains('blocked')) {
        _lastError =
            'Google Sign-In popup was blocked by your browser. Please allow popups for localhost and retry.';
      } else if (err.contains('origin') ||
          err.contains('idpiframe') ||
          err.contains('unauthorized_client') ||
          err.contains('403')) {
        _lastError =
            'OAuth origin mismatch: Please add http://localhost:3000 to Authorized JavaScript Origins in Google Cloud Console.';
      } else if (err.contains('popup_closed') || err.contains('closed')) {
        _lastError =
            'Sign-in popup was closed before completing authentication.';
      } else {
        _lastError = err;
      }
      if (err.contains('clientId') ||
          err.contains('Missing') ||
          err.contains('channel-error') ||
          err.contains('Unimplemented')) {
        _isMissingClientId = true;
      }
      debugPrint('[AuthService] Sign-in failed: $e');
      return false;
    }
  }

  /// Signs in with an authentic Demo Account for immediate UI testing & verification.
  Future<bool> signInDemo({String? name, String? email}) async {
    _currentUser = null;
    _hasCachedGoogleUser = false;
    _isDemoMode = true;
    _isExplicitGuestMode = false;
    _demoUserId = 'demo_user_${DateTime.now().millisecondsSinceEpoch}';
    _demoUserName = name ?? 'Charan Teja (Demo)';
    _demoUserEmail = email ?? 'charanteja.demo@gmail.com';
    _demoUserPhotoUrl =
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=120';
    _accessToken = 'demo_oauth_token';
    _lastError = null;
    _isMissingClientId = false;
    await _persistSession(
      type: 'demo',
      id: _demoUserId,
      name: _demoUserName,
      email: _demoUserEmail,
      photo: _demoUserPhotoUrl,
      token: _accessToken,
    );
    notifyListeners();
    return true;
  }

  /// Switches active session to Guest Mode without discarding saved account tokens.
  void switchToGuestMode() {
    _isExplicitGuestMode = true;
    _persistSession(type: 'guest');
    notifyListeners();
  }

  /// Re-engages Account Mode from Guest Mode.
  void switchToAccountMode() {
    if (_currentUser != null || _hasCachedGoogleUser || _isDemoMode) {
      _isExplicitGuestMode = false;
      final type = _isDemoMode ? 'demo' : 'google';
      _persistSession(
        type: type,
        id: userId,
        name: userDisplayName,
        email: userEmail,
        photo: userPhotoUrl,
        token: _accessToken,
      );
      notifyListeners();
    }
  }

  /// Signs out of Google account, clearing local session tokens.
  Future<void> signOut() async {
    try {
      if (_currentUser != null) {
        await _googleSignIn.signOut();
      }
      _currentUser = null;
      _hasCachedGoogleUser = false;
      _isDemoMode = false;
      _isExplicitGuestMode = false;
      _accessToken = null;
      _cachedUserId = null;
      _cachedUserName = null;
      _cachedUserEmail = null;
      _cachedUserPhoto = null;
      _demoUserId = null;
      _demoUserName = null;
      _demoUserEmail = null;
      _demoUserPhotoUrl = null;
      await _clearPersistedSession();
      notifyListeners();
      debugPrint('[AuthService] Successfully signed out');
    } catch (e) {
      debugPrint('[AuthService] Sign-out error: $e');
    }
  }

  /// Returns a fresh valid OAuth 2.0 access token, refreshing if necessary.
  Future<String?> getFreshAccessToken() async {
    if (_isDemoMode) return _accessToken;
    if (_currentUser != null) {
      try {
        final auth = await _currentUser!.authentication;
        _accessToken = auth.accessToken;
        if (_accessToken != null) {
          _persistSession(
            type: 'google',
            id: _currentUser!.id,
            name: _currentUser!.displayName,
            email: _currentUser!.email,
            photo: _currentUser!.photoUrl,
            token: _accessToken,
          );
        }
        return _accessToken;
      } catch (e) {
        debugPrint('[AuthService] Error refreshing access token: $e');
        return _accessToken;
      }
    }
    return _accessToken;
  }
}
