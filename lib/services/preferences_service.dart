import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ArtworkStyle { card, vinyl }
enum ScrubberStyle { waveform, classic }

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;

  PreferencesService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  // Settings
  bool _crossfadeEnabled = false;
  Color _themeColor = const Color(0xFFFA2D48); // Default DilSe Crimson
  double _cacheSizeMB = 500.0;
  String _customServerUrl = '';
  String _cloudflareWorkerUrl = '';
  ArtworkStyle _artworkStyle = ArtworkStyle.card;
  ScrubberStyle _scrubberStyle = ScrubberStyle.waveform;
  String _userName = '';
  bool _hasPromptedName = false;

  // Search History
  List<String> _searchHistory = [];

  // Listening History
  List<Map<String, String>> _listeningHistory = [];

  // Listening Preferences & Play Counts
  final Map<String, int> _artistPlayCounts = {};
  String _mostPlayedArtist = '';

  bool get isInitialized => _isInitialized;
  bool get crossfadeEnabled => _crossfadeEnabled;
  Color get themeColor => _themeColor;
  double get cacheSizeMB => _cacheSizeMB;
  String get customServerUrl => _customServerUrl;
  String get cloudflareWorkerUrl => _cloudflareWorkerUrl;
  ArtworkStyle get artworkStyle => _artworkStyle;
  ScrubberStyle get scrubberStyle => _scrubberStyle;
  String get userName => _userName.isEmpty ? 'Friend' : _userName;
  bool get hasCustomName => _userName.isNotEmpty;
  bool get hasPromptedName => _hasPromptedName;
  List<String> get searchHistory => _searchHistory;
  List<Map<String, String>> get listeningHistory => _listeningHistory;
  String get mostPlayedArtist => _mostPlayedArtist;
  int get totalPlays => _artistPlayCounts.values.fold(0, (a, b) => a + b);

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();

    _crossfadeEnabled = _prefs.getBool('crossfade') ?? false;
    int colorValue = _prefs.getInt('themeColor') ?? 0xFFFA2D48;
    _themeColor = Color(colorValue);
    _cacheSizeMB = _prefs.getDouble('cacheSizeMB') ?? 500.0;
    _customServerUrl = _prefs.getString('customServerUrl') ?? '';
    _cloudflareWorkerUrl = _prefs.getString('cloudflareWorkerUrl') ?? '';
    _searchHistory = _prefs.getStringList('searchHistory') ?? [];
    _mostPlayedArtist = _prefs.getString('mostPlayedArtist') ?? '';
    _userName = _prefs.getString('userName') ?? '';
    _hasPromptedName = _prefs.getBool('hasPromptedName') ?? false;
    final styleStr = _prefs.getString('artworkStyle') ?? 'card';
    _artworkStyle = styleStr == 'vinyl' ? ArtworkStyle.vinyl : ArtworkStyle.card;
    final scrubStr = _prefs.getString('scrubberStyle') ?? 'waveform';
    _scrubberStyle = scrubStr == 'classic' ? ScrubberStyle.classic : ScrubberStyle.waveform;

    final historyJson = _prefs.getString('listeningHistoryJson');
    if (historyJson != null && historyJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(historyJson);
        _listeningHistory = decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (_) {
        _listeningHistory = [];
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> recordSongPlay(String artist, String title) async {
    if (!_isInitialized) return; // BUG-3 fix: guard against pre-init calls
    if (artist.trim().isEmpty) return;

    final count = (_artistPlayCounts[artist] ?? 0) + 1;
    _artistPlayCounts[artist] = count;

    // Recalculate top artist
    String topArtist = _mostPlayedArtist;
    int maxCount = 0;
    _artistPlayCounts.forEach((key, val) {
      if (val > maxCount) {
        maxCount = val;
        topArtist = key;
      }
    });

    if (topArtist != _mostPlayedArtist) {
      _mostPlayedArtist = topArtist;
      await _prefs.setString('mostPlayedArtist', _mostPlayedArtist);
    }
    notifyListeners();
  }

  Future<void> setCrossfade(bool value) async {
    if (!_isInitialized) return;
    _crossfadeEnabled = value;
    await _prefs.setBool('crossfade', value);
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    if (!_isInitialized) return;
    _themeColor = color;
    await _prefs.setInt('themeColor', color.toARGB32());
    notifyListeners();
  }

  Future<void> setCacheSize(double sizeMB) async {
    _cacheSizeMB = sizeMB;
    await _prefs.setDouble('cacheSizeMB', sizeMB);
    notifyListeners();
  }

  Future<void> setCustomServerUrl(String url) async {
    _customServerUrl = url.trim();
    await _prefs.setString('customServerUrl', _customServerUrl);
    notifyListeners();
  }

  Future<void> setCloudflareWorkerUrl(String url) async {
    _cloudflareWorkerUrl = url.trim();
    await _prefs.setString('cloudflareWorkerUrl', _cloudflareWorkerUrl);
    notifyListeners();
  }

  Future<void> addToSearchHistory(String query) async {
    if (!_isInitialized) return; // BUG-3 fix
    if (query.trim().isEmpty) return;
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    await _prefs.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> removeFromSearchHistory(String query) async {
    _searchHistory.remove(query);
    await _prefs.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory.clear();
    await _prefs.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> addToListeningHistory(Map<String, String> song) async {
    if (!_isInitialized) return; // BUG-3 fix
    final id = song['id'];
    if (id == null || id.isEmpty) return;
    _listeningHistory.removeWhere((item) => item['id'] == id);
    _listeningHistory.insert(0, song);
    if (_listeningHistory.length > 50) {
      _listeningHistory = _listeningHistory.sublist(0, 50);
    }
    await _prefs.setString('listeningHistoryJson', json.encode(_listeningHistory));
    notifyListeners();
  }

  Future<void> clearListeningHistory() async {
    _listeningHistory.clear();
    await _prefs.remove('listeningHistoryJson');
    notifyListeners();
  }

  Future<void> setUserName(String name) async {
    _userName = name.trim();
    _hasPromptedName = true;
    await _prefs.setString('userName', _userName);
    await _prefs.setBool('hasPromptedName', true);
    notifyListeners();
  }

  Future<void> setArtworkStyle(ArtworkStyle style) async {
    _artworkStyle = style;
    await _prefs.setString('artworkStyle', style.name);
    notifyListeners();
  }

  Future<void> toggleArtworkStyle() async {
    final next = _artworkStyle == ArtworkStyle.card ? ArtworkStyle.vinyl : ArtworkStyle.card;
    await setArtworkStyle(next);
  }

  Future<void> setScrubberStyle(ScrubberStyle style) async {
    _scrubberStyle = style;
    await _prefs.setString('scrubberStyle', style.name);
    notifyListeners();
  }
}
