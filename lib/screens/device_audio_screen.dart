import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme_tokens.dart';
import '../services/device_audio_service.dart';
import '../services/music_service.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/desktop/desktop_context_menu.dart';

/// Full-screen In-Device Music Screen.
/// Plays local audio files (.mp3, .m4a, .flac, .wav, .opus) directly with 0 stream data.
class DeviceAudioScreen extends StatefulWidget {
  const DeviceAudioScreen({super.key});

  @override
  State<DeviceAudioScreen> createState() => _DeviceAudioScreenState();
}

class _DeviceAudioScreenState extends State<DeviceAudioScreen> {
  final DeviceAudioService _deviceService = DeviceAudioService();
  final MusicService _musicService = MusicService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, int> _fileSizes = {};
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFileSizes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFileSizes() async {
    for (final s in _deviceService.deviceSongs) {
      final p = s['localPath'] ?? s['filePath'];
      final id = s['id'];
      if (p != null && id != null) {
        try {
          final f = File(p);
          if (await f.exists()) {
            final sz = await f.length();
            if (mounted) {
              setState(() => _fileSizes[id] = sz);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_deviceService, _musicService]),
      builder: (context, _) {
        final allSongs = _deviceService.deviceSongs;
        final filteredSongs = _filterQuery.isEmpty
            ? allSongs
            : allSongs.where((s) {
                final t = (s['title'] ?? '').toLowerCase();
                final a = (s['author'] ?? s['artist'] ?? '').toLowerCase();
                final q = _filterQuery.toLowerCase();
                return t.contains(q) || a.contains(q);
              }).toList();

        return Scaffold(
          backgroundColor: AppThemeTokens.oledBackground,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context, allSongs.length),
                if (_deviceService.isScanning) _buildScanningBanner(),
                _buildActionToolbar(allSongs),
                if (allSongs.isNotEmpty) _buildSearchBar(),
                Expanded(
                  child: allSongs.isEmpty
                      ? _buildEmptyState()
                      : _buildSongList(filteredSongs),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'In-Device Music',
                  style: TextStyle(
                    color: AppThemeTokens.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  count == 1
                      ? '1 offline track found'
                      : '$count offline tracks indexed',
                  style: const TextStyle(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1DB954).withValues(alpha: 0.35),
                width: 0.75,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFF1DB954), size: 14),
                SizedBox(width: 4),
                Text(
                  '0% Data',
                  style: TextStyle(
                    color: Color(0xFF1DB954),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeTokens.surfaceBorder, width: 0.75),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppThemeTokens.brandRuby,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _deviceService.scanStatusMessage.isNotEmpty
                  ? _deviceService.scanStatusMessage
                  : 'Scanning device storage for music files...',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionToolbar(List<Map<String, String>> songs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.refresh_rounded,
            label: 'Scan Storage',
            onTap: () {
              HapticFeedback.lightImpact();
              _deviceService.scanDeviceStorage();
            },
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.folder_open_rounded,
            label: 'Pick Folder',
            onTap: () {
              HapticFeedback.lightImpact();
              _deviceService.pickDirectory();
            },
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: Icons.audio_file_rounded,
            label: 'Pick Files',
            onTap: () {
              HapticFeedback.lightImpact();
              _deviceService.pickAudioFiles();
            },
          ),
          if (songs.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildActionButton(
              icon: Icons.playlist_add_rounded,
              label: 'Create Playlist',
              accent: true,
              onTap: () => _createPlaylistFromDevice(songs),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: accent
                ? AppThemeTokens.brandRuby.withValues(alpha: 0.18)
                : AppThemeTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent
                  ? AppThemeTokens.brandRuby.withValues(alpha: 0.45)
                  : AppThemeTokens.surfaceBorder,
              width: 0.75,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: accent ? AppThemeTokens.brandRuby : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeTokens.surfaceBorder, width: 0.75),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 13.5),
          onChanged: (val) => setState(() => _filterQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search local tracks...',
            hintStyle: TextStyle(
              color: AppThemeTokens.textSecondary.withValues(alpha: 0.7),
              fontSize: 13.5,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Colors.white54,
              size: 19,
            ),
            suffixIcon: _filterQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _filterQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildSongList(List<Map<String, String>> songs) {
    if (songs.isEmpty) {
      return Center(
        child: Text(
          'No local tracks match "$_filterQuery"',
          style: const TextStyle(
            color: AppThemeTokens.textSecondary,
            fontSize: 14,
          ),
        ),
      );
    }

    return DilSeScrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = _musicService.currentSong?.id.value == song['id'];
          final sz = _fileSizes[song['id'] ?? ''] ?? 0;
          final sizeStr = _formatBytes(sz);
          final path = song['localPath'] ?? song['filePath'] ?? '';
          final ext = path.contains('.')
              ? path.split('.').last.toUpperCase()
              : 'AUDIO';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppThemeTokens.brandRuby.withValues(alpha: 0.12)
                  : AppThemeTokens.surfaceCard,
              borderRadius: BorderRadius.circular(AppThemeTokens.radiusCard),
              border: Border.all(
                color: isCurrent
                    ? AppThemeTokens.brandRuby.withValues(alpha: 0.4)
                    : AppThemeTokens.surfaceBorder,
                width: 0.75,
              ),
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
                  vertical: 3,
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _musicService.playDeviceSong(song);
                },
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppThemeTokens.brandRuby.withValues(alpha: 0.25)
                        : AppThemeTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCurrent
                          ? AppThemeTokens.brandRuby.withValues(alpha: 0.5)
                          : Colors.white12,
                      width: 0.75,
                    ),
                  ),
                  child: Center(
                    child: isCurrent
                        ? AnimatedEqualizer(
                            isPlaying: _musicService.isPlaying,
                            size: 20,
                          )
                        : const Icon(
                            Icons.audio_file_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                  ),
                ),
                title: Text(
                  song['title'] ?? 'Unknown Track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? AppThemeTokens.brandRuby : Colors.white,
                    fontSize: 14,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Flexible(
                      child: Text(
                        song['author'] ?? song['artist'] ?? 'Local File',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppThemeTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ext,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (sizeStr.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '• $sizeStr',
                        style: const TextStyle(
                          color: AppThemeTokens.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white60,
                    size: 20,
                  ),
                  onPressed: () {
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppThemeTokens.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppThemeTokens.surfaceBorder,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 46,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No on-device music loaded',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan storage or select audio folders from your device to listen offline with zero data consumption.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeTokens.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeTokens.brandRuby,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text(
                'Scan Device Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () => _deviceService.scanDeviceStorage(),
            ),
          ],
        ),
      ),
    );
  }

  void _createPlaylistFromDevice(List<Map<String, String>> songs) {
    HapticFeedback.lightImpact();
    final name = 'Device Music (${songs.length})';
    _musicService.createPlaylist(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created playlist "$name" in your Library!'),
        backgroundColor: const Color(0xFF1DB954),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
