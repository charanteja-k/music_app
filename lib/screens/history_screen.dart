import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme_tokens.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/dilse_scrollbar.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/desktop/desktop_context_menu.dart';

/// Full-screen Listening History Hub with real-time search, shuffle, and single-track replay.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_musicService, _prefs]),
      builder: (context, _) {
        final allHistory = _prefs.listeningHistory;
        final filteredSongs = _filterQuery.isEmpty
            ? allHistory
            : allHistory.where((s) {
                final t = (s['title'] ?? '').toLowerCase();
                final a = (s['author'] ?? '').toLowerCase();
                final q = _filterQuery.toLowerCase();
                return t.contains(q) || a.contains(q);
              }).toList();

        return Scaffold(
          backgroundColor: AppThemeTokens.oledBackground,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, allHistory.length),
                if (allHistory.isNotEmpty) _buildSearchBar(),
                if (allHistory.isNotEmpty) _buildActionBar(allHistory),
                Expanded(
                  child: allHistory.isEmpty
                      ? _buildEmptyState()
                      : _buildHistoryList(filteredSongs),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
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
                  'Listening History',
                  style: TextStyle(
                    color: AppThemeTokens.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  count == 1 ? '1 track played' : '$count tracks played',
                  style: const TextStyle(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white60,
                size: 22,
              ),
              tooltip: 'Clear history',
              onPressed: _confirmClearHistory,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeTokens.surfaceBorder, width: 0.75),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (val) => setState(() => _filterQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search history...',
            hintStyle: TextStyle(
              color: AppThemeTokens.textSecondary.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Colors.white54,
              size: 20,
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
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(List<Map<String, String>> history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeTokens.brandRuby,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text(
                'Play History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              onPressed: () {
                if (history.isNotEmpty) {
                  HapticFeedback.mediumImpact();
                  _musicService.playHistorySong(history.first);
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              label: const Text(
                'Shuffle',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              onPressed: () {
                if (history.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  final shuffled = List<Map<String, String>>.from(history)
                    ..shuffle();
                  _musicService.playHistorySong(shuffled.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<Map<String, String>> songs) {
    if (songs.isEmpty) {
      return Center(
        child: Text(
          'No history matches "$_filterQuery"',
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = _musicService.currentSong?.id.value == song['id'];

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
                  vertical: 4,
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _musicService.playHistorySong(song);
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
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppThemeTokens.surfaceElevated,
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white54,
                              size: 22,
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
                  song['title'] ?? 'Unknown Track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? AppThemeTokens.brandRuby : Colors.white,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  song['author'] ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 12.5,
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 40),
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
                Icons.history_rounded,
                size: 48,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No listening history yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tracks you play will automatically appear here for rapid replay.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeTokens.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeTokens.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear History?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will remove all songs from your playback history. This action cannot be undone.',
          style: TextStyle(color: AppThemeTokens.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeTokens.brandRuby,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              _prefs.clearListeningHistory();
            },
          ),
        ],
      ),
    );
  }
}
