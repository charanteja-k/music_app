import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/spotlight_billboard.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();

  List<Video> _topChartsIndia = [];
  List<Video> _trendingNow = [];
  List<Video> _newReleases = [];
  List<Video> _personalizedMixes = [];
  bool _isLoadingCharts = true;

  int _selectedMoodIndex = 0;
  List<Video> _moodSongs = [];
  bool _isLoadingMood = false;

  final List<Map<String, String>> _moods = const [
    {'label': '✨ All Hits', 'query': 'Top Global Music Hits 2026'},
    {'label': '⚡ Energetic', 'query': 'High Energy Pop EDM Hits'},
    {'label': '☕ Chill & Relax', 'query': 'Chill Acoustic Vibes Music'},
    {'label': '🎧 Focus / Code', 'query': 'Deep Focus Lofi Beats for Study'},
    {'label': '💪 Workout', 'query': 'Gym Workout Motivation Music'},
    {'label': '🌙 Sleep', 'query': 'Deep Sleep Ambient Calming Music'},
    {'label': '🎉 Party Hits', 'query': 'Club Party Dance Hits'},
  ];

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    // Instant zero-wait display if background preload completed during splash
    if (_musicService.hasPreloadedHome && _musicService.preloadedTopChartsIndia.isNotEmpty) {
      _topChartsIndia = List.from(_musicService.preloadedTopChartsIndia);
      _trendingNow = List.from(_musicService.preloadedTrending);
      _isLoadingCharts = false;
    }
    _loadHomeFeeds();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return 'Late night';
  }

  Future<void> _loadHomeFeeds() async {
    try {
      final List<String> seeds = [];
      if (_prefs.mostPlayedArtist.isNotEmpty) {
        seeds.add('${_prefs.mostPlayedArtist} songs');
      }
      for (var query in _prefs.searchHistory) {
        if (!seeds.contains('$query songs') && seeds.length < 3) {
          seeds.add('$query songs');
        }
      }
      if (seeds.isEmpty) {
        seeds.add('Top Hit Songs 2026');
      }

      final futureCharts = _musicService.searchSongs('Top Charts India Music');
      final futureTrending = _musicService.searchSongs('Trending Songs 2026');
      final futureNewReleases = _musicService.searchSongs('Latest Music Hits');
      final futureSeeds = seeds.map((s) => _musicService.searchSongs(s)).toList();

      final results = await Future.wait<dynamic>([
        futureCharts,
        futureTrending,
        futureNewReleases,
        ...futureSeeds,
      ]);

      final charts = results[0] as List<Video>;
      final trending = results[1] as List<Video>;
      final newReleases = results[2] as List<Video>;

      final List<List<Video>> seedResults = [];
      for (int i = 3; i < results.length; i++) {
        final seedList = results[i] as List<Video>;
        if (seedList.isNotEmpty) seedResults.add(seedList);
      }

      final List<Video> blendedMix = [];
      int maxLen = 0;
      for (var list in seedResults) {
        if (list.length > maxLen) maxLen = list.length;
      }

      for (int i = 0; i < maxLen && blendedMix.length < 15; i++) {
        for (var list in seedResults) {
          if (i < list.length) {
            if (!blendedMix.any((v) => v.id == list[i].id)) {
              blendedMix.add(list[i]);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _topChartsIndia = charts;
          _trendingNow = trending;
          _newReleases = newReleases;
          _personalizedMixes = blendedMix;
          _isLoadingCharts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCharts = false;
        });
      }
    }
  }

  Future<void> _onMoodSelected(int index) async {
    if (_selectedMoodIndex == index) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMoodIndex = index;
    });

    if (index == 0) return;

    setState(() {
      _isLoadingMood = true;
    });

    try {
      final songs = await _musicService.searchSongs(_moods[index]['query']!);
      if (mounted && _selectedMoodIndex == index) {
        setState(() {
          _moodSongs = songs;
          _isLoadingMood = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMood = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final billboardItems = _trendingNow.isNotEmpty
        ? _trendingNow
        : (_topChartsIndia.isNotEmpty ? _topChartsIndia : _newReleases);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Personalized Top Greeting & Avatar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 18, bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_getGreeting().toUpperCase()},',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _prefs.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.6),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.25),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const CircleAvatar(
                          backgroundColor: Color(0xFF1E1E28),
                          radius: 20,
                          child: Icon(Icons.person_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Horizontal Mood & Activity Filter Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _moods.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedMoodIndex == index;

                    return GestureDetector(
                      onTap: () => _onMoodSelected(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor
                              : const Color(0xFF1A1A24),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            _moods[index]['label']!,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // Loading state with Shimmer Skeletons
            if (_isLoadingCharts)
              const SliverToBoxAdapter(
                child: Column(
                  children: [
                    ShimmerBillboard(),
                    SizedBox(height: 20),
                    ShimmerCardRow(),
                    SizedBox(height: 20),
                    ShimmerSongRow(),
                  ],
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mood Filter Result View (if a mood is selected)
                      if (_selectedMoodIndex != 0) ...[
                        _buildSectionHeader(
                          _moods[_selectedMoodIndex]['label']!.toUpperCase(),
                          'Curated Mood Selection',
                        ),
                        if (_isLoadingMood)
                          const ShimmerCardRow()
                        else ...[
                          _buildHorizontalChartCards(_moodSongs),
                          const SizedBox(height: 18),
                          _buildVerticalSongList(_moodSongs),
                        ],
                        const SizedBox(height: 28),
                      ],

                      // Top Spotlight Billboard Carousel
                      SpotlightBillboard(
                        items: billboardItems,
                        onPlay: (song, index) {
                          _musicService.playPlaylist(billboardItems, index);
                        },
                      ),
                      const SizedBox(height: 24),

                      // TOP CHARTS: INDIA
                      _buildSectionHeader('TOP CHARTS: INDIA', 'Updated Daily'),
                      _buildHorizontalChartCards(_topChartsIndia),
                      const SizedBox(height: 24),

                      // MADE FOR YOU
                      _buildSectionHeader('MADE FOR YOU', 'Curated Mix for your taste'),
                      _buildVerticalSongList(_personalizedMixes),
                      const SizedBox(height: 24),

                      // NEW RELEASES
                      _buildSectionHeader('NEW RELEASES', 'Fresh Music'),
                      _buildHorizontalChartCards(_newReleases),
                      const SizedBox(height: 24),

                      // TRENDING NOW
                      _buildSectionHeader('TRENDING NOW', 'Global Pick'),
                      _buildHorizontalChartCards(_trendingNow),
                      const SizedBox(height: 24),

                      // YOUR FAVORITES
                      if (_musicService.likedSongs.isNotEmpty) ...[
                        _buildSectionHeader('YOUR FAVORITES', 'Liked Tracks'),
                        _buildLikedSongsList(),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalChartCards(List<Video> videos) {
    if (videos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 215,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final song = videos[index];
          final hdThumbnail = MusicService.getHdThumbnail(song.id.value);

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _musicService.playPlaylist(videos, index);
            },
            child: Container(
              width: 152,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 152,
                    height: 152,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            hdThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Image.network(
                              song.thumbnails.highResUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerticalSongList(List<Video> videos) {
    if (videos.isEmpty) return const SizedBox.shrink();

    final displayList = videos.length > 6 ? videos.sublist(0, 6) : videos;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: displayList.asMap().entries.map((entry) {
          final index = entry.key;
          final song = entry.value;
          final hdThumbnail = MusicService.getHdThumbnail(song.id.value);

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF14141D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  hdThumbnail,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Image.network(
                    song.thumbnails.lowResUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
              subtitle: Text(
                song.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              trailing: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 22,
                ),
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                _musicService.playPlaylist(displayList, index);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLikedSongsList() {
    final liked = _musicService.likedSongs;
    final displayList = liked.length > 5 ? liked.sublist(0, 5) : liked;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: displayList.map((song) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF14141D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  // BUG-5 fix: use null-safe fallback instead of force-unwrap (!).
                  // Liked songs persisted before the thumbnail field existed would crash here.
                  song['thumbnail'] ?? MusicService.getHdThumbnail(song['id'] ?? ''),
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 50, height: 50, color: Colors.grey[850],
                  ),
                ),
              ),
              title: Text(
                song['title'] ?? 'Unknown Title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
              subtitle: Text(
                song['author'] ?? 'Unknown Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(Icons.favorite_rounded, color: Color(0xFFFA2D48), size: 22),
              onTap: () {
                HapticFeedback.lightImpact();
                final video = Video(
                  VideoId(song['id']!),
                  song['title']!,
                  song['author']!,
                  ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
                  DateTime.now(),
                  '',
                  null,
                  '',
                  null,
                  ThumbnailSet(song['id']!),
                  null,
                  Engagement(0, null, null),
                  false,
                );
                _musicService.playSong(video);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
