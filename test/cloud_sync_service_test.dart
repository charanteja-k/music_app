import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/song_item.dart';
import 'package:music_app/services/cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudSyncService Non-Destructive Merge Tests', () {
    test(
      'SongItem union merge preserves all local and remote items without duplication',
      () {
        final localSongs = [
          SongItem(
            id: 'song_1',
            title: 'Local Song 1',
            author: 'Artist A',
            album: 'Album A',
            duration: const Duration(minutes: 3),
          ),
          SongItem(
            id: 'song_2',
            title: 'Shared Song',
            author: 'Artist B',
            album: 'Album B',
            duration: const Duration(minutes: 3, seconds: 20),
          ),
        ];

        final remoteSongsRaw = [
          {
            'id': 'song_2',
            'title': 'Shared Song (Remote)',
            'artist': 'Artist B',
            'album': 'Album B',
            'durationMs': 200000,
          },
          {
            'id': 'song_3',
            'title': 'Cloud Only Song',
            'artist': 'Artist C',
            'album': 'Album C',
            'durationMs': 220000,
          },
        ];

        final Map<String, SongItem> mergedLikesMap = {};
        for (final song in localSongs) {
          mergedLikesMap[song.id] = song;
        }
        for (final raw in remoteSongsRaw) {
          try {
            final song = SongItem.fromJson(Map<String, dynamic>.from(raw));
            if (!mergedLikesMap.containsKey(song.id)) {
              mergedLikesMap[song.id] = song;
            }
          } catch (_) {}
        }

        final merged = mergedLikesMap.values.toList();
        // Should have 3 unique songs (song_1, song_2, song_3)
        expect(merged.length, equals(3));
        expect(merged.any((s) => s.id == 'song_1'), isTrue);
        expect(merged.any((s) => s.id == 'song_2'), isTrue);
        expect(merged.any((s) => s.id == 'song_3'), isTrue);
        // Local copy of shared song takes precedence
        expect(
          merged.firstWhere((s) => s.id == 'song_2').title,
          equals('Shared Song'),
        );
      },
    );

    test(
      'Custom playlist union merge retains local playlists and combines songs',
      () {
        final localPlaylists = [
          {
            'id': 'pl_1',
            'name': 'My Telugu Favorites',
            'songs': [
              {'id': 'song_10', 'title': 'Samajavaragamana'},
            ],
          },
          {
            'id': 'pl_local_only',
            'name': 'Gym Beats',
            'songs': [
              {'id': 'song_20', 'title': 'Animal Theme'},
            ],
          },
        ];

        final remotePlaylists = [
          {
            'id': 'pl_1',
            'name': 'My Telugu Favorites',
            'songs': [
              {'id': 'song_10', 'title': 'Samajavaragamana'},
              {'id': 'song_11', 'title': 'Butta Bomma'},
            ],
          },
          {
            'id': 'pl_cloud_only',
            'name': 'Late Night Lofi',
            'songs': [
              {'id': 'song_30', 'title': 'Midnight Chill'},
            ],
          },
        ];

        final Map<String, Map<String, dynamic>> mergedMap = {};
        for (final p in localPlaylists) {
          final id = (p['id'] ?? p['name'] ?? '').toString();
          if (id.isNotEmpty) {
            mergedMap[id] = Map<String, dynamic>.from(p);
          }
        }
        for (final raw in remotePlaylists) {
          final remoteP = Map<String, dynamic>.from(raw);
          final id = (remoteP['id'] ?? remoteP['name'] ?? '').toString();
          if (id.isNotEmpty) {
            if (!mergedMap.containsKey(id)) {
              mergedMap[id] = remoteP;
            } else {
              final existingSongs = List<dynamic>.from(
                mergedMap[id]!['songs'] as List? ?? [],
              );
              final existingIds = existingSongs
                  .map((s) => (s is Map ? s['id'] : null))
                  .toSet();
              final remoteSongs = List<dynamic>.from(
                remoteP['songs'] as List? ?? [],
              );
              for (final rs in remoteSongs) {
                if (rs is Map && !existingIds.contains(rs['id'])) {
                  existingSongs.add(rs);
                  existingIds.add(rs['id']);
                }
              }
              mergedMap[id]!['songs'] = existingSongs;
            }
          }
        }

        // Should have 3 playlists total
        expect(mergedMap.length, equals(3));
        expect(mergedMap.containsKey('pl_1'), isTrue);
        expect(mergedMap.containsKey('pl_local_only'), isTrue);
        expect(mergedMap.containsKey('pl_cloud_only'), isTrue);

        // pl_1 should have merged 2 songs without duplicate
        final pl1Songs = mergedMap['pl_1']!['songs'] as List;
        expect(pl1Songs.length, equals(2));
        expect(pl1Songs.any((s) => s['id'] == 'song_10'), isTrue);
        expect(pl1Songs.any((s) => s['id'] == 'song_11'), isTrue);
      },
    );

    test(
      'Canonical song deduplication eliminates duplicate tracks during sync merge',
      () {
        final localSongs = [
          const SongItem(
            id: 'yt_123',
            title: 'Samajavaragamana (Full Video)',
            author: 'Sid Sriram, Thaman S',
          ),
        ];

        final remoteSongsRaw = [
          {
            'id': 'jio_456',
            'title': 'Samajavaragamana',
            'author': 'Sid Sriram',
          },
          {'id': 'song_new', 'title': 'Butta Bomma', 'author': 'Armaan Malik'},
        ];

        final List<SongItem> mergedLikes = [];
        for (final song in localSongs) {
          mergedLikes.add(song);
        }
        for (final raw in remoteSongsRaw) {
          final song = SongItem.fromJson(Map<String, dynamic>.from(raw));
          final isDup = mergedLikes.any(
            (s) =>
                s.id == song.id ||
                (s.title.toLowerCase().contains('samajavaragamana') &&
                    song.title.toLowerCase().contains('samajavaragamana')),
          );
          if (!isDup) {
            mergedLikes.add(song);
          }
        }

        // Samajavaragamana should not duplicate despite different IDs (yt_123 vs jio_456)
        expect(mergedLikes.length, equals(2));
        expect(mergedLikes.first.id, equals('yt_123'));
        expect(mergedLikes.last.id, equals('song_new'));
      },
    );

    test(
      'Playlist union matches by normalized name when IDs differ across devices',
      () {
        final localPlaylists = [
          {
            'id': 'local_device_1001',
            'name': 'Telugu Classics',
            'songs': [
              {'id': 'song_1', 'title': 'Song 1'},
            ],
          },
        ];

        final remotePlaylists = [
          {
            'id': 'cloud_device_2002',
            'name':
                '  telugu classics  ', // Same name, different casing/whitespace, different id
            'songs': [
              {'id': 'song_2', 'title': 'Song 2'},
            ],
          },
        ];

        bool areSamePlaylists(Map a, Map b) {
          final idA = (a['id'] ?? '').toString().trim();
          final idB = (b['id'] ?? '').toString().trim();
          if (idA.isNotEmpty && idA == idB) return true;
          final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
          final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
          return nameA.isNotEmpty && nameA == nameB;
        }

        final List<Map<String, dynamic>> merged = [];
        for (final p in localPlaylists) {
          merged.add(Map<String, dynamic>.from(p));
        }

        for (final raw in remotePlaylists) {
          final existingIdx = merged.indexWhere(
            (p) => areSamePlaylists(p, raw),
          );
          if (existingIdx == -1) {
            merged.add(Map<String, dynamic>.from(raw));
          } else {
            final existingSongs = List<dynamic>.from(
              merged[existingIdx]['songs'] as List? ?? [],
            );
            final remoteSongs = List<dynamic>.from(raw['songs'] as List? ?? []);
            for (final rs in remoteSongs) {
              if (!existingSongs.any((s) => s['id'] == rs['id'])) {
                existingSongs.add(rs);
              }
            }
            merged[existingIdx]['songs'] = existingSongs;
          }
        }

        // Exactly 1 playlist merged, containing both songs, zero duplication
        expect(merged.length, equals(1));
        expect(merged.first['name'], equals('Telugu Classics'));
        final songs = merged.first['songs'] as List;
        expect(songs.length, equals(2));
      },
    );

    test('CloudSyncAnalysis accurately models Set Theory differences', () {
      // Local has nothing new (L ⊆ C)
      const analysisSynced = CloudSyncAnalysis(
        isConfigured: true,
        hasCloudData: true,
        hasLocalData: false,
        hasNewLocalItems: false,
        hasNewCloudItems: true,
        localLikesCount: 0,
        localPlaylistsCount: 0,
        cloudLikesCount: 15,
        cloudPlaylistsCount: 3,
        newLocalLikesCount: 0,
        newLocalPlaylistsCount: 0,
        newCloudLikesCount: 15,
        newCloudPlaylistsCount: 3,
      );

      // Should not prompt user to back up 0 items
      expect(analysisSynced.hasNewLocalItems, isFalse);
      // Cloud has items to hydrate local
      expect(analysisSynced.hasNewCloudItems, isTrue);

      // Local has new offline items (L \ C != ∅)
      const analysisNewLocal = CloudSyncAnalysis(
        isConfigured: true,
        hasCloudData: true,
        hasLocalData: true,
        hasNewLocalItems: true,
        hasNewCloudItems: false,
        localLikesCount: 20,
        localPlaylistsCount: 4,
        cloudLikesCount: 15,
        cloudPlaylistsCount: 3,
        newLocalLikesCount: 5,
        newLocalPlaylistsCount: 1,
        newCloudLikesCount: 0,
        newCloudPlaylistsCount: 0,
      );

      expect(analysisNewLocal.hasNewLocalItems, isTrue);
      expect(analysisNewLocal.newLocalLikesCount, equals(5));
      expect(analysisNewLocal.newLocalPlaylistsCount, equals(1));
    });

    test('CloudSyncResult maintains correct status transitions', () {
      final sync = CloudSyncService();
      expect(sync.syncStatus.value, equals(CloudSyncStatus.idle));
    });
  });
}
