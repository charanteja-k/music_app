import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_service.dart';

class SnapshotResult {
  final bool success;
  final String? filePath;
  final int playlistCount;
  final int likedSongsCount;
  final int downloadCount;
  final String? errorMessage;

  SnapshotResult({
    required this.success,
    this.filePath,
    this.playlistCount = 0,
    this.likedSongsCount = 0,
    this.downloadCount = 0,
    this.errorMessage,
  });
}

class RestoreResult {
  final bool success;
  final int restoredPlaylists;
  final int restoredLikedSongs;
  final int restoredDownloads;
  final String? errorMessage;

  RestoreResult({
    required this.success,
    this.restoredPlaylists = 0,
    this.restoredLikedSongs = 0,
    this.restoredDownloads = 0,
    this.errorMessage,
  });
}

/// Independent, fail-safe service that captures and restores user library data
/// (playlists, liked songs, downloaded songs, listening history, and preferences)
/// to ensure complete zero-data-loss when switching between app versions.
class DataSnapshotService {
  static final DataSnapshotService _instance = DataSnapshotService._internal();
  factory DataSnapshotService() => _instance;
  DataSnapshotService._internal();

  static const String _snapshotFileName = 'dilse_safety_snapshot.json';

  /// Primary keys in SharedPreferences to capture in the safety snapshot.
  static const List<String> _trackedPrefKeys = [
    'listening_history',
    'listening_history_extended',
    'taste_profile',
    'followed_artists',
    'recent_searches',
    'theme_color',
    'audio_quality',
    'audio_format',
    'scrubber_style',
    'artwork_style',
    'custom_server_url',
    'cache_size_mb',
    'shake_bug_report_enabled',
    'auto_skip_silence',
    'equalizer_enabled',
    'equalizer_preset',
  ];

  /// Resolves the primary directory for saving snapshots.
  Future<Directory?> _getPrimarySnapshotDirectory() async {
    try {
      if (kIsWeb) return null;
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      debugPrint('[DataSnapshotService] Error getting primary directory: $e');
      return null;
    }
  }

  /// Resolves secondary persistent directories that survive app uninstallation
  /// on Android (such as external storage or public Downloads directory).
  Future<List<Directory>> _getPersistentBackupDirectories() async {
    final dirs = <Directory>[];
    if (kIsWeb || !Platform.isAndroid) return dirs;

    try {
      // 1. Android public Download directory
      final publicDownloadDir = Directory(
        '/storage/emulated/0/Download/DilSe_Backups',
      );
      dirs.add(publicDownloadDir);

      // 2. External storage directory
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final extBackupDir = Directory('${extDir.path}/DilSe_Backups');
        dirs.add(extBackupDir);
      }
    } catch (e) {
      debugPrint(
        '[DataSnapshotService] Error resolving external directories: $e',
      );
    }

    return dirs;
  }

  /// Captures an atomic snapshot of all user library assets and preferences.
  Future<SnapshotResult> createSafetySnapshot({
    String triggerReason = 'Manual Backup',
  }) async {
    try {
      String appVersion = 'unknown';
      try {
        final pkgInfo = await PackageInfo.fromPlatform();
        appVersion = '${pkgInfo.version}+${pkgInfo.buildNumber}';
      } catch (_) {}

      // 1. Ingest Custom Playlists
      List<dynamic> playlists = [];
      // 2. Ingest Liked Songs
      List<dynamic> likedSongs = [];
      // 3. Ingest Downloaded Songs
      List<dynamic> downloads = [];

      final primaryDir = await _getPrimarySnapshotDirectory();

      if (kIsWeb || primaryDir == null) {
        final prefs = await SharedPreferences.getInstance();
        final rawPlaylists = prefs.getString('custom_playlists_web');
        if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
          playlists = json.decode(rawPlaylists) as List<dynamic>;
        }
        final rawLiked = prefs.getString('liked_songs_web');
        if (rawLiked != null && rawLiked.isNotEmpty) {
          likedSongs = json.decode(rawLiked) as List<dynamic>;
        }
      } else {
        final playlistsFile = File('${primaryDir.path}/custom_playlists.json');
        if (await playlistsFile.exists()) {
          final content = await playlistsFile.readAsString();
          playlists = json.decode(content) as List<dynamic>;
        }

        final likedFile = File('${primaryDir.path}/liked_songs.json');
        if (await likedFile.exists()) {
          final content = await likedFile.readAsString();
          likedSongs = json.decode(content) as List<dynamic>;
        }

        final downloadsFile = File('${primaryDir.path}/downloads.json');
        if (await downloadsFile.exists()) {
          final content = await downloadsFile.readAsString();
          downloads = json.decode(content) as List<dynamic>;
        }
      }

      // If document files were empty but MusicService is currently loaded in memory,
      // harvest directly from active singleton
      if (playlists.isEmpty && MusicService().customPlaylists.isNotEmpty) {
        playlists = List.from(MusicService().customPlaylists);
      }
      if (likedSongs.isEmpty && MusicService().likedSongs.isNotEmpty) {
        likedSongs = List.from(MusicService().likedSongs);
      }
      if (downloads.isEmpty && MusicService().downloadedSongs.isNotEmpty) {
        downloads = List.from(MusicService().downloadedSongs);
      }

      // 4. Ingest SharedPreferences preferences & stats
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> preferencesMap = {};

      for (final key in _trackedPrefKeys) {
        if (prefs.containsKey(key)) {
          preferencesMap[key] = prefs.get(key);
        }
      }

      // Also gather all dynamic artist play count keys (e.g. 'artist_count_*')
      for (final key in prefs.getKeys()) {
        if (key.startsWith('artist_count_') ||
            key.startsWith('genre_count_') ||
            key.startsWith('lang_count_') ||
            key.startsWith('custom_theme_')) {
          preferencesMap[key] = prefs.get(key);
        }
      }

      // Assemble master snapshot package
      final snapshotPayload = {
        'schema_version': 1,
        'app_version': appVersion,
        'created_at': DateTime.now().toIso8601String(),
        'trigger_reason': triggerReason,
        'playlists': playlists,
        'liked_songs': likedSongs,
        'downloads': downloads,
        'preferences': preferencesMap,
      };

      final serializedJson = json.encode(snapshotPayload);

      String? primaryPath;

      if (!kIsWeb && primaryDir != null) {
        final primaryFile = File('${primaryDir.path}/$_snapshotFileName');
        await primaryFile.writeAsString(serializedJson, flush: true);
        primaryPath = primaryFile.path;

        // Write mirror to persistent directories that survive app uninstalls
        final persistentDirs = await _getPersistentBackupDirectories();
        for (final dir in persistentDirs) {
          try {
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
            final mirrorFile = File('${dir.path}/$_snapshotFileName');
            await mirrorFile.writeAsString(serializedJson, flush: true);
            debugPrint(
              '[DataSnapshotService] Mirrored safety snapshot to: ${mirrorFile.path}',
            );
          } catch (e) {
            debugPrint(
              '[DataSnapshotService] Mirror write skipped for ${dir.path}: $e',
            );
          }
        }
      } else {
        primaryPath = 'web_storage:primary_keys';
        try {
          final prefsInstance = await SharedPreferences.getInstance();
          // On Web, library data is already stored in primary keys ('custom_playlists_web', 'liked_songs_web').
          // If storing the duplicate snapshot exceeds browser 5MB quota, catch safely and clear stale snapshots
          // to protect browser localStorage headroom.
          await prefsInstance.setString(
            'dilse_safety_snapshot_web',
            serializedJson,
          );
          primaryPath = 'web_storage:dilse_safety_snapshot_web';
        } catch (storageErr) {
          debugPrint(
            '[DataSnapshotService] Web localStorage quota constrained ($storageErr). Primary keys remain intact.',
          );
          try {
            final prefsInstance = await SharedPreferences.getInstance();
            await prefsInstance.remove('dilse_safety_snapshot_web');
          } catch (_) {}
        }
      }

      debugPrint(
        '[DataSnapshotService] Snapshot captured successfully: '
        '${playlists.length} playlists, ${likedSongs.length} likes, ${downloads.length} downloads',
      );

      return SnapshotResult(
        success: true,
        filePath: primaryPath,
        playlistCount: playlists.length,
        likedSongsCount: likedSongs.length,
        downloadCount: downloads.length,
      );
    } catch (e) {
      debugPrint('[DataSnapshotService] Snapshot creation failed: $e');
      return SnapshotResult(success: false, errorMessage: e.toString());
    }
  }

  /// Finds the latest available snapshot file across primary and persistent external locations.
  Future<File?> findLatestSnapshotFile() async {
    if (kIsWeb) return null;

    final candidatePaths = <String>[];

    // 1. Primary app documents directory
    final primaryDir = await _getPrimarySnapshotDirectory();
    if (primaryDir != null) {
      candidatePaths.add('${primaryDir.path}/$_snapshotFileName');
    }

    // 2. Persistent external locations
    final persistentDirs = await _getPersistentBackupDirectories();
    for (final dir in persistentDirs) {
      candidatePaths.add('${dir.path}/$_snapshotFileName');
    }

    File? bestCandidate;
    DateTime? bestCandidateDate;

    for (final path in candidatePaths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final stat = await file.stat();
          if (bestCandidateDate == null ||
              stat.modified.isAfter(bestCandidateDate)) {
            bestCandidate = file;
            bestCandidateDate = stat.modified;
          }
        } catch (_) {}
      }
    }

    return bestCandidate;
  }

  /// Restores all library data, playlists, downloads, and preferences from a snapshot.
  Future<RestoreResult> restoreFromLatestSnapshot() async {
    try {
      String? jsonContent;

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonContent = prefs.getString('dilse_safety_snapshot_web');
        if (jsonContent == null || jsonContent.isEmpty) {
          final pRaw = prefs.getString('custom_playlists_web');
          final lRaw = prefs.getString('liked_songs_web');
          if ((pRaw != null && pRaw.isNotEmpty) ||
              (lRaw != null && lRaw.isNotEmpty)) {
            jsonContent = json.encode({
              'playlists': pRaw != null ? json.decode(pRaw) : [],
              'liked_songs': lRaw != null ? json.decode(lRaw) : [],
              'downloads': [],
              'preferences': {},
            });
          }
        }
      } else {
        final file = await findLatestSnapshotFile();
        if (file != null && await file.exists()) {
          jsonContent = await file.readAsString();
        }
      }

      if (jsonContent == null || jsonContent.isEmpty) {
        return RestoreResult(
          success: false,
          errorMessage: 'No backup snapshot found on device.',
        );
      }

      final Map<String, dynamic> data =
          json.decode(jsonContent) as Map<String, dynamic>;

      final playlists = (data['playlists'] as List<dynamic>? ?? []);
      final likedSongs = (data['liked_songs'] as List<dynamic>? ?? []);
      final downloads = (data['downloads'] as List<dynamic>? ?? []);
      final preferences = (data['preferences'] as Map<String, dynamic>? ?? {});

      final primaryDir = await _getPrimarySnapshotDirectory();

      if (kIsWeb || primaryDir == null) {
        final prefs = await SharedPreferences.getInstance();
        if (playlists.isNotEmpty) {
          await prefs.setString('custom_playlists_web', json.encode(playlists));
        }
        if (likedSongs.isNotEmpty) {
          await prefs.setString('liked_songs_web', json.encode(likedSongs));
        }
      } else {
        // 1. Restore Playlists
        if (playlists.isNotEmpty) {
          final playlistsFile = File(
            '${primaryDir.path}/custom_playlists.json',
          );
          await playlistsFile.writeAsString(
            json.encode(playlists),
            flush: true,
          );
        }

        // 2. Restore Liked Songs
        if (likedSongs.isNotEmpty) {
          final likedFile = File('${primaryDir.path}/liked_songs.json');
          await likedFile.writeAsString(json.encode(likedSongs), flush: true);
        }

        // 3. Restore Downloads metadata
        if (downloads.isNotEmpty) {
          final downloadsFile = File('${primaryDir.path}/downloads.json');
          await downloadsFile.writeAsString(
            json.encode(downloads),
            flush: true,
          );
        }
      }

      // 4. Restore SharedPreferences preferences
      if (preferences.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        for (final entry in preferences.entries) {
          final key = entry.key;
          final value = entry.value;

          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is List) {
            await prefs.setStringList(key, List<String>.from(value));
          }
        }
      }

      // Reload in-memory singleton caches in MusicService
      try {
        await MusicService().loadCustomPlaylists();
        await MusicService().loadLikedSongs();
        await MusicService().loadDownloadedSongs();
      } catch (e) {
        debugPrint(
          '[DataSnapshotService] Reloading MusicService in-memory caches: $e',
        );
      }

      debugPrint(
        '[DataSnapshotService] Restore finished successfully: '
        '${playlists.length} playlists, ${likedSongs.length} likes, ${downloads.length} downloads',
      );

      return RestoreResult(
        success: true,
        restoredPlaylists: playlists.length,
        restoredLikedSongs: likedSongs.length,
        restoredDownloads: downloads.length,
      );
    } catch (e) {
      debugPrint('[DataSnapshotService] Error restoring snapshot: $e');
      return RestoreResult(success: false, errorMessage: e.toString());
    }
  }

  /// Automatically scans for a backup snapshot on app boot if the library is empty
  /// (e.g. freshly installed rolled-back APK).
  Future<bool> autoRestoreIfEmpty() async {
    try {
      if (kIsWeb) return false;

      final docDir = await getApplicationDocumentsDirectory();
      final playlistsFile = File('${docDir.path}/custom_playlists.json');
      final likedFile = File('${docDir.path}/liked_songs.json');

      final hasPlaylists =
          await playlistsFile.exists() && (await playlistsFile.length() > 5);
      final hasLiked =
          await likedFile.exists() && (await likedFile.length() > 5);

      // If either file already exists with data, no auto-restore needed
      if (hasPlaylists || hasLiked) {
        return false;
      }

      // Check if persistent backup exists
      final snapshotFile = await findLatestSnapshotFile();
      if (snapshotFile == null || !await snapshotFile.exists()) {
        return false;
      }

      debugPrint(
        '[DataSnapshotService] Clean installation detected! Auto-hydrating library from snapshot...',
      );
      final result = await restoreFromLatestSnapshot();
      return result.success;
    } catch (e) {
      debugPrint(
        '[DataSnapshotService] autoRestoreIfEmpty check encountered: $e',
      );
      return false;
    }
  }
}
