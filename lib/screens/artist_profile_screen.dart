import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/jio_album.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../services/dynamic_artist_service.dart';
import '../services/canonical_song_dedup.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/song_options_bottom_sheet.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/mini_player.dart';
import '../widgets/artist/artist_header.dart';
import '../widgets/artist/artist_action_deck.dart';
import '../widgets/artist/artist_popular_tracks.dart';
import '../widgets/artist/artist_albums_section.dart';
import '../widgets/artist/artist_about_card.dart';

/// Dedicated Artist Profile & Discography Screen with deep multi-language,
/// movie range, and filmography filters.
class ArtistProfileScreen extends StatefulWidget {
  final ArtistItem? artist;
  final String artistName;

  const ArtistProfileScreen({super.key, this.artist, required this.artistName});

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  final MusicService _musicService = MusicService();
  final DynamicArtistService _artistService = DynamicArtistService();
  final PreferencesService _prefs = PreferencesService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  late final String _canonicalName;
  late final ArtistItem? _artistItem;
  late final List<String> _languages;
  late final List<String> _filmography;

  final List<String> _eraOptions = const [
    'All Eras',
    '2020–2025',
    '2010–2019',
    '2000–2009',
    'Classics',
  ];

  List<Video> _allSongs = [];
  List<JioAlbum> _albums = [];
  bool _isLoading = true;
  bool _isLoadingAlbums = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;

  // Active Filter State
  String _selectedLanguage = 'All';
  String? _selectedMovie;
  String _selectedEra = 'All Eras';
  String _inArtistQuery = '';

  @override
  void initState() {
    super.initState();
    final matched = _artistService.findArtist(widget.artistName);
    _artistItem = widget.artist ?? matched;
    _canonicalName = _artistItem?.name ?? widget.artistName.trim();

    _languages = ['All', ..._artistService.getArtistLanguages(_canonicalName)];
    _filmography = _artistService.getFilmography(_canonicalName);

    _searchController.addListener(() {
      setState(() {
        _inArtistQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _scrollController.addListener(_onScroll);
    _musicService.addListener(_onMusicServiceChanged);
    _prefs.addListener(_onMusicServiceChanged);

    _loadInitialDiscography();
    _loadAlbums();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _musicService.removeListener(_onMusicServiceChanged);
    _prefs.removeListener(_onMusicServiceChanged);
    super.dispose();
  }

  void _onMusicServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      _loadMoreDiscography();
    }
  }

  Future<void> _loadInitialDiscography() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final songs = await _musicService.fetchArtistDiscography(
        _canonicalName,
        page: 1,
      );
      if (mounted) {
        setState(() {
          _allSongs = songs;
          _isLoading = false;
          _hasMore = songs.isNotEmpty;
        });

        // Immediately prefetch page 2 in background so the profile unlocks 150-200+ songs right away
        if (songs.isNotEmpty) {
          _prefetchPage2();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoadingAlbums = true);
    try {
      final results = await _musicService.searchAlbums(
        _canonicalName,
        limit: 16,
      );
      if (mounted) {
        setState(() {
          _albums = results;
          _isLoadingAlbums = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAlbums = false);
    }
  }

  Future<void> _prefetchPage2() async {
    if (!mounted || _isLoadingMore || _currentPage >= 2) return;
    try {
      final batch = await _musicService.fetchArtistDiscography(
        _canonicalName,
        page: 2,
      );
      if (mounted && batch.isNotEmpty) {
        setState(() {
          _currentPage = 2;
          final uniqueNew = CanonicalSongDedup.deduplicateList(
            _allSongs,
            batch,
          );
          _allSongs.addAll(uniqueNew);
          _hasMore = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMoreDiscography() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final batch = await _musicService.fetchArtistDiscography(
        _canonicalName,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _currentPage = nextPage;
          if (batch.isNotEmpty) {
            final uniqueNew = CanonicalSongDedup.deduplicateList(
              _allSongs,
              batch,
            );
            _allSongs.addAll(uniqueNew);
          }
          // Exhaust up to 10 deep query tiers; stop if empty past album tiers
          _hasMore = nextPage < 10 && (batch.isNotEmpty || nextPage <= 4);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Evaluates whether a song matches the active movie range / era filter
  bool _matchesEra(Video song, String era) {
    if (era == 'All Eras') return true;

    final lower = song.title.toLowerCase();

    // 1. Check YouTube upload date if present
    int? year;
    if (song.uploadDate != null) {
      year = song.uploadDate!.year;
    }

    // 2. Check year in title if present (e.g. "Song Name (1999)")
    final yearMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(lower);
    if (yearMatch != null) {
      final parsed = int.tryParse(yearMatch.group(1) ?? '');
      if (parsed != null) year = parsed;
    }

    if (year != null) {
      if (era == '2020–2025') return year >= 2020;
      if (era == '2010–2019') return year >= 2010 && year <= 2019;
      if (era == '2000–2009') return year >= 2000 && year <= 2009;
      if (era == 'Classics') return year < 2000;
    }

    // Secondary semantic checks for Classics
    if (era == 'Classics') {
      return lower.contains('classic') ||
          lower.contains('old') ||
          lower.contains('retro') ||
          lower.contains('golden');
    }

    return false;
  }

  /// Client-side filtered songs based on Language, Movie, Era, and In-Artist Search
  List<Video> get _filteredSongs {
    return _allSongs.where((song) {
      final title = song.title.toLowerCase();
      final author = song.author.toLowerCase();

      // 1. Language Filter
      if (_selectedLanguage != 'All') {
        final lang = _selectedLanguage.toLowerCase();
        final cachedLang = CanonicalSongDedup.getSongLanguage(
          song.id.value,
        )?.toLowerCase();
        final detectedTitleLang = CanonicalSongDedup.detectLanguage(
          song.title,
        )?.toLowerCase();
        final detectedAuthorLang = CanonicalSongDedup.detectLanguage(
          song.author,
        )?.toLowerCase();

        final explicitMatch =
            cachedLang == lang ||
            detectedTitleLang == lang ||
            detectedAuthorLang == lang ||
            title.contains(lang) ||
            author.contains(lang);

        if (explicitMatch) {
          // Explicitly matched selected language
        } else if (_artistItem != null &&
            _artistItem.language.toLowerCase() == lang) {
          // If artist is primarily of this language, match unless song is detected as another language
          final detectedOther =
              detectedTitleLang ?? detectedAuthorLang ?? cachedLang;
          if (detectedOther != null && detectedOther != lang) {
            return false;
          }
        } else {
          return false;
        }
      }

      // 2. Movie Filter
      if (_selectedMovie != null && _selectedMovie!.isNotEmpty) {
        final movie = _selectedMovie!.toLowerCase();
        if (!title.contains(movie)) return false;
      }

      // 3. Era / Movie Range Filter
      if (!_matchesEra(song, _selectedEra)) {
        return false;
      }

      // 4. In-Artist Live Search Query
      if (_inArtistQuery.isNotEmpty) {
        final matchesQuery =
            title.contains(_inArtistQuery) || author.contains(_inArtistQuery);
        if (!matchesQuery) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;
    final filtered = _filteredSongs;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: Stack(
        children: [
          ResponsiveWrapper(
            maxWidth: 860,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 1. Hero AppBar with Artist Avatar & Back Action
                ArtistHeader(
                  canonicalName: _canonicalName,
                  artistItem: _artistItem,
                  themeColor: themeColor,
                  onBack: () => Navigator.pop(context),
                ),

                // 2. Action Deck: Play All, Shuffle, Radio & Follow
                SliverToBoxAdapter(
                  child: ArtistActionDeck(
                    artistName: _canonicalName,
                    songs: filtered,
                    themeColor: themeColor,
                  ),
                ),

                // 3. Official Soundtracks & Albums Carousel
                SliverToBoxAdapter(
                  child: ArtistAlbumsSection(
                    albums: _albums,
                    isLoading: _isLoadingAlbums,
                    themeColor: themeColor,
                  ),
                ),

                // 4. Top 5 Popular Tracks
                SliverToBoxAdapter(
                  child: ArtistPopularTracks(
                    songs: filtered,
                    themeColor: themeColor,
                  ),
                ),

                // 3. In-Artist Live Search Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161622),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search within $_canonicalName\'s tracks...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                          suffixIcon: _inArtistQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Language Filter Strip
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'LANGUAGE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 34,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _languages.length,
                          itemBuilder: (context, index) {
                            final lang = _languages[index];
                            final isSelected = _selectedLanguage == lang;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(lang),
                                selected: isSelected,
                                onSelected: (val) {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _selectedLanguage = lang;
                                  });
                                },
                                selectedColor: themeColor,
                                backgroundColor: const Color(0xFF171724),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isSelected
                                        ? themeColor
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),

                // 5. Movie & Era Range Filter Strip
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'MOVIE & ERA RANGE',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (_selectedMovie != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedMovie = null;
                                  });
                                },
                                child: Text(
                                  'Clear Movie',
                                  style: TextStyle(
                                    color: themeColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Era Chips Row
                      SizedBox(
                        height: 32,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _eraOptions.length,
                          itemBuilder: (context, index) {
                            final era = _eraOptions[index];
                            final isSelected = _selectedEra == era;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(era),
                                selected: isSelected,
                                onSelected: (val) {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _selectedEra = era;
                                  });
                                },
                                selectedColor: const Color(0xFF26263C),
                                backgroundColor: const Color(0xFF14141E),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? themeColor
                                      : Colors.white60,
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isSelected
                                        ? themeColor.withValues(alpha: 0.6)
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Movie Chips Row (from curated filmography)
                      if (_filmography.isNotEmpty) ...[
                        SizedBox(
                          height: 32,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filmography.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                final isAll = _selectedMovie == null;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: const Text('All Movies'),
                                    selected: isAll,
                                    onSelected: (_) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _selectedMovie = null;
                                      });
                                    },
                                    selectedColor: const Color(0xFF26263C),
                                    backgroundColor: const Color(0xFF14141E),
                                    labelStyle: TextStyle(
                                      color: isAll
                                          ? themeColor
                                          : Colors.white60,
                                      fontSize: 11.5,
                                      fontWeight: isAll
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: isAll
                                            ? themeColor.withValues(alpha: 0.6)
                                            : Colors.white.withValues(
                                                alpha: 0.06,
                                              ),
                                      ),
                                    ),
                                    showCheckmark: false,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                );
                              }

                              final movie = _filmography[index - 1];
                              final isSelected = _selectedMovie == movie;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.movie_outlined,
                                        size: 13,
                                        color: Colors.white54,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(movie),
                                    ],
                                  ),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedMovie = isSelected
                                          ? null
                                          : movie;
                                    });
                                  },
                                  selectedColor: themeColor.withValues(
                                    alpha: 0.25,
                                  ),
                                  backgroundColor: const Color(0xFF14141E),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 11.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: isSelected
                                          ? themeColor
                                          : Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                    ),
                                  ),
                                  showCheckmark: false,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),

                // 6. Header Status Row
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    child: Row(
                      children: [
                        Text(
                          '${filtered.length} Tracks',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (_selectedMovie != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• $_selectedMovie',
                            style: TextStyle(
                              color: themeColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
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
                  ),
                ),

                // 7. Song List Virtualized Slivers
                if (_isLoading)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const ShimmerSongRow(),
                      childCount: 8,
                    ),
                  )
                else if (filtered.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 48,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.filter_alt_off_rounded,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No songs match the selected filters',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedLanguage = 'All';
                                  _selectedMovie = null;
                                  _selectedEra = 'All Eras';
                                  _searchController.clear();
                                });
                              },
                              child: const Text('Reset All Filters'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final song = filtered[index];
                      final isCurrentSong =
                          _musicService.currentSong?.id.value == song.id.value;
                      final hdThumbnail = MusicService.getHdThumbnail(
                        song.id.value,
                      );

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
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
                          style: TextStyle(
                            color: isCurrentSong ? themeColor : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          song.author,
                          maxLines: 1,
                          style: TextStyle(
                            color: isCurrentSong
                                ? themeColor.withValues(alpha: 0.8)
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
                                  color: themeColor,
                                  size: 16,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.more_horiz,
                                color: Colors.white54,
                              ),
                              onPressed: () =>
                                  showSongOptionsBottomSheet(context, song),
                            ),
                          ],
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _musicService.playPlaylist(filtered, index);
                        },
                      );
                    }, childCount: filtered.length),
                  ),
                  SliverToBoxAdapter(
                    child: ArtistAboutCard(
                      canonicalName: _canonicalName,
                      artistItem: _artistItem,
                      languages: _languages,
                      totalTracks: _allSongs.length,
                      themeColor: themeColor,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 160),
                      child: Center(
                        child: _isLoadingMore
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        themeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Loading more tracks from discography...',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              )
                            : _hasMore
                            ? OutlinedButton.icon(
                                onPressed: _loadMoreDiscography,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: themeColor,
                                  side: BorderSide(
                                    color: themeColor.withValues(alpha: 0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  'Load More Tracks (${_allSongs.length} loaded)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : Text(
                                filtered.length >= 30
                                    ? '• Complete Discography Loaded (${filtered.length} songs) •'
                                    : '',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Floating MiniPlayer visible over artist content when a song is playing
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: MusicService(),
              builder: (context, _) {
                if (MusicService().currentSong == null) {
                  return const SizedBox.shrink();
                }
                return const MiniPlayer();
              },
            ),
          ),
        ],
      ),
    );
  }
}
