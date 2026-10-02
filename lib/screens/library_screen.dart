import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import 'spotify_import_screen.dart';
import 'custom_playlist_screen.dart';
import '../widgets/animated_equalizer.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();

  @override
  bool get wantKeepAlive => true;

  final Map<String, int> _songFileSizes = {};
  int _lastDownloadedCount = -1;

  @override
  void initState() {
    super.initState();
    _musicService.addListener(_onStateChanged);
    _prefs.addListener(_onStateChanged);
    _lastDownloadedCount = _musicService.downloadedSongs.length;
    _calculateStorageUsage();
  }

  @override
  void dispose() {
    _musicService.removeListener(_onStateChanged);
    _prefs.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      final currentCount = _musicService.downloadedSongs.length;
      if (currentCount != _lastDownloadedCount) {
        _lastDownloadedCount = currentCount;
        _calculateStorageUsage();
      }
      setState(() {});
    }
  }

  Future<void> _calculateStorageUsage() async {
    if (kIsWeb) return;
    final downloaded = _musicService.downloadedSongs;
    for (final s in downloaded) {
      final path = s['localPath'];
      final id = s['id'] ?? '';
      if (path != null && id.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            final len = await f.length();
            _songFileSizes[id] = len;
          }
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1.0) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(0)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final downloaded = _musicService.downloadedSongs;
    final liked = _musicService.likedSongs;
    final history = _prefs.listeningHistory;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0F),
          elevation: 0,
          title: const Text(
            'Your Library',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 30,
              color: Colors.white,
              letterSpacing: -0.8,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text(
                  'Import / Exportify',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SpotifyImportScreen(),
                    ),
                  );
                },
              ),
            ),
          ],

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(bottom: 6),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tabs: [
                  _buildPillTab('Downloaded', downloaded.length),
                  _buildPillTab('Liked', liked.length),
                  _buildPillTab(
                    'Playlists',
                    _musicService.customPlaylists.length,
                  ),
                  _buildPillTab('History', history.length),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: DOWNLOADED SONGS
            downloaded.isEmpty
                ? _buildEmptyState(
                    icon: Icons.download_for_offline_outlined,
                    title: 'No downloaded songs yet',
                    subtitle:
                        'Tap the download icon while playing any song to listen offline without internet.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 160, top: 12),
                    itemCount: downloaded.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildActionHeader(
                          count: downloaded.length,
                          onPlayAll: () {
                            HapticFeedback.lightImpact();
                            _musicService.playDownloadedSong(downloaded.first);
                          },
                          onShuffle: () {
                            HapticFeedback.lightImpact();
                            _musicService.setShuffle(true);
                            final randomIndex = Random().nextInt(
                              downloaded.length,
                            );
                            _musicService.playDownloadedSong(
                              downloaded[randomIndex],
                            );
                          },
                        );
                      }

                      final song = downloaded[index - 1];
                      final songId = song['id'] ?? '';
                      final sizeBytes = _songFileSizes[songId] ?? 0;
                      final sizeFormatted = _formatBytes(sizeBytes);
                      final isCurrent =
                          _musicService.currentSong?.id.value == songId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  song['thumbnail'] ?? '',
                                  cacheWidth: 120,
                                  cacheHeight: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFF1E1E28),
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black54,
                                    child: Center(
                                      child: AnimatedEqualizer(
                                        isPlaying: _musicService.isPlaying,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        title: Text(
                          song['title'] ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Flexible(
                              child: Text(
                                song['author'] ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            if (sizeBytes > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  sizeFormatted,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.offline_pin_rounded,
                              color: Color(0xFF1DB954),
                              size: 20,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white38,
                                size: 20,
                              ),
                              onPressed: () async {
                                HapticFeedback.mediumImpact();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E28),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    title: const Text(
                                      'Delete Download?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: Text(
                                      'Remove "${song['title']}" from offline storage?',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _musicService.deleteDownloadedSong(
                                    song['id']!,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _musicService.playDownloadedSong(song);
                        },
                      );
                    },
                  ),

            // TAB 2: LIKED SONGS
            liked.isEmpty
                ? _buildEmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'No liked songs yet',
                    subtitle:
                        'Tap the heart icon while playing any song to save it in your favorites collection.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 160, top: 12),
                    itemCount: liked.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildActionHeader(
                          count: liked.length,
                          onPlayAll: () {
                            HapticFeedback.lightImpact();
                            _musicService.playLikedSong(liked.first);
                          },
                          onShuffle: () {
                            HapticFeedback.lightImpact();
                            _musicService.setShuffle(true);
                            final randomIndex = Random().nextInt(liked.length);
                            _musicService.playLikedSong(liked[randomIndex]);
                          },
                        );
                      }

                      final song = liked[index - 1];
                      final songId = song['id'] ?? '';
                      final isCurrent =
                          _musicService.currentSong?.id.value == songId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  song['thumbnail'] ?? '',
                                  fit: BoxFit.cover,
                                  cacheWidth: 120,
                                  cacheHeight: 120,
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFF1E1E28),
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black54,
                                    child: Center(
                                      child: AnimatedEqualizer(
                                        isPlaying: _musicService.isPlaying,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        title: Text(
                          song['title'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Text(
                          song['author'] ?? '',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFA2D48),
                            size: 22,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _musicService.removeLikedSong(song['id'] ?? '');
                          },
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _musicService.playLikedSong(song);
                        },
                      );
                    },
                  ),

            // TAB 3: PLAYLISTS
            _musicService.customPlaylists.isEmpty
                ? _buildEmptyState(
                    icon: Icons.featured_play_list_outlined,
                    title: 'No custom playlists yet',
                    subtitle:
                        'Import any public playlist from Spotify or create your own custom playlist.',
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Import Spotify / Exportify'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SpotifyImportScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New Playlist'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showCreatePlaylistDialog();
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 160, top: 12),
                    itemCount: _musicService.customPlaylists.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_musicService.customPlaylists.length} Playlists',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                tooltip: 'New Playlist',
                                onPressed: _showCreatePlaylistDialog,
                              ),
                            ],
                          ),
                        );
                      }

                      final playlist = _musicService.customPlaylists[index - 1];
                      final name =
                          (playlist['name'] as String?) ?? 'Unknown Playlist';
                      final songs = List<Map<String, dynamic>>.from(
                        playlist['songs'] ?? [],
                      );
                      final id = (playlist['id'] as String?) ?? '';
                      final firstThumbnail = songs.isNotEmpty
                          ? songs.first['thumbnail'] as String?
                          : null;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _prefs.themeColor.withValues(alpha: 0.16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:
                                firstThumbnail != null &&
                                    firstThumbnail.isNotEmpty
                                ? Image.network(
                                    firstThumbnail,
                                    fit: BoxFit.cover,
                                    cacheWidth: 120,
                                    cacheHeight: 120,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.queue_music_rounded,
                                      color: _prefs.themeColor.withValues(
                                        alpha: 0.85,
                                      ),
                                      size: 26,
                                    ),
                                  )
                                : Icon(
                                    Icons.queue_music_rounded,
                                    color: _prefs.themeColor.withValues(
                                      alpha: 0.85,
                                    ),
                                    size: 26,
                                  ),
                          ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Text(
                          '${songs.length} tracks',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('playlist_play_$id'),
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                              tooltip: 'Play playlist',
                              onPressed: songs.isEmpty
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      _musicService.playCustomPlaylist(id, 0);
                                    },
                            ),
                            IconButton(
                              key: ValueKey('playlist_options_$id'),
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                              tooltip: 'Playlist options',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _showPlaylistOptionsSheet(
                                  id: id,
                                  name: name,
                                  songCount: songs.length,
                                  firstThumbnail: firstThumbnail,
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CustomPlaylistScreen(playlistId: id),
                            ),
                          );
                        },
                      );
                    },
                  ),

            // TAB 4: LISTENING HISTORY
            history.isEmpty
                ? _buildEmptyState(
                    icon: Icons.history_toggle_off_rounded,
                    title: 'No listening history yet',
                    subtitle:
                        'Songs you stream will automatically appear here for quick replay.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 160, top: 12),
                    itemCount: history.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${history.length} Recently Played',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(
                                  Icons.delete_sweep_rounded,
                                  size: 16,
                                  color: Colors.white54,
                                ),
                                label: const Text(
                                  'Clear',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _prefs.clearListeningHistory();
                                },
                              ),
                            ],
                          ),
                        );
                      }

                      final song = history[index - 1];
                      final songId = song['id'] ?? '';
                      final isCurrent =
                          _musicService.currentSong?.id.value == songId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  song['thumbnail'] ?? '',
                                  fit: BoxFit.cover,
                                  cacheWidth: 120,
                                  cacheHeight: 120,
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFF1E1E28),
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black54,
                                    child: Center(
                                      child: AnimatedEqualizer(
                                        isPlaying: _musicService.isPlaying,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        title: Text(
                          song['title'] ?? 'Unknown Track',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Text(
                          song['author'] ?? 'Unknown Artist',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white38,
                          size: 24,
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _musicService.playHistorySong(song);
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionHeader({
    required int count,
    required VoidCallback onPlayAll,
    required VoidCallback onShuffle,
  }) {
    final isShuffle = _musicService.isShuffle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 20,
              ),
              label: Text(
                'Play All ($count)',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPlayAll,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(
                Icons.shuffle_rounded,
                color: isShuffle ? const Color(0xFF1DB954) : Colors.white70,
                size: 18,
              ),
              label: Text(
                'Shuffle',
                style: TextStyle(
                  color: isShuffle ? const Color(0xFF1DB954) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: isShuffle
                    ? const Color(0xFF1DB954).withValues(alpha: 0.12)
                    : null,
                side: BorderSide(
                  color: isShuffle
                      ? const Color(0xFF1DB954).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.2),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onShuffle,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create New Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _musicService.createPlaylist(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptionsSheet({
    required String id,
    required String name,
    required int songCount,
    String? firstThumbnail,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Material(
          color: const Color(0xFF14141E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.only(top: 12, bottom: 28),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pill Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Playlist Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _prefs.themeColor.withValues(alpha: 0.16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:
                                firstThumbnail != null &&
                                    firstThumbnail.isNotEmpty
                                ? Image.network(
                                    firstThumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.queue_music_rounded,
                                      color: _prefs.themeColor.withValues(
                                        alpha: 0.85,
                                      ),
                                      size: 24,
                                    ),
                                  )
                                : Icon(
                                    Icons.queue_music_rounded,
                                    color: _prefs.themeColor.withValues(
                                      alpha: 0.85,
                                    ),
                                    size: 24,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$songCount ${songCount == 1 ? "track" : "tracks"}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 1,
                  ),
                  const SizedBox(height: 8),

                  // Action: Play Playlist
                  if (songCount > 0) ...[
                    ListTile(
                      key: const ValueKey('option_play_playlist'),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Play Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Start playback from the first track',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        _musicService.playCustomPlaylist(id, 0);
                      },
                    ),
                    ListTile(
                      key: const ValueKey('option_shuffle_playlist'),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1DB954,
                          ).withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shuffle_rounded,
                          color: Color(0xFF1DB954),
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Shuffle Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Play tracks in randomized order',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        _musicService.playCustomPlaylistWithShuffle(id);
                      },
                    ),
                  ],

                  // Action: Rename Playlist
                  ListTile(
                    key: const ValueKey('option_rename_playlist'),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Rename Playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Change playlist title',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      HapticFeedback.lightImpact();
                      _showRenamePlaylistDialog(id, name);
                    },
                  ),

                  // Action: Delete Playlist
                  ListTile(
                    key: const ValueKey('option_delete_playlist'),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Delete Playlist',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Permanently delete this playlist',
                      style: TextStyle(
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      HapticFeedback.lightImpact();
                      _showDeletePlaylistDialog(id, name);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRenamePlaylistDialog(String id, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New playlist name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white70),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != currentName) {
                _musicService.renamePlaylist(id, newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "$name"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              _musicService.deletePlaylist(id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab(String title, int count) {
    return Tab(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF161622),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Icon(icon, size: 48, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }
}
