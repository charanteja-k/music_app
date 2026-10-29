import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme_tokens.dart';
import '../services/music_service.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/desktop/desktop_context_menu.dart';

/// Dedicated full-screen Downloads Hub — 4th core destination in the bottom dock.
/// Guaranteed 100% offline playback with storage telemetry and instant search.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final MusicService _musicService = MusicService();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, int> _songFileSizes = {};
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFileSizes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFileSizes() async {
    if (kIsWeb) return;
    final downloaded = _musicService.downloadedSongs;
    for (final song in downloaded) {
      final path = song['filePath'];
      final id = song['id'];
      if (path != null && id != null) {
        try {
          final file = File(path);
          if (await file.exists()) {
            final len = await file.length();
            if (mounted) {
              setState(() {
                _songFileSizes[id] = len;
              });
            }
          }
        } catch (_) {}
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  int get _totalStorageBytes {
    return _songFileSizes.values.fold<int>(0, (sum, sz) => sum + sz);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _musicService,
      builder: (context, _) {
        final allDownloaded = _musicService.downloadedSongs;
        final filteredSongs = _filterQuery.isEmpty
            ? allDownloaded
            : allDownloaded.where((s) {
                final t = (s['title'] ?? '').toLowerCase();
                final a = (s['author'] ?? '').toLowerCase();
                return t.contains(_filterQuery.toLowerCase()) ||
                    a.contains(_filterQuery.toLowerCase());
              }).toList();

        return Scaffold(
          backgroundColor: AppThemeTokens.oledBackground,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(allDownloaded.length),
                if (allDownloaded.isNotEmpty) _buildSearchBar(),
                Expanded(
                  child: allDownloaded.isEmpty
                      ? _buildEmptyState()
                      : _buildSongsList(filteredSongs),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(int totalCount) {
    final storageStr = _formatBytes(_totalStorageBytes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Downloads',
                style: TextStyle(
                  color: AppThemeTokens.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppThemeTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppThemeTokens.surfaceBorder,
                    width: 0.75,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.offline_pin_rounded,
                      color: Color(0xFF1DB954),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      storageStr.isNotEmpty ? storageStr : 'Offline Ready',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$totalCount songs saved for offline listening',
            style: const TextStyle(
              color: AppThemeTokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeTokens.surfaceBorder, width: 0.75),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search downloaded songs...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) {
                  setState(() => _filterQuery = val.trim());
                },
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _filterQuery = '');
                },
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppThemeTokens.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppThemeTokens.surfaceBorder,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.download_for_offline_rounded,
                color: Colors.white38,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Downloads Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Songs you download will appear here for seamless offline playback anywhere, anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongsList(List<Map<String, String>> songs) {
    return DilSeScrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 160, top: 4),
        itemCount: songs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildActionBar(songs);
          }

          final song = songs[index - 1];
          final songId = song['id'] ?? '';
          final sizeBytes = _songFileSizes[songId] ?? 0;
          final sizeFormatted = _formatBytes(sizeBytes);
          final isCurrent = _musicService.currentSong?.id.value == songId;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppThemeTokens.surfaceElevated
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                showUnifiedTrackMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  song: songMapToVideo(song),
                );
              },
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _musicService.playDownloadedSong(song);
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          song['thumbnail'] ?? '',
                          cacheWidth: 120,
                          cacheHeight: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppThemeTokens.surfaceCard,
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
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                title: Text(
                  song['title'] ?? 'Unknown Title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? AppThemeTokens.brandRuby : Colors.white,
                    fontSize: 14.5,
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sizeFormatted,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final video = songMapToVideo(song);
                    showSongOptionsBottomSheet(context, video);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionBar(List<Map<String, String>> songs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeTokens.brandRuby,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text(
                'Play All',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: () {
                if (songs.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  _musicService.playDownloadedSong(songs.first);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: AppThemeTokens.surfaceBorder),
                backgroundColor: AppThemeTokens.surfaceCard,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text(
                'Shuffle',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              onPressed: () {
                if (songs.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  _musicService.toggleShuffle();
                  _musicService.playDownloadedSong(songs.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
