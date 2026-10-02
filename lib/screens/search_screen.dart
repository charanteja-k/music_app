import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../services/dynamic_artist_service.dart';
import '../services/canonical_song_dedup.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/category_card.dart';
import '../widgets/artist_card.dart';
import '../widgets/animated_equalizer.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();
  final DynamicArtistService _artistService = DynamicArtistService();
  int _browseTabIndex = 0;
  late PageController _browsePageController;

  @override
  bool get wantKeepAlive => true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Video> _searchResults = [];
  List<SearchSuggestion> _suggestions = [];
  Timer? _debounceTimer;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isArtistSearchActive = false;
  int _currentPage = 1;
  String _currentQuery = '';

  final List<Map<String, dynamic>> _categories = [
    {
      'title': 'Bollywood Hits',
      'subtitle': 'Top Trending & Classics',
      'query': 'Bollywood Top Hits 2026',
      'colors': [const Color(0xFFFF416C), const Color(0xFFFF4B2B)],
      'icon': Icons.whatshot_rounded,
      'badge': 'HOT',
    },
    {
      'title': 'Telugu Beats',
      'subtitle': 'Groove, Melodies & Mass',
      'query': 'Telugu Top Songs',
      'colors': [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)],
      'icon': Icons.music_note_rounded,
      'badge': 'VIRAL',
    },
    {
      'title': 'Pop & Global',
      'subtitle': 'Chartbusters & Hits',
      'query': 'Global Pop Hits',
      'colors': [const Color(0xFF00c6ff), const Color(0xFF0072ff)],
      'icon': Icons.public_rounded,
      'badge': 'GLOBAL',
    },
    {
      'title': 'Punjabi Hits',
      'subtitle': 'Bhangra, Dhol & Bass',
      'query': 'Punjabi Top Hits',
      'colors': [const Color(0xFFf857a6), const Color(0xFFff5858)],
      'icon': Icons.speaker_group_rounded,
      'badge': 'BEATS',
    },
    {
      'title': 'Lo-Fi & Chill',
      'subtitle': 'Focus, Relax & Study',
      'query': 'Lofi Chill Beats',
      'colors': [const Color(0xFF11998e), const Color(0xFF38ef7d)],
      'icon': Icons.bedtime_rounded,
      'badge': 'CHILL',
    },
    {
      'title': 'Workout Energy',
      'subtitle': 'High BPM & Motivation',
      'query': 'Workout Music Beats',
      'colors': [const Color(0xFFFF8008), const Color(0xFFFFC837)],
      'icon': Icons.bolt_rounded,
      'badge': 'PUMP',
    },
    {
      'title': 'Romance & Love',
      'subtitle': 'Soulful & Melodies',
      'query': 'Romantic Hindi Songs',
      'colors': [const Color(0xFFee9ca7), const Color(0xFFff758c)],
      'icon': Icons.favorite_rounded,
      'badge': 'LOVE',
    },
    {
      'title': 'Hip-Hop & Rap',
      'subtitle': 'Bars, Trap & 808s',
      'query': 'Hip Hop Hits',
      'colors': [const Color(0xFF3A1C71), const Color(0xFFD76D77)],
      'icon': Icons.mic_external_on_rounded,
      'badge': 'FLOW',
    },
    {
      'title': 'Party & Dance',
      'subtitle': 'Club Nights & EDM',
      'query': 'Party Dance Club Hits',
      'colors': [const Color(0xFFFA2D48), const Color(0xFFF7971E)],
      'icon': Icons.celebration_rounded,
      'badge': 'PARTY',
    },
    {
      'title': 'Indie & Acoustic',
      'subtitle': 'Raw, Unplugged & Vibe',
      'query': 'Indian Indie Acoustic Songs',
      'colors': [const Color(0xFF4776E6), const Color(0xFF8E54E9)],
      'icon': Icons.audiotrack_rounded,
      'badge': 'RAW',
    },
  ];

  @override
  void initState() {
    super.initState();
    _browsePageController = PageController(initialPage: _browseTabIndex);
    _prefs.addListener(_onPrefsChanged);
    _musicService.addListener(_onPrefsChanged);
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreResults();
      }
    });
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    setState(() {});
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    if (query != _currentQuery) {
      _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
        if (!mounted) return;
        final results = await _musicService.fetchEntitySuggestions(
          query,
          limit: 10,
        );
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _suggestions = results;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _prefs.removeListener(_onPrefsChanged);
    _musicService.removeListener(_onPrefsChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _browsePageController.dispose();
    super.dispose();
  }

  void _performSearch(String query, {bool isArtist = false}) async {
    if (query.trim().isEmpty) return;
    _debounceTimer?.cancel();

    await _prefs.addToSearchHistory(query);

    final bool isArtistSearch = isArtist || _artistService.isKnownArtist(query);
    final String effectiveQuery = isArtistSearch
        ? (_artistService.findArtist(query)?.name ?? query)
        : query;

    setState(() {
      _isSearching = true;
      _currentQuery = effectiveQuery;
      _currentPage = 1;
      _hasMore = true;
      _isArtistSearchActive = isArtistSearch;
      _suggestions.clear();
      _searchResults.clear();
    });

    final results = isArtistSearch
        ? await _musicService.fetchArtistDiscography(effectiveQuery, page: 1)
        : await _musicService.searchSongs(effectiveQuery, page: 1, limit: 50);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _hasMore = results.isNotEmpty;
      });
    }
  }

  void _loadMoreResults() async {
    if (_isLoadingMore || !_hasMore || _isSearching || _currentQuery.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    final initialPage = _currentPage;
    int targetPage = initialPage + 1;
    final List<Video> accumulatedNewSongs = [];

    const int maxAttempts = 3;
    const int pageLimit = 35;
    int attempts = 0;

    while (targetPage <= pageLimit &&
        attempts < maxAttempts &&
        accumulatedNewSongs.isEmpty) {
      attempts++;
      final batch = _isArtistSearchActive
          ? await _musicService.fetchArtistDiscography(
              _currentQuery,
              page: targetPage,
            )
          : await _musicService.searchSongs(
              _currentQuery,
              page: targetPage,
              limit: 50,
            );

      if (batch.isEmpty) {
        break;
      }

      final deduped = CanonicalSongDedup.deduplicateList(_searchResults, batch);

      if (deduped.isNotEmpty) {
        accumulatedNewSongs.addAll(deduped);
        break;
      } else {
        // Current batch had songs that were already loaded in _searchResults.
        // Advance to next page tier and retry immediately so scroll never stalls.
        targetPage++;
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (accumulatedNewSongs.isNotEmpty) {
          _currentPage = targetPage;
          _searchResults.addAll(accumulatedNewSongs);
          _hasMore = targetPage < pageLimit;
        } else {
          _hasMore = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final history = _prefs.searchHistory;

    if (_browsePageController.hasClients) {
      final currentPage = _browsePageController.page?.round();
      if (currentPage != null && currentPage != _browseTabIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _browsePageController.hasClients) {
            final cur = _browsePageController.page?.round();
            if (cur != null && cur != _browseTabIndex) {
              _browsePageController.jumpToPage(_browseTabIndex);
            }
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        elevation: 0,
        title: const Text(
          'Search',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern Frosted Search Field
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF161622),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: (val) {
                  HapticFeedback.lightImpact();
                  _performSearch(val);
                },
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Artists, Songs, Lyrics, and More',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white60,
                    size: 22,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.white60,
                            size: 18,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _searchController.clear();
                            setState(() {
                              _searchResults.clear();
                              _suggestions.clear();
                              _currentQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Content Area: Either Searching, Live Suggestions, Search Results, or Browse Categories
            Expanded(
              child: _isSearching
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                    )
                  : (_searchController.text.trim().isNotEmpty &&
                        _suggestions.isNotEmpty &&
                        _searchController.text.trim() != _currentQuery)
                  ? ListView.builder(
                      padding: const EdgeInsets.only(bottom: 160),
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: _buildSuggestionLeading(suggestion.type),
                          title: Text(
                            suggestion.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: suggestion.subtitle.isNotEmpty
                              ? Text(
                                  suggestion.subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          trailing: const Icon(
                            Icons.north_west_rounded,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _searchController.text = suggestion.text;
                            _performSearch(
                              suggestion.text,
                              isArtist:
                                  suggestion.type ==
                                  SearchSuggestionType.artist,
                            );
                          },
                        );
                      },
                    )
                  : _searchResults.isNotEmpty
                  ? ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 160),
                      itemCount:
                          _searchResults.length +
                          (_isArtistSearchActive ? 1 : 0) +
                          (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        final int headerOffset = _isArtistSearchActive ? 1 : 0;
                        if (_isArtistSearchActive && index == 0) {
                          return Container(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.library_music_rounded,
                                  color: Color(0xFF1DB954),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${_searchResults.length} Tracks • Complete Discography',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if (_isLoadingMore)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF1DB954),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        final songIndex = index - headerOffset;
                        if (songIndex == _searchResults.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Theme.of(context).primaryColor,
                                strokeWidth: 2.5,
                              ),
                            ),
                          );
                        }

                        final video = _searchResults[songIndex];
                        final hdThumbnail = MusicService.getHdThumbnail(
                          video.id.value,
                        );
                        final isCurrentSong =
                            _musicService.currentSong?.id.value ==
                            video.id.value;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              hdThumbnail,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Image.network(
                                video.thumbnails.lowResUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          title: Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrentSong
                                  ? Theme.of(context).primaryColor
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            video.author,
                            maxLines: 1,
                            style: TextStyle(
                              color: isCurrentSong
                                  ? Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.8)
                                  : Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrentSong)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: AnimatedEqualizer(
                                    isPlaying: _musicService.isPlaying,
                                    barCount: 3,
                                    color: Theme.of(context).primaryColor,
                                    size: 16,
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.more_horiz,
                                  color: Colors.white54,
                                ),
                                onPressed: () =>
                                    showSongOptionsBottomSheet(context, video),
                              ),
                            ],
                          ),
                          onTap: () {
                            _musicService.playPlaylist(_searchResults, index);
                          },
                        );
                      },
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (history.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.history_rounded,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Flexible(
                                      child: Text(
                                        'Recent Searches',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _prefs.clearSearchHistory();
                                  setState(() {});
                                },
                                icon: Icon(
                                  Icons.delete_sweep_rounded,
                                  size: 15,
                                  color: Theme.of(context).primaryColor,
                                ),
                                label: Text(
                                  'Clear All',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: history.map((item) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161622),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _searchController.text = item;
                                      _performSearch(item);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.search_rounded,
                                            size: 14,
                                            color: Theme.of(context)
                                                .primaryColor
                                                .withValues(alpha: 0.8),
                                          ),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 180,
                                            ),
                                            child: Text(
                                              item,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              _prefs.removeFromSearchHistory(
                                                item,
                                              );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                color: Colors.white12,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        // Two Boxes Switcher: Categories and Artists
                        _buildBrowseTabsHeader(context),
                        const SizedBox(height: 14),
                        // Swappable Grid with PageView matching MainScreen switching animation
                        Expanded(
                          child: PageView(
                            key: const PageStorageKey('browse_tabs_page_view'),
                            controller: _browsePageController,
                            physics: const ClampingScrollPhysics(),
                            onPageChanged: (index) {
                              setState(() => _browseTabIndex = index);
                            },
                            children: [
                              _buildCategoriesGrid(),
                              _buildArtistsGrid(),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Two Boxes Switcher: 'Categories' and 'Artists' with Apple-style smooth sliding indicator
  Widget _buildBrowseTabsHeader(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              // Fluid sliding highlight indicator pill with matching 320ms easeOutCubic curve
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: _browseTabIndex * boxWidth,
                top: 0,
                bottom: 0,
                width: boxWidth,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.65),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // The Two Interactive Selector Boxes
              Row(
                children: [
                  Expanded(
                    child: _buildSwitcherBox(
                      index: 0,
                      title: 'Categories',
                      icon: Icons.grid_view_rounded,
                      isActive: _browseTabIndex == 0,
                    ),
                  ),
                  Expanded(
                    child: _buildSwitcherBox(
                      index: 1,
                      title: 'Artists',
                      icon: Icons.mic_external_on_rounded,
                      isActive: _browseTabIndex == 1,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitcherBox({
    required int index,
    required String title,
    required IconData icon,
    required bool isActive,
  }) {
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final isOutOfSync =
              _browsePageController.hasClients &&
              _browsePageController.page?.round() != index;
          if (_browseTabIndex != index || isOutOfSync) {
            HapticFeedback.lightImpact();
            setState(() => _browseTabIndex = index);
            if (_browsePageController.hasClients) {
              _browsePageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
              );
            }
          }
        },
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? primaryColor : Colors.white60,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white60,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900 ? 4 : (width > 600 ? 3 : 2);
        final aspectRatio = width > 600 ? 1.75 : 1.55;

        return ListView(
          key: const PageStorageKey('categories_grid_view'),
          padding: const EdgeInsets.only(top: 4, bottom: 160),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.explore_rounded,
                    size: 16,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Browse Categories',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Explore curated moods, genres & charts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return CategoryCard(
                  title: cat['title'] as String,
                  subtitle: cat['subtitle'] as String,
                  query: cat['query'] as String,
                  colors: cat['colors'] as List<Color>,
                  icon: cat['icon'] as IconData,
                  badgeText: cat['badge'] as String?,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _searchController.text = cat['title'] as String;
                    _performSearch(cat['query'] as String);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistsGrid() {
    final artists = _artistService.getDynamicArtists();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900 ? 4 : (width > 600 ? 3 : 2);
        final aspectRatio = width > 600 ? 1.75 : 1.55;

        return ListView(
          key: const PageStorageKey('artists_grid_view'),
          padding: const EdgeInsets.only(top: 4, bottom: 160),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_external_on_rounded,
                    size: 16,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Featured Artists',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Curated from your listening taste & trending hits',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return ArtistCard(
                  artist: artist,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _searchController.text = artist.name;
                    _performSearch(artist.name, isArtist: true);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSuggestionLeading(SearchSuggestionType type) {
    switch (type) {
      case SearchSuggestionType.artist:
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Color(0xFF1DB954),
            size: 18,
          ),
        );
      case SearchSuggestionType.song:
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF00c6ff).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            color: Color(0xFF00c6ff),
            size: 18,
          ),
        );
      case SearchSuggestionType.album:
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFF8008).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.album_rounded,
            color: Color(0xFFFF8008),
            size: 18,
          ),
        );
      case SearchSuggestionType.history:
        return const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.history_rounded, color: Colors.white54, size: 20),
        );
      case SearchSuggestionType.query:
        return const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.search_rounded, color: Colors.white54, size: 20),
        );
    }
  }
}
