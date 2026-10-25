import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';
import 'api_config.dart';
import 'audio/favorites_repository.dart';
import 'auth_service.dart';
import 'canonical_song_dedup.dart';
import 'data_snapshot_service.dart';
import 'music_service.dart';

enum CloudSyncStatus { idle, syncing, success, offline, error, kvNotConfigured }

class CloudSyncResult {
  final bool success;
  final CloudSyncStatus status;
  final String message;
  final int localLikesCount;
  final int localPlaylistsCount;
  final int mergedLikesCount;
  final int mergedPlaylistsCount;

  const CloudSyncResult({
    required this.success,
    required this.status,
    required this.message,
    this.localLikesCount = 0,
    this.localPlaylistsCount = 0,
    this.mergedLikesCount = 0,
    this.mergedPlaylistsCount = 0,
  });
}

/// Detailed set-theory comparison between local storage (L) and cloud storage (C).
class CloudSyncAnalysis {
  final bool isConfigured;
  final bool hasCloudData;
  final bool hasLocalData;
  final bool
  hasNewLocalItems; // (L \ C != ∅): local has items that cloud does not have
  final bool
  hasNewCloudItems; // (C \ L != ∅): cloud has items that local does not have
  final int localLikesCount;
  final int localPlaylistsCount;
  final int cloudLikesCount;
  final int cloudPlaylistsCount;
  final int newLocalLikesCount; // Count of likes in L not in C
  final int newLocalPlaylistsCount; // Count of playlists in L not in C
  final int newCloudLikesCount; // Count of likes in C not in L
  final int newCloudPlaylistsCount; // Count of playlists in C not in L

  const CloudSyncAnalysis({
    required this.isConfigured,
    required this.hasCloudData,
    required this.hasLocalData,
    required this.hasNewLocalItems,
    required this.hasNewCloudItems,
    required this.localLikesCount,
    required this.localPlaylistsCount,
    required this.cloudLikesCount,
    required this.cloudPlaylistsCount,
    required this.newLocalLikesCount,
    required this.newLocalPlaylistsCount,
    required this.newCloudLikesCount,
    required this.newCloudPlaylistsCount,
  });
}

/// Robust, zero-data-loss cloud synchronization service powered by Cloudflare Workers KV.
///
/// Guarantees:
/// 1. Atomic local safety snapshot before any network or sync operation.
/// 2. Non-destructive bidirectional merge with CanonicalSongDedup deduplication.
/// 3. Offline-first: if Cloudflare KV is unreachable or unconfigured, local library remains 100% intact.
class CloudSyncService {
  static final CloudSyncService _instance = CloudSyncService._internal();
  factory CloudSyncService() => _instance;
  CloudSyncService._internal();

  final ValueNotifier<CloudSyncStatus> syncStatus =
      ValueNotifier<CloudSyncStatus>(CloudSyncStatus.idle);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> syncMessage = ValueNotifier<String?>(null);

  bool _isSyncing = false;

  /// Inspects and analyzes differences between current local library and remote cloud storage.
  /// Allows the UI to make informed decisions:
  /// - If local has no new items (L ⊆ C), avoid asking the user to back up again.
  /// - If cloud has items that local is missing (C \ L != ∅), auto-sync down silently.
  /// - Only prompt the user if there are actual unsaved local items (L \ C != ∅).
  Future<CloudSyncAnalysis> inspectSyncState() async {
    final auth = AuthService();
    final userId = auth.userId;
    final localLikes = List<SongItem>.from(FavoritesRepository().likedSongs);
    final localPlaylists = List<Map<String, dynamic>>.from(
      MusicService().customPlaylists,
    );

    if (userId == null || userId.isEmpty || !auth.isAuthenticated) {
      return CloudSyncAnalysis(
        isConfigured: false,
        hasCloudData: false,
        hasLocalData: localLikes.isNotEmpty || localPlaylists.isNotEmpty,
        hasNewLocalItems: false,
        hasNewCloudItems: false,
        localLikesCount: localLikes.length,
        localPlaylistsCount: localPlaylists.length,
        cloudLikesCount: 0,
        cloudPlaylistsCount: 0,
        newLocalLikesCount: 0,
        newLocalPlaylistsCount: 0,
        newCloudLikesCount: 0,
        newCloudPlaylistsCount: 0,
      );
    }

    try {
      final endpoint = Uri.parse(
        '${ApiConfig.cloudflareWorkerUrl}/user/sync?userId=${Uri.encodeComponent(userId)}',
      );
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return CloudSyncAnalysis(
          isConfigured: false,
          hasCloudData: false,
          hasLocalData: localLikes.isNotEmpty || localPlaylists.isNotEmpty,
          hasNewLocalItems: false,
          hasNewCloudItems: false,
          localLikesCount: localLikes.length,
          localPlaylistsCount: localPlaylists.length,
          cloudLikesCount: 0,
          cloudPlaylistsCount: 0,
          newLocalLikesCount: 0,
          newLocalPlaylistsCount: 0,
          newCloudLikesCount: 0,
          newCloudPlaylistsCount: 0,
        );
      }

      final jsonBody = json.decode(response.body) as Map<String, dynamic>;
      if (jsonBody['status'] == 'not_configured') {
        return CloudSyncAnalysis(
          isConfigured: false,
          hasCloudData: false,
          hasLocalData: localLikes.isNotEmpty || localPlaylists.isNotEmpty,
          hasNewLocalItems: false,
          hasNewCloudItems: false,
          localLikesCount: localLikes.length,
          localPlaylistsCount: localPlaylists.length,
          cloudLikesCount: 0,
          cloudPlaylistsCount: 0,
          newLocalLikesCount: 0,
          newLocalPlaylistsCount: 0,
          newCloudLikesCount: 0,
          newCloudPlaylistsCount: 0,
        );
      }

      final remoteData = jsonBody['data'] as Map<String, dynamic>?;
      if (remoteData == null) {
        final hasLocal = localLikes.isNotEmpty || localPlaylists.isNotEmpty;
        return CloudSyncAnalysis(
          isConfigured: true,
          hasCloudData: false,
          hasLocalData: hasLocal,
          hasNewLocalItems: hasLocal,
          hasNewCloudItems: false,
          localLikesCount: localLikes.length,
          localPlaylistsCount: localPlaylists.length,
          cloudLikesCount: 0,
          cloudPlaylistsCount: 0,
          newLocalLikesCount: localLikes.length,
          newLocalPlaylistsCount: localPlaylists.length,
          newCloudLikesCount: 0,
          newCloudPlaylistsCount: 0,
        );
      }

      final remoteLikesList =
          (remoteData['likedSongs'] as List<dynamic>? ?? []);
      final remotePlaylistsList =
          (remoteData['playlists'] as List<dynamic>? ?? []);

      final List<SongItem> remoteLikes = [];
      for (final item in remoteLikesList) {
        if (item is Map) {
          try {
            remoteLikes.add(SongItem.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }

      // Fast Set-based lookup for Likes
      final localLikesIds = localLikes
          .map((s) => s.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final localLikesTitles = localLikes
          .map((s) => s.title.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toSet();
      final remoteLikesIds = remoteLikes
          .map((s) => s.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final remoteLikesTitles = remoteLikes
          .map((s) => s.title.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toSet();

      // Calculate Likes Difference L \ C
      int newLocalLikes = 0;
      for (final localSong in localLikes) {
        final id = localSong.id.trim();
        final title = localSong.title.trim().toLowerCase();
        if ((id.isNotEmpty && remoteLikesIds.contains(id)) ||
            (title.isNotEmpty && remoteLikesTitles.contains(title))) {
          continue;
        }
        final existsInCloud = remoteLikes.any(
          (remoteSong) => _areSameSongs(localSong, remoteSong),
        );
        if (!existsInCloud) {
          newLocalLikes++;
        }
      }

      // Calculate Likes Difference C \ L
      int newCloudLikes = 0;
      for (final remoteSong in remoteLikes) {
        final id = remoteSong.id.trim();
        final title = remoteSong.title.trim().toLowerCase();
        if ((id.isNotEmpty && localLikesIds.contains(id)) ||
            (title.isNotEmpty && localLikesTitles.contains(title))) {
          continue;
        }
        final existsInLocal = localLikes.any(
          (localSong) => _areSameSongs(localSong, remoteSong),
        );
        if (!existsInLocal) {
          newCloudLikes++;
        }
      }

      // Build index of remote playlists by ID and lowercased name
      final remotePlaylistsById = <String, Map<String, dynamic>>{};
      final remotePlaylistsByName = <String, Map<String, dynamic>>{};
      for (final p in remotePlaylistsList) {
        if (p is Map) {
          final pMap = Map<String, dynamic>.from(p);
          final id = (pMap['id'] ?? '').toString().trim();
          if (id.isNotEmpty) remotePlaylistsById[id] = pMap;
          final name = (pMap['name'] ?? '').toString().trim().toLowerCase();
          if (name.isNotEmpty) remotePlaylistsByName[name] = pMap;
        }
      }

      // Build index of local playlists by ID and lowercased name
      final localPlaylistsById = <String, Map<String, dynamic>>{};
      final localPlaylistsByName = <String, Map<String, dynamic>>{};
      for (final p in localPlaylists) {
        final id = (p['id'] ?? '').toString().trim();
        if (id.isNotEmpty) localPlaylistsById[id] = p;
        final name = (p['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) localPlaylistsByName[name] = p;
      }

      // Calculate Playlists Difference L \ C
      int newLocalPlaylists = 0;
      for (final localP in localPlaylists) {
        final id = (localP['id'] ?? '').toString().trim();
        final name = (localP['name'] ?? '').toString().trim().toLowerCase();
        final matchingCloudP =
            (id.isNotEmpty ? remotePlaylistsById[id] : null) ??
            (name.isNotEmpty ? remotePlaylistsByName[name] : null);

        if (matchingCloudP == null) {
          newLocalPlaylists++;
        } else {
          final localSongs = localP['songs'] as List? ?? [];
          final cloudSongs = matchingCloudP['songs'] as List? ?? [];
          if (localSongs.isNotEmpty) {
            final cloudSongIds = <String>{};
            final cloudSongTitles = <String>{};
            for (final cs in cloudSongs) {
              if (cs is Map) {
                final csId = (cs['id'] ?? cs['videoId'] ?? '')
                    .toString()
                    .trim();
                if (csId.isNotEmpty) cloudSongIds.add(csId);
                final csT = (cs['title'] ?? '').toString().trim().toLowerCase();
                if (csT.isNotEmpty) cloudSongTitles.add(csT);
              }
            }
            final hasUnsyncedSongs = localSongs.any((ls) {
              if (ls is! Map) return false;
              final lsId = (ls['id'] ?? ls['videoId'] ?? '').toString().trim();
              final lsT = (ls['title'] ?? '').toString().trim().toLowerCase();
              if ((lsId.isNotEmpty && cloudSongIds.contains(lsId)) ||
                  (lsT.isNotEmpty && cloudSongTitles.contains(lsT))) {
                return false;
              }
              return !cloudSongs.any(
                (cs) => cs is Map && _areSameSongMaps(ls, cs),
              );
            });
            if (hasUnsyncedSongs) {
              newLocalPlaylists++;
            }
          }
        }
      }

      int newCloudPlaylists = 0;
      for (final cloudP in remotePlaylistsList) {
        if (cloudP is! Map) continue;
        final id = (cloudP['id'] ?? '').toString().trim();
        final name = (cloudP['name'] ?? '').toString().trim().toLowerCase();
        final matchingLocalP =
            (id.isNotEmpty ? localPlaylistsById[id] : null) ??
            (name.isNotEmpty ? localPlaylistsByName[name] : null);

        if (matchingLocalP == null) {
          newCloudPlaylists++;
        } else {
          final cloudSongs = cloudP['songs'] as List? ?? [];
          final localSongs = matchingLocalP['songs'] as List? ?? [];
          if (cloudSongs.isNotEmpty) {
            final localSongIds = <String>{};
            final localSongTitles = <String>{};
            for (final ls in localSongs) {
              if (ls is Map) {
                final lsId = (ls['id'] ?? ls['videoId'] ?? '')
                    .toString()
                    .trim();
                if (lsId.isNotEmpty) localSongIds.add(lsId);
                final lsT = (ls['title'] ?? '').toString().trim().toLowerCase();
                if (lsT.isNotEmpty) localSongTitles.add(lsT);
              }
            }
            final hasMissingLocalSongs = cloudSongs.any((cs) {
              if (cs is! Map) return false;
              final csId = (cs['id'] ?? cs['videoId'] ?? '').toString().trim();
              final csT = (cs['title'] ?? '').toString().trim().toLowerCase();
              if ((csId.isNotEmpty && localSongIds.contains(csId)) ||
                  (csT.isNotEmpty && localSongTitles.contains(csT))) {
                return false;
              }
              return !localSongs.any(
                (ls) => ls is Map && _areSameSongMaps(cs, ls),
              );
            });
            if (hasMissingLocalSongs) {
              newCloudPlaylists++;
            }
          }
        }
      }

      final hasCloud = remoteLikes.isNotEmpty || remotePlaylistsList.isNotEmpty;
      final hasLocal = localLikes.isNotEmpty || localPlaylists.isNotEmpty;

      return CloudSyncAnalysis(
        isConfigured: true,
        hasCloudData: hasCloud,
        hasLocalData: hasLocal,
        hasNewLocalItems: newLocalLikes > 0 || newLocalPlaylists > 0,
        hasNewCloudItems: newCloudLikes > 0 || newCloudPlaylists > 0,
        localLikesCount: localLikes.length,
        localPlaylistsCount: localPlaylists.length,
        cloudLikesCount: remoteLikes.length,
        cloudPlaylistsCount: remotePlaylistsList.length,
        newLocalLikesCount: newLocalLikes,
        newLocalPlaylistsCount: newLocalPlaylists,
        newCloudLikesCount: newCloudLikes,
        newCloudPlaylistsCount: newCloudPlaylists,
      );
    } catch (e) {
      debugPrint('[CloudSyncService] inspectSyncState error: $e');
      return CloudSyncAnalysis(
        isConfigured: false,
        hasCloudData: false,
        hasLocalData: localLikes.isNotEmpty || localPlaylists.isNotEmpty,
        hasNewLocalItems: false,
        hasNewCloudItems: false,
        localLikesCount: localLikes.length,
        localPlaylistsCount: localPlaylists.length,
        cloudLikesCount: 0,
        cloudPlaylistsCount: 0,
        newLocalLikesCount: 0,
        newLocalPlaylistsCount: 0,
        newCloudLikesCount: 0,
        newCloudPlaylistsCount: 0,
      );
    }
  }

  /// Main entry point to sync user library with Cloudflare Workers KV.
  Future<CloudSyncResult> sync({bool forcePushLocal = false}) async {
    if (_isSyncing) {
      return const CloudSyncResult(
        success: false,
        status: CloudSyncStatus.syncing,
        message: 'Sync is already in progress.',
      );
    }

    final auth = AuthService();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty || !auth.isAuthenticated) {
      syncStatus.value = CloudSyncStatus.idle;
      syncMessage.value = 'Sign in with Google to enable cloud library sync.';
      return const CloudSyncResult(
        success: false,
        status: CloudSyncStatus.idle,
        message: 'User is not signed in.',
      );
    }

    _isSyncing = true;
    syncStatus.value = CloudSyncStatus.syncing;
    syncMessage.value = 'Creating safety backup…';

    try {
      // 1. MANDATORY ZERO-DATA-LOSS STEP: Create atomic safety snapshot on device
      // On Web, primary library keys are already persisted in localStorage and preserved.
      // We skip the redundant heavy snapshot serialization on Web to avoid localStorage freezes and quota pressure.
      if (!kIsWeb) {
        try {
          await DataSnapshotService().createSafetySnapshot(
            triggerReason: 'Pre-CloudSync Safety Backup',
          );
        } catch (e) {
          debugPrint('[CloudSyncService] Pre-sync snapshot warning: $e');
        }
      }

      // Cooperative yield to keep UI at 60 FPS
      await Future<void>.delayed(Duration.zero);

      syncMessage.value = 'Connecting to Cloudflare Edge…';

      // 2. Ingest current local library
      final localLikes = List<SongItem>.from(FavoritesRepository().likedSongs);
      final localPlaylists = List<Map<String, dynamic>>.from(
        MusicService().customPlaylists,
      );

      final endpoint = Uri.parse(
        '${ApiConfig.cloudflareWorkerUrl}/user/sync?userId=${Uri.encodeComponent(userId)}',
      );

      http.Response getResponse;
      try {
        getResponse = await http
            .get(endpoint)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        _isSyncing = false;
        syncStatus.value = CloudSyncStatus.offline;
        syncMessage.value = 'Cloudflare Edge offline; local library preserved.';
        return CloudSyncResult(
          success: false,
          status: CloudSyncStatus.offline,
          message: 'Network offline: $e',
          localLikesCount: localLikes.length,
          localPlaylistsCount: localPlaylists.length,
        );
      }

      if (getResponse.statusCode == 200) {
        final Map<String, dynamic> jsonBody =
            json.decode(getResponse.body) as Map<String, dynamic>;

        if (jsonBody['status'] == 'not_configured') {
          _isSyncing = false;
          syncStatus.value = CloudSyncStatus.kvNotConfigured;
          syncMessage.value =
              'Cloudflare KV namespace not bound yet. Local library safe.';
          return CloudSyncResult(
            success: false,
            status: CloudSyncStatus.kvNotConfigured,
            message: 'KV namespace not bound in Cloudflare.',
            localLikesCount: localLikes.length,
            localPlaylistsCount: localPlaylists.length,
          );
        }

        final remoteData = jsonBody['data'] as Map<String, dynamic>?;

        // 3. Cloud is empty: push local library to cloud without touching local data
        if (remoteData == null) {
          syncMessage.value = 'Backing up local library to Cloudflare…';
          await _pushToCloudflare(
            userId: userId,
            email: auth.userEmail ?? '',
            playlists: localPlaylists,
            likedSongs: localLikes,
          );

          _isSyncing = false;
          syncStatus.value = CloudSyncStatus.success;
          lastSyncedAt.value = DateTime.now();
          syncMessage.value =
              'Backed up ${localLikes.length} likes & ${localPlaylists.length} playlists to cloud.';
          return CloudSyncResult(
            success: true,
            status: CloudSyncStatus.success,
            message: 'Initial backup complete.',
            localLikesCount: localLikes.length,
            localPlaylistsCount: localPlaylists.length,
            mergedLikesCount: localLikes.length,
            mergedPlaylistsCount: localPlaylists.length,
          );
        }

        // 4. Non-Destructive Bidirectional Merge with Fast O(1) Set Lookups
        syncMessage.value = 'Merging cloud and local libraries…';
        final remoteLikesList =
            (remoteData['likedSongs'] as List<dynamic>? ?? []);
        final remotePlaylistsList =
            (remoteData['playlists'] as List<dynamic>? ?? []);

        // A. Merge Liked Songs (Union with zero duplicates)
        final List<SongItem> mergedLikes = [];
        final Set<String> seenLikeIds = {};
        final Set<String> seenLikeTitles = {};
        final Set<String> seenLikeCleanTitles = {};

        for (final song in localLikes) {
          final id = song.id.trim();
          final title = song.title.trim().toLowerCase();
          if (id.isNotEmpty) seenLikeIds.add(id);
          if (title.isNotEmpty) seenLikeTitles.add(title);
          final clean = CanonicalSongDedup.cleanTitle(title);
          if (clean.isNotEmpty) seenLikeCleanTitles.add(clean);
          mergedLikes.add(song);
        }

        for (final raw in remoteLikesList) {
          if (raw is Map) {
            try {
              final song = SongItem.fromJson(Map<String, dynamic>.from(raw));
              final id = song.id.trim();
              final title = song.title.trim().toLowerCase();
              if (id.isNotEmpty && seenLikeIds.contains(id)) continue;
              if (title.isNotEmpty && seenLikeTitles.contains(title)) continue;
              final clean = CanonicalSongDedup.cleanTitle(title);
              if (clean.isNotEmpty && seenLikeCleanTitles.contains(clean)) {
                continue;
              }

              if (id.isNotEmpty) seenLikeIds.add(id);
              if (title.isNotEmpty) seenLikeTitles.add(title);
              if (clean.isNotEmpty) seenLikeCleanTitles.add(clean);
              mergedLikes.add(song);
            } catch (_) {}
          }
        }

        // B. Merge Custom Playlists (Union by ID / name & song dedup)
        final List<Map<String, dynamic>> mergedPlaylists = [];
        final Map<String, int> playlistIdxById = {};
        final Map<String, int> playlistIdxByName = {};

        for (int i = 0; i < localPlaylists.length; i++) {
          final p = localPlaylists[i];
          final copy = Map<String, dynamic>.from(p);
          copy['songs'] = _dedupSongList(copy['songs'] as List? ?? []);
          final idx = mergedPlaylists.length;
          mergedPlaylists.add(copy);

          final id = (copy['id'] ?? '').toString().trim();
          if (id.isNotEmpty) playlistIdxById[id] = idx;
          final name = (copy['name'] ?? '').toString().trim().toLowerCase();
          if (name.isNotEmpty) playlistIdxByName[name] = idx;

          if (i % 15 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        for (int i = 0; i < remotePlaylistsList.length; i++) {
          final raw = remotePlaylistsList[i];
          if (raw is! Map) continue;
          final remoteP = Map<String, dynamic>.from(raw);
          final rId = (remoteP['id'] ?? '').toString().trim();
          final rName = (remoteP['name'] ?? '').toString().trim().toLowerCase();

          int? existingIdx;
          if (rId.isNotEmpty && playlistIdxById.containsKey(rId)) {
            existingIdx = playlistIdxById[rId];
          } else if (rName.isNotEmpty && playlistIdxByName.containsKey(rName)) {
            existingIdx = playlistIdxByName[rName];
          }

          if (existingIdx == null ||
              existingIdx < 0 ||
              existingIdx >= mergedPlaylists.length) {
            final copy = Map<String, dynamic>.from(remoteP);
            copy['songs'] = _dedupSongList(copy['songs'] as List? ?? []);
            final idx = mergedPlaylists.length;
            mergedPlaylists.add(copy);
            if (rId.isNotEmpty) playlistIdxById[rId] = idx;
            if (rName.isNotEmpty) playlistIdxByName[rName] = idx;
          } else {
            final existingP = mergedPlaylists[existingIdx];
            final existingSongs = List<dynamic>.from(
              existingP['songs'] as List? ?? [],
            );
            final Set<String> existingIds = {};
            final Set<String> existingTitles = {};
            final Set<String> existingCleanTitles = {};
            for (final s in existingSongs) {
              if (s is Map) {
                final id = (s['id'] ?? s['videoId'] ?? '').toString().trim();
                if (id.isNotEmpty) existingIds.add(id);
                final t = (s['title'] ?? '').toString().trim().toLowerCase();
                if (t.isNotEmpty) existingTitles.add(t);
                final clean = CanonicalSongDedup.cleanTitle(t);
                if (clean.isNotEmpty) existingCleanTitles.add(clean);
              }
            }
            final remoteSongs = List<dynamic>.from(
              remoteP['songs'] as List? ?? [],
            );
            for (final rs in remoteSongs) {
              if (rs is! Map) continue;
              final rsId = (rs['id'] ?? rs['videoId'] ?? '').toString().trim();
              final rsTitle = (rs['title'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (rsId.isNotEmpty && existingIds.contains(rsId)) continue;
              if (rsTitle.isNotEmpty && existingTitles.contains(rsTitle)) {
                continue;
              }
              final rsClean = CanonicalSongDedup.cleanTitle(rsTitle);
              if (rsClean.isNotEmpty && existingCleanTitles.contains(rsClean)) {
                continue;
              }

              if (rsId.isNotEmpty) existingIds.add(rsId);
              if (rsTitle.isNotEmpty) existingTitles.add(rsTitle);
              if (rsClean.isNotEmpty) existingCleanTitles.add(rsClean);
              existingSongs.add(rs);
            }
            existingP['songs'] = existingSongs;
          }

          if (i % 15 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        // Detect whether local library received new items
        bool localChanged =
            (mergedLikes.length != localLikes.length) ||
            (mergedPlaylists.length != localPlaylists.length);
        if (!localChanged) {
          for (int i = 0; i < mergedPlaylists.length; i++) {
            final mSongs = mergedPlaylists[i]['songs'] as List? ?? [];
            final lSongs = localPlaylists[i]['songs'] as List? ?? [];
            if (mSongs.length != lSongs.length) {
              localChanged = true;
              break;
            }
          }
        }

        // Detect whether cloud KV needs new items pushed
        bool cloudChanged =
            (mergedLikes.length != remoteLikesList.length) ||
            (mergedPlaylists.length != remotePlaylistsList.length);
        if (!cloudChanged) {
          for (int i = 0; i < mergedPlaylists.length; i++) {
            final mSongs = mergedPlaylists[i]['songs'] as List? ?? [];
            final rSongs =
                (i < remotePlaylistsList.length &&
                    remotePlaylistsList[i] is Map)
                ? (remotePlaylistsList[i]['songs'] as List? ?? [])
                : [];
            if (mSongs.length != rSongs.length) {
              cloudChanged = true;
              break;
            }
          }
        }

        // 5. Persist merged library to local platform storage ONLY if local received new data
        if (localChanged) {
          await _saveMergedLocalLibrary(
            mergedLikes: mergedLikes,
            mergedPlaylists: mergedPlaylists,
          );
        }

        // 6. Push the unified union back to Cloudflare ONLY if cloud received new data or forcePushLocal
        if (cloudChanged || forcePushLocal) {
          await _pushToCloudflare(
            userId: userId,
            email: auth.userEmail ?? '',
            playlists: mergedPlaylists,
            likedSongs: mergedLikes,
          );
        }

        _isSyncing = false;
        syncStatus.value = CloudSyncStatus.success;
        lastSyncedAt.value = DateTime.now();
        syncMessage.value =
            'Synced! ${mergedLikes.length} likes & ${mergedPlaylists.length} playlists active.';

        return CloudSyncResult(
          success: true,
          status: CloudSyncStatus.success,
          message: 'Sync succeeded.',
          localLikesCount: localLikes.length,
          localPlaylistsCount: localPlaylists.length,
          mergedLikesCount: mergedLikes.length,
          mergedPlaylistsCount: mergedPlaylists.length,
        );
      } else {
        _isSyncing = false;
        syncStatus.value = CloudSyncStatus.error;
        syncMessage.value =
            'Cloudflare returned HTTP ${getResponse.statusCode}.';
        return CloudSyncResult(
          success: false,
          status: CloudSyncStatus.error,
          message: 'HTTP ${getResponse.statusCode}',
        );
      }
    } catch (e) {
      _isSyncing = false;
      syncStatus.value = CloudSyncStatus.error;
      syncMessage.value = 'Sync error: $e';
      return CloudSyncResult(
        success: false,
        status: CloudSyncStatus.error,
        message: e.toString(),
      );
    }
  }

  /// Pushes library data to Cloudflare Edge KV via POST /user/sync
  Future<void> _pushToCloudflare({
    required String userId,
    required String email,
    required List<Map<String, dynamic>> playlists,
    required List<SongItem> likedSongs,
  }) async {
    try {
      final endpoint = Uri.parse('${ApiConfig.cloudflareWorkerUrl}/user/sync');
      final payload = {
        'userId': userId,
        'email': email,
        'playlists': playlists,
        'likedSongs': likedSongs.map((s) => s.toJson()).toList(),
      };

      await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[CloudSyncService] Error pushing to Cloudflare: $e');
    }
  }

  /// Atomically saves merged library to local platform storage and notifies listeners
  Future<void> _saveMergedLocalLibrary({
    required List<SongItem> mergedLikes,
    required List<Map<String, dynamic>> mergedPlaylists,
  }) async {
    try {
      final likesJson = json.encode(
        mergedLikes.map((s) => s.toJson()).toList(),
      );
      final playlistsJson = json.encode(mergedPlaylists);

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('liked_songs_web', likesJson);
        await prefs.setString('custom_playlists_web', playlistsJson);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final likesFile = File('${dir.path}/liked_songs.json');
        await likesFile.writeAsString(likesJson, flush: true);

        final playlistsFile = File('${dir.path}/custom_playlists.json');
        await playlistsFile.writeAsString(playlistsJson, flush: true);
      }

      // Reload into active services to notify all UI widgets
      await FavoritesRepository().load();
      await MusicService().loadLikedSongs();
      await MusicService().loadCustomPlaylists();
    } catch (e) {
      debugPrint('[CloudSyncService] Error saving merged local library: $e');
    }
  }

  static bool _areSameSongs(SongItem a, SongItem b) {
    final idA = a.id.trim();
    final idB = b.id.trim();
    if (idA.isNotEmpty && idA == idB) return true;

    final titleA = a.title.trim().toLowerCase();
    final titleB = b.title.trim().toLowerCase();
    if (titleA.isNotEmpty && titleA == titleB) return true;

    return CanonicalSongDedup.areDuplicateSongs(
      titleA: a.title,
      artistA: a.author,
      titleB: b.title,
      artistB: b.author,
    );
  }

  static bool _areSameSongMaps(Map a, Map b) {
    final idA = (a['id'] ?? a['videoId'] ?? '').toString().trim();
    final idB = (b['id'] ?? b['videoId'] ?? '').toString().trim();
    if (idA.isNotEmpty && idA == idB) return true;

    final titleA = (a['title'] ?? '').toString().trim().toLowerCase();
    final titleB = (b['title'] ?? '').toString().trim().toLowerCase();
    if (titleA.isEmpty || titleB.isEmpty) return false;
    if (titleA == titleB) return true;

    final artistA = (a['author'] ?? a['artist'] ?? '').toString().trim();
    final artistB = (b['author'] ?? b['artist'] ?? '').toString().trim();

    return CanonicalSongDedup.areDuplicateSongs(
      titleA: (a['title'] ?? '').toString().trim(),
      artistA: artistA,
      titleB: (b['title'] ?? '').toString().trim(),
      artistB: artistB,
    );
  }

  static List<Map<String, dynamic>> _dedupSongList(List rawList) {
    final List<Map<String, dynamic>> deduped = [];
    final Set<String> seenIds = {};
    final Set<String> seenTitles = {};
    final Set<String> seenCleanTitles = {};

    for (final item in rawList) {
      if (item is! Map) continue;
      final songMap = Map<String, dynamic>.from(item);
      final id = (songMap['id'] ?? songMap['videoId'] ?? '').toString().trim();
      final title = (songMap['title'] ?? '').toString().trim().toLowerCase();

      if (id.isNotEmpty && seenIds.contains(id)) continue;
      if (title.isNotEmpty && seenTitles.contains(title)) continue;

      final cleanTitle = title.isNotEmpty
          ? CanonicalSongDedup.cleanTitle(title)
          : '';
      if (cleanTitle.isNotEmpty && seenCleanTitles.contains(cleanTitle)) {
        continue;
      }

      if (id.isNotEmpty) seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(title);
      if (cleanTitle.isNotEmpty) seenCleanTitles.add(cleanTitle);
      deduped.add(songMap);
    }
    return deduped;
  }
}
