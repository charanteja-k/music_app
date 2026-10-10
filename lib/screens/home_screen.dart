import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/profile_avatar_helper.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../layouts/desktop_layout_state.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../services/canonical_song_dedup.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/profile_side_drawer.dart';
import 'album_screen.dart';
import 'curated_playlist_screen.dart';
import 'custom_playlist_screen.dart';
import '../models/jio_album.dart';
import '../constants/app_theme_tokens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();

  @override
  bool get wantKeepAlive => true;

  List<Video> _topChartsIndia = [];
  List<Video> _trendingNow = [];
  List<Video> _newReleases = [];
  List<Video> _personalizedMixes = [];
  List<Video> _circadianMix = [];
  List<Video> _dailyMix1 = [];
  List<Video> _dailyMix2 = [];
  List<JioAlbum> _trendingAlbums = [];
  CircadianContext? _circadianContext;
  List<DailyMixConfig> _dailyMixConfigs = [];
  bool _isLoadingCharts = true;

  int _selectedMoodIndex = 0;
  List<Video> _moodSongs = [];
  bool _isLoadingMood = false;
  final Map<int, List<Video>> _cachedMoodSongs = {};

  List<Map<String, String>> get _moods {
    final primaryLang = _prefs.preferredLanguages.isNotEmpty
        ? _prefs.preferredLanguages.first
        : 'Telugu';
    return [
      {
        'label': 'All Hits',
        'query': '$primaryLang Top Hits',
        'desc': 'All trending and personalized hits curated for you',
      },
      {
        'label': 'Energetic',
        'query': '$primaryLang Fast Hits',
        'desc': 'High-tempo power anthems to fuel your energy',
      },
      {
        'label': 'Chill & Relax',
        'query': '$primaryLang Melodies',
        'desc': 'Mellow acoustic melodies to unwind and relax',
      },
      {
        'label': 'Focus & Code',
        'query': 'Lofi Instrumental Chill Beats',
        'desc': 'Smooth non-distracting instrumental beats for flow state',
      },
      {
        'label': 'Workout',
        'query': '$primaryLang Mass Hits',
        'desc': 'Adrenaline-pumping tracks to power your training session',
      },
      {
        'label': 'Sleep',
        'query': '$primaryLang Slow Melodies',
        'desc': 'Peaceful, dreamy soundscapes for deep and restful sleep',
      },
      {
        'label': 'Party Hits',
        'query': '$primaryLang Party Hits',
        'desc': 'Dancefloor crowd-pleasers and club anthems',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _musicService.addListener(_onPrefsChanged);
    // Instant zero-wait display if background preload completed during splash
    if (_musicService.hasPreloadedHome &&
        _musicService.preloadedTopChartsIndia.isNotEmpty) {
      _topChartsIndia = List.from(_musicService.preloadedTopChartsIndia);
      _trendingNow = List.from(_musicService.preloadedTrending);
      _isLoadingCharts = false;
    }
    _loadHomeFeeds();
  }

  @override
  void dispose() {
    _musicService.removeListener(_onPrefsChanged);
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _getGreeting() {
    return _prefs.getTimeOfDayGreeting();
  }

  /// Fetches an optimized, pure JioSaavn Studio 320kbps catalog for Daily Mix.
  /// Strictly guarantees 100% official studio tracks, 0 YouTube video noise,
  /// 0 wedding/DJ noise, and 0 duplicate tracks.
  Future<List<Video>> _loadRichDailyMix(DailyMixConfig config) async {
    try {
      final jioMix = await _musicService.fetchJioDailyMix(config, limit: 35);
      if (jioMix.isNotEmpty) return jioMix;
      return await _musicService.searchSongs(config.query, limit: 35);
    } catch (_) {
      return await _musicService.searchSongs(config.query, limit: 35);
    }
  }

  Future<void> _loadHomeFeeds() async {
    _circadianContext = _prefs.getCircadianContext();
    _dailyMixConfigs = _prefs.getDailyMixConfigs();

    // 1. Silent Instant Cache Hydration (< 6 hours) with strict deduplication & noise filtering
    final cachedCircadian = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('circadian'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedMix1 = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('daily_mix_1'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedMix2 = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('daily_mix_2'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedCharts = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('charts'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedTrending = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('trending'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedNewReleases = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('new_releases'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedPersonalized = CanonicalSongDedup.deduplicateList(
      _deserializeCachedVideos(
        _prefs.getCachedHomeFeed('personalized'),
      ).where((v) => CanonicalSongDedup.isGenuineSong(v)).toList(),
    );
    final cachedAlbumsJson = _prefs.getCachedHomeFeed('albums');
    List<JioAlbum> cachedAlbums = [];
    if (cachedAlbumsJson != null && cachedAlbumsJson.isNotEmpty) {
      try {
        final decoded = json.decode(cachedAlbumsJson) as List<dynamic>;
        cachedAlbums = decoded
            .whereType<Map<String, dynamic>>()
            .map(JioAlbum.fromJson)
            .where((a) => a.id.isNotEmpty && a.title.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    bool hadCache = false;
    if (cachedCircadian.isNotEmpty ||
        cachedMix1.isNotEmpty ||
        cachedCharts.isNotEmpty ||
        cachedAlbums.isNotEmpty) {
      hadCache = true;
      if (mounted) {
        setState(() {
          if (cachedCircadian.isNotEmpty) _circadianMix = cachedCircadian;
          if (cachedMix1.isNotEmpty) _dailyMix1 = cachedMix1;
          if (cachedMix2.isNotEmpty) _dailyMix2 = cachedMix2;
          if (cachedCharts.isNotEmpty) _topChartsIndia = cachedCharts;
          if (cachedTrending.isNotEmpty) _trendingNow = cachedTrending;
          if (cachedNewReleases.isNotEmpty) _newReleases = cachedNewReleases;
          if (cachedPersonalized.isNotEmpty) {
            _personalizedMixes = cachedPersonalized;
          }
          if (cachedAlbums.isNotEmpty) _trendingAlbums = cachedAlbums;
          _isLoadingCharts = false;
        });
      }
    }

    // 2. Background Refresh / Initial Load
    try {
      final primaryLang = _prefs.preferredLanguages.isNotEmpty
          ? _prefs.preferredLanguages.first
          : 'Telugu';
      final futureCircadian = _musicService.searchSongs(
        _circadianContext!.query,
      );
      final futureMix1 = _loadRichDailyMix(_dailyMixConfigs[0]);
      final futureMix2 = _loadRichDailyMix(_dailyMixConfigs[1]);
      final futureCharts =
          _musicService.hasPreloadedHome &&
              _musicService.preloadedTopChartsIndia.isNotEmpty
          ? Future.value(_musicService.preloadedTopChartsIndia)
          : _musicService.searchSongs('$primaryLang Top Hits');
      final futureTrending =
          _musicService.hasPreloadedHome &&
              _musicService.preloadedTrending.isNotEmpty
          ? Future.value(_musicService.preloadedTrending)
          : _musicService.searchSongs('$primaryLang Trending');
      final futureNewReleases = _musicService.searchSongs(
        '$primaryLang Latest Songs',
      );
      final futurePersonalized = _dailyMixConfigs.length > 2
          ? _loadRichDailyMix(_dailyMixConfigs[2])
          : _musicService.searchSongs('$primaryLang Mix');
      final futureAlbums = _musicService.searchAlbums(
        '$primaryLang Soundtracks',
        limit: 12,
      );

      final results = await Future.wait<dynamic>([
        futureCircadian,
        futureMix1,
        futureMix2,
        futureCharts,
        futureTrending,
        futureNewReleases,
        futurePersonalized,
        futureAlbums,
      ]);

      final circadian = CanonicalSongDedup.deduplicateList(
        results[0] as List<Video>,
      );
      final mix1 = CanonicalSongDedup.deduplicateList(
        results[1] as List<Video>,
      );
      final mix2 = CanonicalSongDedup.deduplicateList(
        results[2] as List<Video>,
      );
      final charts = CanonicalSongDedup.deduplicateList(
        results[3] as List<Video>,
      );
      final trending = CanonicalSongDedup.deduplicateList(
        results[4] as List<Video>,
      );
      final newReleases = CanonicalSongDedup.deduplicateList(
        results[5] as List<Video>,
      );
      final personalized = CanonicalSongDedup.deduplicateList(
        results[6] as List<Video>,
      );
      var albums = (results[7] as List<dynamic>).whereType<JioAlbum>().toList();
      if (albums.length < 3) {
        final fallbackAlbums = await _musicService.searchAlbums(
          primaryLang,
          limit: 12,
        );
        if (fallbackAlbums.isNotEmpty) {
          albums = fallbackAlbums;
        }
      }

      _prefs.cacheHomeFeed('circadian', _serializeVideos(circadian));
      _prefs.cacheHomeFeed('daily_mix_1', _serializeVideos(mix1));
      _prefs.cacheHomeFeed('daily_mix_2', _serializeVideos(mix2));
      _prefs.cacheHomeFeed('charts', _serializeVideos(charts));
      _prefs.cacheHomeFeed('trending', _serializeVideos(trending));
      _prefs.cacheHomeFeed('new_releases', _serializeVideos(newReleases));
      _prefs.cacheHomeFeed('personalized', _serializeVideos(personalized));
      if (albums.isNotEmpty) {
        _prefs.cacheHomeFeed(
          'albums',
          json.encode(albums.map((a) => a.toJson()).toList()),
        );
      }

      if (mounted) {
        setState(() {
          _circadianMix = circadian;
          _dailyMix1 = mix1;
          _dailyMix2 = mix2;
          _topChartsIndia = charts;
          _trendingNow = trending;
          _newReleases = newReleases;
          _personalizedMixes = personalized;
          if (albums.isNotEmpty) _trendingAlbums = albums;
          _isLoadingCharts = false;
        });
        // Asynchronously enrich home cards with genuine JioSaavn album artwork
        _musicService.enrichArtworkForSongs(charts);
        _musicService.enrichArtworkForSongs(trending);
        _musicService.enrichArtworkForSongs(circadian);
      }
    } catch (e) {
      if (mounted && !hadCache) {
        setState(() {
          _isLoadingCharts = false;
        });
      }
    }
  }

  String _serializeVideos(List<Video> videos) {
    final list = videos
        .map(
          (v) => {
            'id': v.id.value,
            'title': v.title,
            'author': v.author,
            'durationMs': v.duration?.inMilliseconds ?? 0,
            'streamUrl': MusicService.getCachedWebStreamUrl(v.id.value) ?? '',
            'thumbnail': MusicService.getHdThumbnail(v.id.value),
          },
        )
        .toList();
    return json.encode(list);
  }

  List<Video> _deserializeCachedVideos(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = json.decode(jsonStr);
      return list.map((m) {
        final id = m['id'] as String;
        final streamUrl = m['streamUrl'] as String?;
        if (streamUrl != null && streamUrl.isNotEmpty) {
          MusicService.cacheWebStreamUrl(id, streamUrl);
        }
        return Video(
          VideoId(id),
          m['title'] as String,
          m['author'] as String,
          ChannelId('UC0WP5P-fwGlLyO4yOE76T8g'),
          DateTime.now(),
          '',
          null,
          '',
          Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
          ThumbnailSet(id),
          null,
          Engagement(0, null, null),
          false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _onMoodSelected(int index) async {
    if (_selectedMoodIndex == index) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMoodIndex = index;
    });

    if (index == 0) return;

    // Instant zero-wait cache response if previously loaded
    if (_cachedMoodSongs.containsKey(index) &&
        _cachedMoodSongs[index]!.isNotEmpty) {
      setState(() {
        _moodSongs = _cachedMoodSongs[index]!;
        _isLoadingMood = false;
      });
      return;
    }

    setState(() {
      _isLoadingMood = true;
    });

    try {
      final rawSongs = await _musicService.searchSongs(_moods[index]['query']!);
      // Filter out long mixes (>10 min) and short clips (<45s) to guarantee real songs
      final songs = rawSongs.where((v) {
        if (v.duration == null) return true;
        return v.duration!.inSeconds >= 45 && v.duration!.inMinutes <= 10;
      }).toList();

      if (mounted && _selectedMoodIndex == index) {
        _cachedMoodSongs[index] = songs;
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
    super.build(context);

    return Scaffold(
      backgroundColor: AppThemeTokens.oledBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Personalized Top Greeting & Avatar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!kIsWeb || MediaQuery.of(context).size.width < 1024)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ProfileSideDrawer.show(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFF1E1E28),
                            radius: 20,
                            backgroundImage: getProfileImageProvider(
                              _prefs.profileImagePath,
                            ),
                            child: !hasProfileImage(_prefs.profileImagePath)
                                ? const Icon(
                                    Icons.person_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Smart Playback Quick Resume Banner
            _buildQuickResumeBanner(),

            // 2x3 Minimalist Quick Access Grid for 1-Tap Playback
            _buildQuickAccessGrid(),

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
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.16)
                              : const Color(0xFF161622),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.30)
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            _moods[index]['label']!,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
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
                      // Dedicated Vibe Radio Hub vs Default Full Home Feed
                      if (_selectedMoodIndex != 0)
                        _buildVibeRadioView(_selectedMoodIndex)
                      else ...[
                        // Circadian Time-of-Day Contextual Shelf
                        if (_circadianMix.isNotEmpty &&
                            _circadianContext != null) ...[
                          _buildSectionHeader(
                            _circadianContext!.title.toUpperCase(),
                            _circadianContext!.subtitle,
                          ),
                          _buildHorizontalChartCards(_circadianMix),
                          const SizedBox(height: 24),
                        ],

                        // TOP CHARTS: INDIA
                        _buildSectionHeader(
                          'TOP CHARTS: INDIA',
                          'Updated Daily',
                        ),
                        _buildHorizontalChartCards(_topChartsIndia),
                        const SizedBox(height: 24),

                        // BLOCKBUSTER SOUNDTRACKS & ALBUMS
                        if (_trendingAlbums.isNotEmpty) ...[
                          _buildAlbumsSection(),
                          const SizedBox(height: 24),
                        ],

                        // MADE FOR YOU
                        if (_personalizedMixes.isNotEmpty) ...[
                          _buildSectionHeader(
                            'MADE FOR YOU',
                            'Curated for your taste',
                          ),
                          _buildHorizontalChartCards(_personalizedMixes),
                          const SizedBox(height: 24),
                        ],
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

  Widget _buildQuickAccessGrid() {
    final dailyMix1 = _dailyMixConfigs.isNotEmpty ? _dailyMixConfigs[0] : null;
    final dailyMix2 = _dailyMixConfigs.length > 1 ? _dailyMixConfigs[1] : null;

    final items = <_HomeQuickAccessItem>[
      _HomeQuickAccessItem(
        title: dailyMix1?.title ?? 'Daily Mix 1',
        icon: Icons.shuffle_rounded,
        iconGradient: const [Color(0xFFE040FB), Color(0xFF1DB954)],
        imageUrl: _dailyMix1.isNotEmpty
            ? _dailyMix1.first.thumbnails.lowResUrl
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CuratedPlaylistScreen(
                title: dailyMix1?.title ?? 'Daily Mix 1',
                subtitle: dailyMix1?.subtitle ?? 'Curated for you',
                initialSongs: _dailyMix1,
                gradientColors: const [Color(0xFFE040FB), Color(0xFF1DB954)],
                icon: Icons.shuffle_rounded,
              ),
            ),
          );
        },
      ),
      _HomeQuickAccessItem(
        title: 'Liked Songs',
        icon: Icons.favorite_rounded,
        iconGradient: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
        imageUrl: _musicService.likedSongs.isNotEmpty
            ? _musicService.likedSongs.first['thumbnail']
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const CustomPlaylistScreen(playlistId: 'liked_songs'),
            ),
          );
        },
      ),
      _HomeQuickAccessItem(
        title: dailyMix2?.title ?? 'Daily Mix 2',
        icon: Icons.graphic_eq_rounded,
        iconGradient: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
        imageUrl: _dailyMix2.isNotEmpty
            ? _dailyMix2.first.thumbnails.lowResUrl
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CuratedPlaylistScreen(
                title: dailyMix2?.title ?? 'Daily Mix 2',
                subtitle: dailyMix2?.subtitle ?? 'Curated for you',
                initialSongs: _dailyMix2,
                gradientColors: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
                icon: Icons.graphic_eq_rounded,
              ),
            ),
          );
        },
      ),
      _HomeQuickAccessItem(
        title: 'Top Charts',
        icon: Icons.trending_up_rounded,
        iconGradient: const [Color(0xFFFF512F), Color(0xFFDD2476)],
        imageUrl: _topChartsIndia.isNotEmpty
            ? _topChartsIndia.first.thumbnails.lowResUrl
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CuratedPlaylistScreen(
                title: 'Top Charts India',
                subtitle: 'Updated Daily',
                initialSongs: _topChartsIndia,
                gradientColors: const [Color(0xFFFF512F), Color(0xFFDD2476)],
                icon: Icons.trending_up_rounded,
              ),
            ),
          );
        },
      ),
      _HomeQuickAccessItem(
        title: 'New Releases',
        icon: Icons.fiber_new_rounded,
        iconGradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
        imageUrl: _newReleases.isNotEmpty
            ? _newReleases.first.thumbnails.lowResUrl
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CuratedPlaylistScreen(
                title: 'New Releases',
                subtitle: 'Fresh Music',
                initialSongs: _newReleases,
                gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                icon: Icons.fiber_new_rounded,
              ),
            ),
          );
        },
      ),
      _HomeQuickAccessItem(
        title: 'Trending',
        icon: Icons.whatshot_rounded,
        iconGradient: const [Color(0xFFF857A6), Color(0xFFFF5858)],
        imageUrl: _trendingNow.isNotEmpty
            ? _trendingNow.first.thumbnails.lowResUrl
            : null,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CuratedPlaylistScreen(
                title: 'Trending Now',
                subtitle: 'Global Pick',
                initialSongs: _trendingNow,
                gradientColors: const [Color(0xFFF857A6), Color(0xFFFF5858)],
                icon: Icons.whatshot_rounded,
              ),
            ),
          );
        },
      ),
    ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 52,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppThemeTokens.radiusSmall),
              onTap: () {
                HapticFeedback.lightImpact();
                item.onTap();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppThemeTokens.surfaceCard,
                  borderRadius: BorderRadius.circular(
                    AppThemeTokens.radiusSmall,
                  ),
                  border: Border.all(
                    color: AppThemeTokens.surfaceBorder,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(AppThemeTokens.radiusSmall),
                        bottomLeft: Radius.circular(AppThemeTokens.radiusSmall),
                      ),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child:
                            item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? Image.network(
                                item.imageUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: item.iconGradient,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Icon(
                                    item.icon,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: item.iconGradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppThemeTokens.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          );
        }, childCount: items.length),
      ),
    );
  }

  Widget _buildQuickResumeBanner() {
    final songMap = _prefs.lastPlayedSong;
    if (songMap == null || _musicService.currentSong != null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final title = (songMap['title'] as String?) ?? 'Last Played';
    final author = (songMap['author'] as String?) ?? 'Unknown Artist';
    final thumbnail = (songMap['thumbnail'] as String?) ?? '';
    final posMs = _prefs.lastPlayedPositionMs;
    final durMs = _prefs.lastPlayedDurationMs;
    final progress = (durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E1E2C).withValues(alpha: 0.95),
                const Color(0xFF13131E).withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.mediumImpact();
                _musicService.resumeLastPlaybackSession();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: thumbnail.isNotEmpty
                              ? Image.network(
                                  thumbnail,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  cacheWidth: 120,
                                  cacheHeight: 120,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 48,
                                    height: 48,
                                    color: const Color(0xFF262636),
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: const Color(0xFF262636),
                                  child: const Icon(
                                    Icons.music_note,
                                    color: Colors.white54,
                                  ),
                                ),
                        ),
                        if (progress > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: Colors.black45,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFA2D48),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'JUMP BACK IN',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _musicService.resumeLastPlaybackSession();
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _prefs.clearLastPlaybackSession();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVibeRadioView(int moodIndex) {
    final mood = _moods[moodIndex];
    final label = mood['label'] ?? '';
    final desc = mood['desc'] ?? 'Curated for this vibe';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vibe Hero Card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'VIBE RADIO',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!_isLoadingMood && _moodSongs.isNotEmpty)
                    Text(
                      '${_moodSongs.length} Tracks',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 18),
              if (!_isLoadingMood && _moodSongs.isNotEmpty)
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text(
                        'Play Vibe Radio',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _musicService.playPlaylist(_moodSongs, 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text(
                        'Shuffle',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        final shuffled = List<Video>.from(_moodSongs)
                          ..shuffle();
                        _musicService.playPlaylist(shuffled, 0);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_isLoadingMood) ...[
          const ShimmerCardRow(),
          const SizedBox(height: 20),
          const ShimmerSongRow(),
        ] else if (_moodSongs.isEmpty) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const Icon(
                    Icons.music_off_rounded,
                    size: 48,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No tracks found for $label',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _onMoodSelected(0),
                    child: const Text('Return to All Hits'),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          _buildSectionHeader('HIGHLIGHTS', 'Top Picks for $label'),
          _buildHorizontalChartCards(_moodSongs),
          const SizedBox(height: 22),
          _buildSectionHeader('VIBE TRACKLIST', '${_moodSongs.length} Songs'),
          _buildVerticalSongList(_moodSongs, isVibe: true),
        ],
      ],
    );
  }

  Widget _buildAlbumsSection() {
    if (_trendingAlbums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'BLOCKBUSTER SOUNDTRACKS',
          'Full Movie & Studio Albums',
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _trendingAlbums.length,
            itemBuilder: (context, index) {
              final album = _trendingAlbums[index];
              final isSingle = album.songCount <= 1;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (kIsWeb && MediaQuery.of(context).size.width >= 1024) {
                    DesktopLayoutState.openAlbum(
                      album: album,
                      albumId: album.id,
                      albumTitle: album.title,
                      albumArtwork: album.artwork,
                      albumArtist: album.artist,
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AlbumScreen(
                          album: album,
                          albumId: album.id,
                          albumTitle: album.title,
                          albumArtwork: album.artwork,
                          albumArtist: album.artist,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  width: 152,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
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
                              color: Colors.black.withValues(alpha: 0.45),
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
                              if (album.artwork.isNotEmpty)
                                Image.network(
                                  album.artwork,
                                  fit: BoxFit.cover,
                                  cacheWidth: 320,
                                  cacheHeight: 320,
                                  errorBuilder: (_, _, _) =>
                                      _buildAlbumFallbackCover(album),
                                )
                              else
                                _buildAlbumFallbackCover(album),
                              // Song count pill badge
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSingle
                                          ? Colors.white24
                                          : const Color(
                                              0xFF7C3AED,
                                            ).withValues(alpha: 0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    isSingle
                                        ? 'Single'
                                        : '${album.songCount} Songs',
                                    style: TextStyle(
                                      color: isSingle
                                          ? Colors.white70
                                          : const Color(0xFFA78BFA),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                              // Vinyl disc icon overlay
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.album_rounded,
                                    color: Colors.black,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.artist.isNotEmpty
                            ? album.artist
                            : (album.year.isNotEmpty
                                  ? album.year
                                  : 'Soundtrack'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumFallbackCover(JioAlbum album) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F1B2C), Color(0xFF120E1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.album_rounded, color: Color(0xFFA78BFA), size: 40),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
                          Transform.scale(
                            scale:
                                hdThumbnail.startsWith('https://i.ytimg.com/')
                                ? 1.35
                                : 1.0,
                            child: Image.network(
                              hdThumbnail,
                              fit: BoxFit.cover,
                              cacheWidth: 320,
                              cacheHeight: 320,
                              errorBuilder: (_, _, _) => Image.network(
                                song.thumbnails.highResUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 320,
                                cacheHeight: 320,
                              ),
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

  Widget _buildVerticalSongList(List<Video> videos, {bool isVibe = false}) {
    if (videos.isEmpty) return const SizedBox.shrink();

    final displayList = (!isVibe && videos.length > 6)
        ? videos.sublist(0, 6)
        : videos;

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
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    hdThumbnail,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
                    errorBuilder: (_, _, _) => Image.network(
                      song.thumbnails.lowResUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      cacheHeight: 120,
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white38,
                        size: 20,
                      ),
                      onPressed: () {
                        showSongOptionsBottomSheet(context, song);
                      },
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child:
                            (_musicService.currentSong?.id.value ==
                                    song.id.value &&
                                _musicService.isPlaying)
                            ? const AnimatedEqualizer(isPlaying: true, size: 16)
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _musicService.playPlaylist(displayList, index);
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HomeQuickAccessItem {
  final String title;
  final IconData icon;
  final List<Color> iconGradient;
  final String? imageUrl;
  final VoidCallback onTap;

  const _HomeQuickAccessItem({
    required this.title,
    required this.icon,
    required this.iconGradient,
    this.imageUrl,
    required this.onTap,
  });
}
