import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final MusicService _musicService = MusicService();
  final PreferencesService _prefs = PreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Video> _searchResults = [];
  List<String> _suggestions = [];
  Timer? _debounceTimer;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String _currentQuery = '';

  final List<Map<String, dynamic>> _categories = [
    {
      'title': 'Bollywood Hits',
      'query': 'Bollywood Top Hits 2026',
      'colors': [const Color(0xFFFF416C), const Color(0xFFFF4B2B)],
    },
    {
      'title': 'Telugu Beats',
      'query': 'Telugu Top Songs',
      'colors': [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)],
    },
    {
      'title': 'Pop & Global',
      'query': 'Global Pop Hits',
      'colors': [const Color(0xFF00c6ff), const Color(0xFF0072ff)],
    },
    {
      'title': 'Punjabi Hits',
      'query': 'Punjabi Top Hits',
      'colors': [const Color(0xFFf857a6), const Color(0xFFff5858)],
    },
    {
      'title': 'Lo-Fi & Chill',
      'query': 'Lofi Chill Beats',
      'colors': [const Color(0xFF11998e), const Color(0xFF38ef7d)],
    },
    {
      'title': 'Workout Energy',
      'query': 'Workout Music Beats',
      'colors': [const Color(0xFFFF8008), const Color(0xFFFFC837)],
    },
    {
      'title': 'Romance & Love',
      'query': 'Romantic Hindi Songs',
      'colors': [const Color(0xFFee9ca7), const Color(0xFFffdde1)],
    },
    {
      'title': 'Hip-Hop & Rap',
      'query': 'Hip Hop Hits',
      'colors': [const Color(0xFF3A1C71), const Color(0xFFD76D77)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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
      _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
        if (!mounted) return;
        final results = await _musicService.fetchSuggestions(query, limit: 8);
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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    _debounceTimer?.cancel();

    await _prefs.addToSearchHistory(query);

    setState(() {
      _isSearching = true;
      _currentQuery = query;
      _currentPage = 1;
      _hasMore = true;
      _suggestions.clear();
      _searchResults.clear();
    });

    final results = await _musicService.searchSongs(query, page: 1);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
        if (results.isEmpty || results.length < 20) {
          _hasMore = false;
        }
      });
    }
  }

  void _loadMoreResults() async {
    if (_isLoadingMore || !_hasMore || _isSearching || _currentQuery.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    final newResults = await _musicService.searchSongs(_currentQuery, page: nextPage);

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (newResults.isEmpty) {
          _hasMore = false;
          // BUG-4 fix: do NOT advance _currentPage on empty results.
          // A transient network failure returning [] would otherwise permanently
          // lock out pagination for this search session.
        } else {
          _currentPage = nextPage;
          _searchResults.addAll(newResults);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _prefs.searchHistory;

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
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 22),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 18),
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
                  ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
                  : (_searchController.text.trim().isNotEmpty &&
                          _suggestions.isNotEmpty &&
                          _searchController.text.trim() != _currentQuery)
                      ? ListView.builder(
                          padding: const EdgeInsets.only(bottom: 160),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: const Icon(Icons.search, color: Colors.white54, size: 20),
                              title: Text(
                                suggestion,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: const Icon(Icons.north_west, color: Colors.white38, size: 18),
                              onTap: () {
                                _searchController.text = suggestion;
                                _performSearch(suggestion);
                              },
                            );
                          },
                        )
                      : _searchResults.isNotEmpty
                          ? ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 160),
                          itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _searchResults.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(color: Theme.of(context).primaryColor, strokeWidth: 2.5),
                                ),
                              );
                            }

                            final video = _searchResults[index];
                            final hdThumbnail = MusicService.getHdThumbnail(video.id.value);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
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
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                video.author,
                                maxLines: 1,
                                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                                onPressed: () {},
                              ),
                              onTap: () {
                                _musicService.playSong(video);
                              },
                            );
                          },
                        )

                      : ListView(
                          padding: const EdgeInsets.only(bottom: 160),
                          children: [
                            if (history.isNotEmpty) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent Searches',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _prefs.clearSearchHistory();
                                      setState(() {});
                                    },
                                    child: Text(
                                      'Clear All',
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: history.map((item) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF181824),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        width: 1,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(24),
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _searchController.text = item;
                                        _performSearch(item);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.history_rounded, size: 15, color: Colors.white60),
                                            const SizedBox(width: 6),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 180),
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
                                                _prefs.removeFromSearchHistory(item);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: Colors.white12,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close_rounded, size: 12, color: Colors.white70),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                            const Text(
                              'Browse Categories',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.7,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final cat = _categories[index];
                                final List<Color> colors = cat['colors'];

                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _searchController.text = cat['title'];
                                    _performSearch(cat['query']);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: colors,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colors.first.withValues(alpha: 0.35),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Text(
                                        cat['title'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
