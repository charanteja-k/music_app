import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'canonical_song_dedup.dart';
import 'spotify_import_service.dart';
import 'web_player_bridge.dart';

enum ArtworkStyle { card, vinyl }
enum ScrubberStyle { waveform, classic }

class TasteMatrix {
  final List<String> topArtists;
  final List<String> preferredLanguages;
  final Map<String, double> artistAffinities;
  final int totalPlays;
  final int totalSkips;

  const TasteMatrix({
    required this.topArtists,
    required this.preferredLanguages,
    required this.artistAffinities,
    required this.totalPlays,
    required this.totalSkips,
  });
}

class CircadianContext {
  final String title;
  final String subtitle;
  final String query;
  final String tag;
  final String emoji;

  const CircadianContext({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.tag,
    required this.emoji,
  });
}

class DailyMixConfig {
  final String title;
  final String subtitle;
  final String query;

  const DailyMixConfig({
    required this.title,
    required this.subtitle,
    required this.query,
  });
}

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;

  PreferencesService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  // Settings
  bool _crossfadeEnabled = true;
  int _crossfadeSeconds = 4;
  bool _smartCrossfadeEnabled = true;
  bool _fadeInOnStartEnabled = false;
  bool _equalizerEnabled = false;
  String _equalizerPreset = 'Flat';
  Map<int, double> _equalizerBands = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0};
  double _bassBoost = 0.0;
  double _virtualizer = 0.0;
  Color _themeColor = const Color(0xFFFA2D48); // Default DilSe Crimson
  double _cacheSizeMB = 500.0;
  String _customServerUrl = '';
  String _cloudflareWorkerUrl = '';
  ArtworkStyle _artworkStyle = ArtworkStyle.card;
  ScrubberStyle _scrubberStyle = ScrubberStyle.waveform;
  String _lyricsDisplayMode = 'original'; // 'original', 'pronunciation', 'dual'
  String _userName = '';
  bool _hasPromptedName = false;

  // Search History
  List<String> _searchHistory = [];

  // Listening History
  List<Map<String, String>> _listeningHistory = [];

  // Listening Preferences & Play Counts (Local Private Taste Matrix)
  final Map<String, int> _artistPlayCounts = {};
  final Map<String, int> _artistSkipCounts = {};
  List<String> _preferredLanguages = ['Hindi', 'Telugu', 'Tamil', 'Punjabi', 'English'];
  String _mostPlayedArtist = '';
  UserAudioProfile _audioProfile = const UserAudioProfile();

  bool get isInitialized => _isInitialized;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeSeconds => _crossfadeSeconds;
  bool get smartCrossfadeEnabled => _smartCrossfadeEnabled;
  bool get fadeInOnStartEnabled => _fadeInOnStartEnabled;
  bool get equalizerEnabled => _equalizerEnabled;
  String get equalizerPreset => _equalizerPreset;
  Map<int, double> get equalizerBands => Map.unmodifiable(_equalizerBands);
  double get bassBoost => _bassBoost;
  double get virtualizer => _virtualizer;
  Color get themeColor => _themeColor;
  double get cacheSizeMB => _cacheSizeMB;
  String get customServerUrl => _customServerUrl;
  String get cloudflareWorkerUrl => _cloudflareWorkerUrl;
  ArtworkStyle get artworkStyle => _artworkStyle;
  ScrubberStyle get scrubberStyle => _scrubberStyle;
  String get lyricsDisplayMode => _lyricsDisplayMode;
  String get userName => _userName.isEmpty ? 'Friend' : _userName;
  bool get hasCustomName => _userName.isNotEmpty;
  bool get hasPromptedName => _hasPromptedName;
  List<String> get searchHistory => _searchHistory;
  List<Map<String, String>> get listeningHistory => _listeningHistory;
  List<String> get preferredLanguages => _preferredLanguages;
  String get mostPlayedArtist => _mostPlayedArtist;
  UserAudioProfile get audioProfile => _audioProfile;
  int get totalPlays => _artistPlayCounts.values.fold(0, (a, b) => a + b);
  int get totalSkips => _artistSkipCounts.values.fold(0, (a, b) => a + b);

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();

    final hasUserSetCrossfade = _prefs.getBool('crossfade_user_set') ?? false;
    if (!hasUserSetCrossfade) {
      _crossfadeEnabled = true;
      _crossfadeSeconds = 4;
      await _prefs.setBool('crossfade', true);
      await _prefs.setInt('crossfadeSeconds', 4);
    } else {
      _crossfadeEnabled = _prefs.getBool('crossfade') ?? true;
      _crossfadeSeconds = _prefs.getInt('crossfadeSeconds') ?? 4;
    }
    _smartCrossfadeEnabled = _prefs.getBool('smartCrossfade') ?? true;
    _fadeInOnStartEnabled = _prefs.getBool('fadeInOnStart') ?? false;
    _equalizerEnabled = _prefs.getBool('equalizerEnabled') ?? false;
    _equalizerPreset = _prefs.getString('equalizerPreset') ?? 'Flat';
    _bassBoost = _prefs.getDouble('bassBoost') ?? 0.0;
    _virtualizer = _prefs.getDouble('virtualizer') ?? 0.0;
    final bandsJson = _prefs.getString('equalizerBandsJson');
    if (bandsJson != null && bandsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = json.decode(bandsJson);
        final map = <int, double>{};
        decoded.forEach((k, v) => map[int.parse(k)] = (v as num).toDouble());
        _equalizerBands = map;
      } catch (_) {}
    }

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
    _lyricsDisplayMode = _prefs.getString('lyricsDisplayMode') ?? 'original';

    final historyJson = _prefs.getString('listeningHistoryJson');
    if (historyJson != null && historyJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(historyJson);
        _listeningHistory = decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (_) {
        _listeningHistory = [];
      }
    }

    final playsJson = _prefs.getString('artistPlayCountsJson');
    if (playsJson != null && playsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = json.decode(playsJson);
        decoded.forEach((k, v) => _artistPlayCounts[k] = (v as num).toInt());
      } catch (_) {}
    }

    final skipsJson = _prefs.getString('artistSkipCountsJson');
    if (skipsJson != null && skipsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = json.decode(skipsJson);
        decoded.forEach((k, v) => _artistSkipCounts[k] = (v as num).toInt());
      } catch (_) {}
    }

    final langs = _prefs.getStringList('preferredLanguages');
    if (langs != null && langs.isNotEmpty) {
      _preferredLanguages = langs;
    }

    final profileJson = _prefs.getString('userAudioProfileJson');
    if (profileJson != null && profileJson.isNotEmpty) {
      try {
        _audioProfile = UserAudioProfile.fromJson(json.decode(profileJson));
      } catch (_) {}
    }

    _isInitialized = true;
    WebPlayerBridge.setEqualizer(_equalizerEnabled, _equalizerBands);
    notifyListeners();
  }

  Future<void> recordSongPlay(String artist, String title) async {
    if (!_isInitialized) return;
    if (artist.trim().isEmpty) return;

    final count = (_artistPlayCounts[artist] ?? 0) + 1;
    _artistPlayCounts[artist] = count;
    await _prefs.setString('artistPlayCountsJson', json.encode(_artistPlayCounts));

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

  Future<void> recordSongSkip(String artist) async {
    if (!_isInitialized) return;
    if (artist.trim().isEmpty) return;

    final count = (_artistSkipCounts[artist] ?? 0) + 1;
    _artistSkipCounts[artist] = count;
    await _prefs.setString('artistSkipCountsJson', json.encode(_artistSkipCounts));
    notifyListeners();
  }

  Future<void> setPreferredLanguages(List<String> langs) async {
    if (!_isInitialized) return;
    _preferredLanguages = List.from(langs);
    await _prefs.setStringList('preferredLanguages', _preferredLanguages);
    notifyListeners();
  }

  Future<void> setLyricsDisplayMode(String mode) async {
    _lyricsDisplayMode = mode;
    if (_isInitialized) {
      await _prefs.setString('lyricsDisplayMode', mode);
    }
    notifyListeners();
  }

  /// Builds the 100% private local "Taste Matrix" inspired by ListenBrainz/Troi
  TasteMatrix getTasteMatrix() {
    final affinities = <String, double>{};
    final allArtists = {..._artistPlayCounts.keys, ..._artistSkipCounts.keys};

    for (final artist in allArtists) {
      final plays = _artistPlayCounts[artist] ?? 0;
      final skips = _artistSkipCounts[artist] ?? 0;
      // Affinity: 2 points per play minus 1 point per skip
      affinities[artist] = (plays * 2.0) - (skips * 1.0);
    }

    final sorted = affinities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    List<String> top = sorted.take(5).map((e) => e.key).toList();
    if (top.isEmpty) {
      top = ['Arijit Singh', 'Anirudh Ravichander', 'Pritam', 'Sid Sriram', 'Shreya Ghoshal'];
    }

    return TasteMatrix(
      topArtists: top,
      preferredLanguages: List.unmodifiable(_preferredLanguages),
      artistAffinities: affinities,
      totalPlays: _artistPlayCounts.values.fold(0, (a, b) => a + b),
      totalSkips: _artistSkipCounts.values.fold(0, (a, b) => a + b),
    );
  }

  /// Returns user's top played artists based on on-device playback history
  List<String> getTopArtists({int limit = 5}) {
    final matrix = getTasteMatrix();
    return matrix.topArtists.take(limit).toList();
  }

  /// Circadian Time-of-Day Contextualizer:
  /// Morning (acoustic/ambient), Afternoon (upbeat/tempo), Evening (trending/hits), Late Night (lo-fi/slowed)
  CircadianContext getCircadianContext() {
    final hour = DateTime.now().hour;
    final primaryLang = _preferredLanguages.isNotEmpty ? _preferredLanguages.first : 'Telugu';

    if (hour >= 5 && hour < 12) {
      return CircadianContext(
        title: 'Morning Melodies',
        subtitle: 'Soft acoustic & ambient vibes to start your day',
        query: '$primaryLang Melodies',
        tag: 'MORNING',
        emoji: '🌅',
      );
    }
    if (hour >= 12 && hour < 17) {
      return CircadianContext(
        title: 'Afternoon Energy',
        subtitle: 'High-tempo beats and chartbusters to keep you grooving',
        query: '$primaryLang Fast Hits',
        tag: 'AFTERNOON',
        emoji: '⚡',
      );
    }
    if (hour >= 17 && hour < 22) {
      return CircadianContext(
        title: 'Evening Chill',
        subtitle: 'Trending relaxing tracks and chill evening vibes',
        query: '$primaryLang Top Hits',
        tag: 'EVENING',
        emoji: '🌆',
      );
    }
    return CircadianContext(
      title: 'Late Night Vibes',
      subtitle: 'Dreamy lo-fi and slowed melodies for quiet hours',
      query: '$primaryLang Slow Melodies',
      tag: 'LATE NIGHT',
      emoji: '🌙',
    );
  }

  String getTimeOfDayGreeting() {
    return getCircadianContext().title;
  }

  /// Multi-Seed Daily Mix Synthesizer (Inspired by Spotube)
  List<DailyMixConfig> getDailyMixConfigs() {
    final top = getTopArtists(limit: 5);
    final primaryLang = _preferredLanguages.isNotEmpty ? _preferredLanguages.first : 'Telugu';
    final artist1 = top.isNotEmpty ? top[0] : (primaryLang == 'Telugu' ? 'Sid Sriram' : 'Arijit Singh');
    final artist2 = top.length > 1 ? top[1] : (primaryLang == 'Telugu' ? 'Anirudh Ravichander' : 'Pritam');

    return [
      DailyMixConfig(
        title: 'Daily Mix 1',
        subtitle: '$artist1 & Friends',
        query: artist1,
      ),
      DailyMixConfig(
        title: 'Daily Mix 2',
        subtitle: '$artist2 Melodies',
        query: artist2,
      ),
      DailyMixConfig(
        title: 'Made For You',
        subtitle: 'Personalized Blend',
        query: top.isNotEmpty ? '$primaryLang ${top[0]}' : '$primaryLang Super Hits',
      ),
    ];
  }

  /// Ingests Exportify / Spotify tracks directly into local Taste Matrix & Audio Profile
  Future<void> importExportifyTasteData(List<ExportifyTrack> tracks) async {
    if (!_isInitialized || tracks.isEmpty) return;

    double totalDance = 0;
    double totalEnergy = 0;
    double totalValence = 0;
    double totalTempo = 0;
    double totalAcoustic = 0;
    int featureCount = 0;

    final langScores = <String, int>{};

    for (final track in tracks) {
      final artists = track.artistName
          .split(RegExp(r'[,;&/|]|(?:\s+feat\.?\s+)|\s+ft\.?\s+', caseSensitive: false))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty && a.length > 1);

      for (final artist in artists) {
        _artistPlayCounts[artist] = (_artistPlayCounts[artist] ?? 0) + 3;
      }

      final detected = CanonicalSongDedup.detectLanguage('${track.trackName} ${track.artistName}');
      if (detected != null) {
        langScores[detected] = (langScores[detected] ?? 0) + 1;
      }

      if (track.energy > 0 || track.valence > 0) {
        totalDance += track.danceability;
        totalEnergy += track.energy;
        totalValence += track.valence;
        totalTempo += track.tempo;
        totalAcoustic += track.acousticness;
        featureCount++;
      }
    }

    if (featureCount > 0) {
      _audioProfile = UserAudioProfile(
        avgDanceability: totalDance / featureCount,
        avgEnergy: totalEnergy / featureCount,
        avgValence: totalValence / featureCount,
        avgTempo: totalTempo / featureCount,
        avgAcousticness: totalAcoustic / featureCount,
        tracksAnalyzed: featureCount,
      );
      await _prefs.setString('userAudioProfileJson', json.encode(_audioProfile.toJson()));
    }

    if (langScores.isNotEmpty) {
      final sortedLangs = langScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final topDetected = sortedLangs.take(3).map((e) => e.key).toList();
      for (final l in topDetected) {
        if (!_preferredLanguages.contains(l)) {
          _preferredLanguages.insert(0, l);
        } else {
          _preferredLanguages.remove(l);
          _preferredLanguages.insert(0, l);
        }
      }
      await _prefs.setStringList('preferredLanguages', _preferredLanguages);
    }

    await _prefs.setString('artistPlayCountsJson', json.encode(_artistPlayCounts));

    String topArtist = _mostPlayedArtist;
    int maxCount = 0;
    _artistPlayCounts.forEach((key, val) {
      if (val > maxCount) {
        maxCount = val;
        topArtist = key;
      }
    });
    if (topArtist.isNotEmpty) {
      _mostPlayedArtist = topArtist;
      await _prefs.setString('mostPlayedArtist', _mostPlayedArtist);
    }

    notifyListeners();
  }

  /// Generates dynamic personalized search seeds for the Home Screen
  List<String> getPersonalizedMixSeeds() {
    final mixes = getDailyMixConfigs();
    final vibe = getCircadianContext();
    return [
      mixes[0].query,
      mixes[1].query,
      vibe.query,
    ];
  }

  /// Caches home feed data with timestamp TTL (6 hours)
  Future<void> cacheHomeFeed(String key, String jsonData) async {
    if (!_isInitialized) return;
    await _prefs.setString('home_cache_$key', jsonData);
    await _prefs.setInt('home_cache_time_$key', DateTime.now().millisecondsSinceEpoch);
  }

  /// Retrieves cached home feed data if less than 6 hours old
  String? getCachedHomeFeed(String key) {
    if (!_isInitialized) return null;
    final timestamp = _prefs.getInt('home_cache_time_$key');
    if (timestamp == null) return null;

    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    if (age.inHours >= 6) return null; // Stale

    return _prefs.getString('home_cache_$key');
  }

  Future<void> setCrossfade(bool value) async {
    if (!_isInitialized) return;
    _crossfadeEnabled = value;
    await _prefs.setBool('crossfade', value);
    await _prefs.setBool('crossfade_user_set', true);
    notifyListeners();
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    if (!_isInitialized) return;
    _crossfadeSeconds = seconds.clamp(1, 12);
    await _prefs.setInt('crossfadeSeconds', _crossfadeSeconds);
    await _prefs.setBool('crossfade_user_set', true);
    notifyListeners();
  }

  Future<void> setSmartCrossfade(bool value) async {
    if (!_isInitialized) return;
    _smartCrossfadeEnabled = value;
    await _prefs.setBool('smartCrossfade', value);
    notifyListeners();
  }

  Future<void> setFadeInOnStart(bool value) async {
    if (!_isInitialized) return;
    _fadeInOnStartEnabled = value;
    await _prefs.setBool('fadeInOnStart', value);
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool value) async {
    if (!_isInitialized) return;
    _equalizerEnabled = value;
    await _prefs.setBool('equalizerEnabled', value);
    WebPlayerBridge.setEqualizer(_equalizerEnabled, _equalizerBands);
    notifyListeners();
  }

  Future<void> setEqualizerPreset(String preset, Map<int, double> bands) async {
    if (!_isInitialized) return;
    _equalizerPreset = preset;
    _equalizerBands = Map<int, double>.from(bands);
    await _prefs.setString('equalizerPreset', preset);
    final mapForJson = _equalizerBands.map((k, v) => MapEntry(k.toString(), v));
    await _prefs.setString('equalizerBandsJson', json.encode(mapForJson));
    WebPlayerBridge.setEqualizer(_equalizerEnabled, _equalizerBands);
    notifyListeners();
  }

  Future<void> setEqualizerBand(int bandIndex, double gainDb) async {
    if (!_isInitialized) return;
    _equalizerBands[bandIndex] = gainDb.clamp(-12.0, 12.0);
    _equalizerPreset = 'Custom';
    await _prefs.setString('equalizerPreset', 'Custom');
    final mapForJson = _equalizerBands.map((k, v) => MapEntry(k.toString(), v));
    await _prefs.setString('equalizerBandsJson', json.encode(mapForJson));
    WebPlayerBridge.setEqualizer(_equalizerEnabled, _equalizerBands);
    notifyListeners();
  }

  Future<void> setBassBoost(double value) async {
    if (!_isInitialized) return;
    _bassBoost = value.clamp(0.0, 1.0);
    await _prefs.setDouble('bassBoost', _bassBoost);
    notifyListeners();
  }

  Future<void> setVirtualizer(double value) async {
    if (!_isInitialized) return;
    _virtualizer = value.clamp(0.0, 1.0);
    await _prefs.setDouble('virtualizer', _virtualizer);
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    if (!_isInitialized) return;
    _themeColor = color;
    await _prefs.setInt('themeColor', color.toARGB32());
    notifyListeners();
  }

  Future<void> setCacheSize(double sizeMB) async {
    if (!_isInitialized) return;
    _cacheSizeMB = sizeMB;
    await _prefs.setDouble('cacheSizeMB', sizeMB);
    notifyListeners();
  }

  Future<void> setCustomServerUrl(String url) async {
    if (!_isInitialized) return;
    _customServerUrl = url.trim();
    await _prefs.setString('customServerUrl', _customServerUrl);
    notifyListeners();
  }

  Future<void> setCloudflareWorkerUrl(String url) async {
    if (!_isInitialized) return;
    _cloudflareWorkerUrl = url.trim();
    await _prefs.setString('cloudflareWorkerUrl', _cloudflareWorkerUrl);
    notifyListeners();
  }

  Future<void> addToSearchHistory(String query) async {
    if (!_isInitialized) return;
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
    if (!_isInitialized) return;
    _searchHistory.remove(query);
    await _prefs.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    if (!_isInitialized) return;
    _searchHistory.clear();
    await _prefs.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> addToListeningHistory(Map<String, String> song) async {
    if (!_isInitialized) return;
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
    if (!_isInitialized) return;
    _listeningHistory.clear();
    await _prefs.remove('listeningHistoryJson');
    notifyListeners();
  }

  Future<void> setUserName(String name) async {
    if (!_isInitialized) return;
    _userName = name.trim();
    _hasPromptedName = true;
    await _prefs.setString('userName', _userName);
    await _prefs.setBool('hasPromptedName', true);
    notifyListeners();
  }

  Future<void> setArtworkStyle(ArtworkStyle style) async {
    if (!_isInitialized) return;
    _artworkStyle = style;
    await _prefs.setString('artworkStyle', style.name);
    notifyListeners();
  }

  Future<void> toggleArtworkStyle() async {
    final next = _artworkStyle == ArtworkStyle.card ? ArtworkStyle.vinyl : ArtworkStyle.card;
    await setArtworkStyle(next);
  }

  Future<void> setScrubberStyle(ScrubberStyle style) async {
    if (!_isInitialized) return;
    _scrubberStyle = style;
    await _prefs.setString('scrubberStyle', style.name);
    notifyListeners();
  }
}
