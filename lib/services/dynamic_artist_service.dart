import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'preferences_service.dart';
import 'music_service.dart';
import 'playlist_artist_filter.dart';
import 'canonical_song_dedup.dart';
import 'youtube_library_service.dart';

/// Data model representing an artist in the Search section.
class ArtistItem {
  final String name;
  final String genre;
  final String imageUrl;
  final String language;
  final String badge;
  final bool isFromUserHistory;

  const ArtistItem({
    required this.name,
    required this.genre,
    required this.imageUrl,
    required this.language,
    required this.badge,
    this.isFromUserHistory = false,
  });

  ArtistItem copyWith({
    String? name,
    String? genre,
    String? imageUrl,
    String? language,
    String? badge,
    bool? isFromUserHistory,
  }) {
    return ArtistItem(
      name: name ?? this.name,
      genre: genre ?? this.genre,
      imageUrl: imageUrl ?? this.imageUrl,
      language: language ?? this.language,
      badge: badge ?? this.badge,
      isFromUserHistory: isFromUserHistory ?? this.isFromUserHistory,
    );
  }
}

/// Service that dynamically fetches, curates, and ranks artists based on
/// user's listening habits, genre similarity, and popular artists across languages.
class DynamicArtistService {
  static final DynamicArtistService _instance =
      DynamicArtistService._internal();
  factory DynamicArtistService() => _instance;
  DynamicArtistService._internal();

  /// Runtime memory cache for dynamically fetched artist images.
  final Map<String, String> _artistImageCache = {};
  final Set<String> _attemptedArtistFetches = {};

  /// Pre-verified, high-resolution artist catalog with verified 500x500 CDN URLs
  /// covering diverse languages (Telugu, Tamil, Hindi, Punjabi, English, Malayalam).
  static const List<ArtistItem> _curatedCatalog = [
    // --- Telugu ---
    ArtistItem(
      name: 'Devi Sri Prasad',
      genre: 'Tollywood • Mass & Dance Beats',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/a904f8ee6cc4dcb472f75bd8ae1a21da/500x500-000000-80-0-0.jpg',
      language: 'Telugu',
      badge: 'TOP COMPOSER',
    ),
    ArtistItem(
      name: 'Thaman S',
      genre: 'Tollywood • EDM & Mass Grooves',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/f42d76b5c7e4e5dcb1afb373321f16c4/500x500-000000-80-0-0.jpg',
      language: 'Telugu',
      badge: 'BEATS KING',
    ),
    ArtistItem(
      name: 'Sid Sriram',
      genre: 'Carnatic, Melody & Soul',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/fbe3e1d17fc6958e047f011f74233f82/500x500-000000-80-0-0.jpg',
      language: 'Telugu',
      badge: 'SOULFUL',
    ),
    ArtistItem(
      name: 'Anurag Kulkarni',
      genre: 'Tollywood • Folk & Melodies',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/f9f1f4491e7efc579dff25792bbc0fd6/500x500-000000-80-0-0.jpg',
      language: 'Telugu',
      badge: 'MELODIC',
    ),
    ArtistItem(
      name: 'Ram Miriyala',
      genre: 'Telugu Indie • Folk Rock',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/43f399df39ffe548e7ed9b5495abf6e1/500x500-000000-80-0-0.jpg',
      language: 'Telugu',
      badge: 'INDIE HIT',
    ),
    ArtistItem(
      name: 'M.M. Keeravaani',
      genre: 'Oscar Maestro • Epic Melodies',
      imageUrl:
          'https://c.saavncdn.com/artists/M__M__Keeravani_002_20240129101710_500x500.webp',
      language: 'Telugu',
      badge: 'MAESTRO',
    ),
    ArtistItem(
      name: 'Mickey J Meyer',
      genre: 'Tollywood • Youthful Melodies',
      imageUrl: 'https://c.saavncdn.com/artists/Mickey_J_Meyer_500x500.webp',
      language: 'Telugu',
      badge: 'NOSTALGIA',
    ),
    ArtistItem(
      name: 'S.P. Balasubrahmanyam',
      genre: 'Legendary Maestro • Evergreen',
      imageUrl:
          'https://c.saavncdn.com/artists/S_P_Balasubrahmanyam_500x500.webp',
      language: 'Telugu',
      badge: 'LEGEND',
    ),
    ArtistItem(
      name: 'K.S. Chithra',
      genre: 'Melody Queen of India',
      imageUrl:
          'https://c.saavncdn.com/artists/K_S_Chithra_002_20190906071921_500x500.webp',
      language: 'Telugu',
      badge: 'QUEEN',
    ),
    ArtistItem(
      name: 'Mangli',
      genre: 'Folk Anthems & High Energy',
      imageUrl:
          'https://c.saavncdn.com/artists/Mangli_Satyavathi_001_20240701121028_500x500.webp',
      language: 'Telugu',
      badge: 'FOLK QUEEN',
    ),
    ArtistItem(
      name: 'Sunitha',
      genre: 'Tollywood • Timeless Melodies',
      imageUrl:
          'https://c.saavncdn.com/artists/Sunitha_Upadrashta_003_20240424064243_500x500.webp',
      language: 'Telugu',
      badge: 'MELODY',
    ),
    ArtistItem(
      name: 'Karthik',
      genre: 'Soulful Vocals & Romantic Hits',
      imageUrl: 'https://c.saavncdn.com/artists/Karthik_500x500.webp',
      language: 'Telugu',
      badge: 'ROMANTIC',
    ),
    ArtistItem(
      name: 'Haricharan',
      genre: 'Carnatic & Film Melodies',
      imageUrl: 'https://c.saavncdn.com/artists/Haricharan_500x500.webp',
      language: 'Telugu',
      badge: 'SOULFUL',
    ),

    // --- Tamil ---
    ArtistItem(
      name: 'Anirudh Ravichander',
      genre: 'Rockstar • Modern Pop & Mass',
      imageUrl:
          'https://c.saavncdn.com/artists/Anirudh_Ravichander_003_20260121134149_500x500.webp',
      language: 'Tamil',
      badge: 'ROCKSTAR',
    ),
    ArtistItem(
      name: 'A.R. Rahman',
      genre: 'The Mozart of Madras • Sufi & Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/AR_Rahman_002_20210120084455_500x500.webp',
      language: 'Tamil',
      badge: 'MAESTRO',
    ),
    ArtistItem(
      name: 'Sai Abhyankkar',
      genre: 'Tamil Indie • Viral RnB & Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/Sai_Abhyankkar_003_20250707122433_500x500.webp',
      language: 'Tamil',
      badge: 'VIRAL HIT',
    ),
    ArtistItem(
      name: 'Yuvan Shankar Raja',
      genre: 'BGM King • Lo-Fi & Melancholy',
      imageUrl:
          'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_002_20180802174245_500x500.webp',
      language: 'Tamil',
      badge: 'VIBES',
    ),
    ArtistItem(
      name: 'Santhosh Narayanan',
      genre: 'Raw Indie • Acoustic & Folk',
      imageUrl:
          'https://c.saavncdn.com/artists/Santhosh_Narayanan_002_20250527101718_500x500.webp',
      language: 'Tamil',
      badge: 'RAW INDIE',
    ),
    ArtistItem(
      name: 'Harris Jayaraj',
      genre: 'Romantic Pop & Timeless Melodies',
      imageUrl:
          'https://c.saavncdn.com/artists/Harris_Jayaraj_002_20230718071330_500x500.webp',
      language: 'Tamil',
      badge: 'CLASSIC',
    ),
    ArtistItem(
      name: 'Ilaiyaraaja',
      genre: 'Isaignani • Timeless Orchestrations',
      imageUrl:
          'https://c.saavncdn.com/artists/Ilaiyaraaja_001_20251020081419_500x500.webp',
      language: 'Tamil',
      badge: 'MAESTRO',
    ),
    ArtistItem(
      name: 'G.V. Prakash Kumar',
      genre: 'Acoustic Folk & Chartbusters',
      imageUrl:
          'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_003_20251113063655_500x500.webp',
      language: 'Tamil',
      badge: 'HITMAKER',
    ),

    // --- Hindi / Bollywood ---
    ArtistItem(
      name: 'Arijit Singh',
      genre: 'Bollywood • Romantic & Soul',
      imageUrl:
          'https://c.saavncdn.com/artists/Arijit_Singh_004_20241118063717_500x500.webp',
      language: 'Hindi',
      badge: 'SOUL KING',
    ),
    ArtistItem(
      name: 'Pritam',
      genre: 'Bollywood • Chartbuster Anthems',
      imageUrl:
          'https://c.saavncdn.com/artists/Pritam_Chakraborty-20170711073326_500x500.webp',
      language: 'Hindi',
      badge: 'HITMAKER',
    ),
    ArtistItem(
      name: 'Shreya Ghoshal',
      genre: 'Bollywood • Melodious Vocals',
      imageUrl:
          'https://c.saavncdn.com/artists/Shreya_Ghoshal_007_20241101074144_500x500.webp',
      language: 'Hindi',
      badge: 'QUEEN',
    ),
    ArtistItem(
      name: 'Badshah',
      genre: 'Desi Hip-Hop & Party Anthems',
      imageUrl:
          'https://c.saavncdn.com/artists/Badshah_006_20241118064015_500x500.webp',
      language: 'Hindi',
      badge: 'PARTY KING',
    ),
    ArtistItem(
      name: 'Atif Aslam',
      genre: 'Sufi Rock & Soulful Ballads',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/0ea90444148fff9c11d77f06a344724e/500x500-000000-80-0-0.jpg',
      language: 'Hindi',
      badge: 'SOULFUL',
    ),
    ArtistItem(
      name: 'Sonu Nigam',
      genre: 'Golden Voice • Evergreen Romantic',
      imageUrl:
          'https://c.saavncdn.com/artists/Sonu_Nigam_003_20260813182013_500x500.webp',
      language: 'Hindi',
      badge: 'LEGEND',
    ),
    ArtistItem(
      name: 'Shankar Mahadevan',
      genre: 'Breathless • Fusion & Classical',
      imageUrl: 'https://c.saavncdn.com/artists/Shankar_Mahadevan_500x500.webp',
      language: 'Hindi',
      badge: 'VIRTUOSO',
    ),
    ArtistItem(
      name: 'Armaan Malik',
      genre: 'Prince of Romance • Pop Ballads',
      imageUrl:
          'https://c.saavncdn.com/artists/Armaan_Malik_006_20260813132832_500x500.webp',
      language: 'Hindi',
      badge: 'POP PRINCE',
    ),
    ArtistItem(
      name: 'Neha Kakkar',
      genre: 'Peppy Party Hits & Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/Neha_Kakkar_007_20241212115832_500x500.webp',
      language: 'Hindi',
      badge: 'PARTY POP',
    ),
    ArtistItem(
      name: 'Jubin Nautiyal',
      genre: 'Soulful Melodies & Devotional',
      imageUrl:
          'https://c.saavncdn.com/artists/Jubin_Nautiyal_003_20231130204020_500x500.webp',
      language: 'Hindi',
      badge: 'DEVOTION',
    ),

    // --- Punjabi ---
    ArtistItem(
      name: 'Diljit Dosanjh',
      genre: 'Global Punjabi • Folk & Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/Diljit_Dosanjh_005_20231025073054_500x500.webp',
      language: 'Punjabi',
      badge: 'G.O.A.T',
    ),
    ArtistItem(
      name: 'Karan Aujla',
      genre: 'Punjabi Hip-Hop & Trap',
      imageUrl:
          'https://c.saavncdn.com/artists/Karan_Aujla_005_20260925061936_500x500.webp',
      language: 'Punjabi',
      badge: 'CHARTBUSTER',
    ),
    ArtistItem(
      name: 'AP Dhillon',
      genre: 'Punjabi R&B • Retro Melodies',
      imageUrl:
          'https://c.saavncdn.com/artists/AP_Dhillon_004_20251023102150_500x500.jpg',
      language: 'Punjabi',
      badge: 'RETRO WAVE',
    ),
    ArtistItem(
      name: 'Sidhu Moose Wala',
      genre: 'Punjabi Rap & Legend Folk',
      imageUrl:
          'https://c.saavncdn.com/artists/Sidhu_Moose_Wala_004_20250617183705_500x500.webp',
      language: 'Punjabi',
      badge: 'LEGEND',
    ),
    ArtistItem(
      name: 'Guru Randhawa',
      genre: 'High Rated Punjabi Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/Guru_Randhawa_004_20250701125845_500x500.webp',
      language: 'Punjabi',
      badge: 'POP HIT',
    ),

    // --- Malayalam ---
    ArtistItem(
      name: 'Sushin Shyam',
      genre: 'Malayalam • Electronic & Indie',
      imageUrl:
          'https://c.saavncdn.com/artists/Sushin_Shyam_002_20250707125538_500x500.webp',
      language: 'Malayalam',
      badge: 'NEW WAVE',
    ),
    ArtistItem(
      name: 'K.J. Yesudas',
      genre: 'Celestial Voice • Classical Legend',
      imageUrl: 'https://c.saavncdn.com/artists/KJ_Yesudas_500x500.webp',
      language: 'Malayalam',
      badge: 'LEGEND',
    ),
    ArtistItem(
      name: 'Hesham Abdul Wahab',
      genre: 'Soulful Malayalam Indie & Melodies',
      imageUrl:
          'https://c.saavncdn.com/artists/Hesham_Abdul_Wahab_001_20220919094035_500x500.webp',
      language: 'Malayalam',
      badge: 'SOULFUL',
    ),

    // --- Global / English ---
    ArtistItem(
      name: 'The Weeknd',
      genre: 'Dark R&B • Synth-Pop',
      imageUrl:
          'https://c.saavncdn.com/artists/The_Weeknd_002_20241003071400_500x500.webp',
      language: 'English',
      badge: 'AFTER HOURS',
    ),
    ArtistItem(
      name: 'Taylor Swift',
      genre: 'Pop & Narrative Anthems',
      imageUrl:
          'https://c.saavncdn.com/artists/Taylor_Swift_003_20200226074119_500x500.webp',
      language: 'English',
      badge: 'POP QUEEN',
    ),
    ArtistItem(
      name: 'Ed Sheeran',
      genre: 'Acoustic Pop & Ballads',
      imageUrl:
          'https://c.saavncdn.com/artists/Ed_Sheeran_002_20250625073038_500x500.webp',
      language: 'English',
      badge: 'ACOUSTIC',
    ),
    ArtistItem(
      name: 'Dua Lipa',
      genre: 'Dance Pop & Future Nostalgia',
      imageUrl:
          'https://c.saavncdn.com/artists/Dua_Lipa_004_20231120090922_500x500.webp',
      language: 'English',
      badge: 'DANCE POP',
    ),
    ArtistItem(
      name: 'Billie Eilish',
      genre: 'Alt-Pop • Dark & Soulful',
      imageUrl:
          'https://c.saavncdn.com/artists/Billie_Eilish_20190211151539_500x500.webp',
      language: 'English',
      badge: 'ALT POP',
    ),
    ArtistItem(
      name: 'Bruno Mars',
      genre: 'Funk, Pop & Retro Soul',
      imageUrl:
          'https://c.saavncdn.com/artists/Bruno_Mars_003_20260324060413_500x500.webp',
      language: 'English',
      badge: '24K MAGIC',
    ),
  ];

  /// Canonical map to find curated items by lower-cased / normalized artist keys.
  static final Map<String, ArtistItem> _catalogByNormalized = {
    for (final a in _curatedCatalog) PlaylistArtistFilter.normalize(a.name): a,
    // Telugu Aliases
    'dsp': _curatedCatalog.firstWhere((a) => a.name == 'Devi Sri Prasad'),
    'devi sri prasad': _curatedCatalog.firstWhere(
      (a) => a.name == 'Devi Sri Prasad',
    ),
    'thaman': _curatedCatalog.firstWhere((a) => a.name == 'Thaman S'),
    's thaman': _curatedCatalog.firstWhere((a) => a.name == 'Thaman S'),
    'thaman s': _curatedCatalog.firstWhere((a) => a.name == 'Thaman S'),
    'sid sriram': _curatedCatalog.firstWhere((a) => a.name == 'Sid Sriram'),
    'anurag kulkarni': _curatedCatalog.firstWhere(
      (a) => a.name == 'Anurag Kulkarni',
    ),
    'ram miriyala': _curatedCatalog.firstWhere((a) => a.name == 'Ram Miriyala'),
    'keeravani': _curatedCatalog.firstWhere((a) => a.name == 'M.M. Keeravaani'),
    'm m keeravani': _curatedCatalog.firstWhere(
      (a) => a.name == 'M.M. Keeravaani',
    ),
    'mm keeravaani': _curatedCatalog.firstWhere(
      (a) => a.name == 'M.M. Keeravaani',
    ),
    'm.m. keeravaani': _curatedCatalog.firstWhere(
      (a) => a.name == 'M.M. Keeravaani',
    ),
    'mickey j meyer': _curatedCatalog.firstWhere(
      (a) => a.name == 'Mickey J Meyer',
    ),
    'spb': _curatedCatalog.firstWhere((a) => a.name == 'S.P. Balasubrahmanyam'),
    's p balasubrahmanyam': _curatedCatalog.firstWhere(
      (a) => a.name == 'S.P. Balasubrahmanyam',
    ),
    's.p. balasubrahmanyam': _curatedCatalog.firstWhere(
      (a) => a.name == 'S.P. Balasubrahmanyam',
    ),
    'balasubrahmanyam': _curatedCatalog.firstWhere(
      (a) => a.name == 'S.P. Balasubrahmanyam',
    ),
    'chithra': _curatedCatalog.firstWhere((a) => a.name == 'K.S. Chithra'),
    'k s chithra': _curatedCatalog.firstWhere((a) => a.name == 'K.S. Chithra'),
    'k.s. chithra': _curatedCatalog.firstWhere((a) => a.name == 'K.S. Chithra'),
    'mangli': _curatedCatalog.firstWhere((a) => a.name == 'Mangli'),
    'sunitha': _curatedCatalog.firstWhere((a) => a.name == 'Sunitha'),
    'karthik': _curatedCatalog.firstWhere((a) => a.name == 'Karthik'),
    'haricharan': _curatedCatalog.firstWhere((a) => a.name == 'Haricharan'),

    // Tamil Aliases
    'anirudh': _curatedCatalog.firstWhere(
      (a) => a.name == 'Anirudh Ravichander',
    ),
    'anirudh ravichander': _curatedCatalog.firstWhere(
      (a) => a.name == 'Anirudh Ravichander',
    ),
    'ar rahman': _curatedCatalog.firstWhere((a) => a.name == 'A.R. Rahman'),
    'a r rahman': _curatedCatalog.firstWhere((a) => a.name == 'A.R. Rahman'),
    'a.r. rahman': _curatedCatalog.firstWhere((a) => a.name == 'A.R. Rahman'),
    'rahman': _curatedCatalog.firstWhere((a) => a.name == 'A.R. Rahman'),
    'sai abhyankkar': _curatedCatalog.firstWhere(
      (a) => a.name == 'Sai Abhyankkar',
    ),
    'yuvan': _curatedCatalog.firstWhere((a) => a.name == 'Yuvan Shankar Raja'),
    'yuvan shankar raja': _curatedCatalog.firstWhere(
      (a) => a.name == 'Yuvan Shankar Raja',
    ),
    'santhosh': _curatedCatalog.firstWhere(
      (a) => a.name == 'Santhosh Narayanan',
    ),
    'santhosh narayanan': _curatedCatalog.firstWhere(
      (a) => a.name == 'Santhosh Narayanan',
    ),
    'harris': _curatedCatalog.firstWhere((a) => a.name == 'Harris Jayaraj'),
    'harris jayaraj': _curatedCatalog.firstWhere(
      (a) => a.name == 'Harris Jayaraj',
    ),
    'ilaiyaraaja': _curatedCatalog.firstWhere((a) => a.name == 'Ilaiyaraaja'),
    'ilayaraja': _curatedCatalog.firstWhere((a) => a.name == 'Ilaiyaraaja'),
    'gv prakash': _curatedCatalog.firstWhere(
      (a) => a.name == 'G.V. Prakash Kumar',
    ),
    'g.v. prakash kumar': _curatedCatalog.firstWhere(
      (a) => a.name == 'G.V. Prakash Kumar',
    ),

    // Hindi Aliases
    'arijit singh': _curatedCatalog.firstWhere((a) => a.name == 'Arijit Singh'),
    'pritam': _curatedCatalog.firstWhere((a) => a.name == 'Pritam'),
    'shreya ghoshal': _curatedCatalog.firstWhere(
      (a) => a.name == 'Shreya Ghoshal',
    ),
    'badshah': _curatedCatalog.firstWhere((a) => a.name == 'Badshah'),
    'atif aslam': _curatedCatalog.firstWhere((a) => a.name == 'Atif Aslam'),
    'sonu nigam': _curatedCatalog.firstWhere((a) => a.name == 'Sonu Nigam'),
    'shankar mahadevan': _curatedCatalog.firstWhere(
      (a) => a.name == 'Shankar Mahadevan',
    ),
    'armaan malik': _curatedCatalog.firstWhere((a) => a.name == 'Armaan Malik'),
    'neha kakkar': _curatedCatalog.firstWhere((a) => a.name == 'Neha Kakkar'),
    'jubin nautiyal': _curatedCatalog.firstWhere(
      (a) => a.name == 'Jubin Nautiyal',
    ),

    // Punjabi Aliases
    'diljit dosanjh': _curatedCatalog.firstWhere(
      (a) => a.name == 'Diljit Dosanjh',
    ),
    'karan aujla': _curatedCatalog.firstWhere((a) => a.name == 'Karan Aujla'),
    'ap dhillon': _curatedCatalog.firstWhere((a) => a.name == 'AP Dhillon'),
    'sidhu moose wala': _curatedCatalog.firstWhere(
      (a) => a.name == 'Sidhu Moose Wala',
    ),
    'guru randhawa': _curatedCatalog.firstWhere(
      (a) => a.name == 'Guru Randhawa',
    ),

    // Malayalam Aliases
    'sushin shyam': _curatedCatalog.firstWhere((a) => a.name == 'Sushin Shyam'),
    'kj yesudas': _curatedCatalog.firstWhere((a) => a.name == 'K.J. Yesudas'),
    'k.j. yesudas': _curatedCatalog.firstWhere((a) => a.name == 'K.J. Yesudas'),
    'hesham abdul wahab': _curatedCatalog.firstWhere(
      (a) => a.name == 'Hesham Abdul Wahab',
    ),

    // Global
    'the weeknd': _curatedCatalog.firstWhere((a) => a.name == 'The Weeknd'),
    'taylor swift': _curatedCatalog.firstWhere((a) => a.name == 'Taylor Swift'),
    'ed sheeran': _curatedCatalog.firstWhere((a) => a.name == 'Ed Sheeran'),
    'dua lipa': _curatedCatalog.firstWhere((a) => a.name == 'Dua Lipa'),
    'billie eilish': _curatedCatalog.firstWhere(
      (a) => a.name == 'Billie Eilish',
    ),
    'bruno mars': _curatedCatalog.firstWhere((a) => a.name == 'Bruno Mars'),
  };

  /// Generates the dynamic list of artists tailored to the user:
  /// 1. User's top listened artists (from history, play counts, most played)
  /// 2. Genre and language-similar artists
  /// 3. Popular trending artists across diverse languages
  List<ArtistItem> getDynamicArtists() {
    final prefs = PreferencesService();
    final musicService = MusicService();

    final List<ArtistItem> result = [];
    final Set<String> addedNames = {};
    final Set<String> userLanguages = {};

    // 1. Gather artist candidates from user listening habits
    final List<String> userArtistNames = [];

    // (a) Most played artist
    if (prefs.mostPlayedArtist.isNotEmpty) {
      userArtistNames.add(prefs.mostPlayedArtist);
    }

    // (b) Top played artists ranking
    final topList = prefs.getTopPlayedArtists(limit: 15);
    for (final entry in topList) {
      if (entry.key.trim().isNotEmpty) {
        userArtistNames.add(entry.key);
      }
    }

    // (c) Most played songs list
    for (final song in prefs.mostPlayedSongs.take(15)) {
      final author = (song['author'] as String?) ?? '';
      final title = (song['title'] as String?) ?? '';
      final extracted = _extractArtists(author, title);
      userArtistNames.addAll(extracted);
    }

    // (d) Liked songs
    for (final song in musicService.likedSongs.take(15)) {
      final author = song['author'] ?? '';
      final title = song['title'] ?? '';
      final extracted = _extractArtists(author, title);
      userArtistNames.addAll(extracted);
    }

    // (e) Listening history
    for (final song in prefs.listeningHistory.reversed.take(20)) {
      final author = song['author'] ?? '';
      final title = song['title'] ?? '';
      final extracted = _extractArtists(author, title);
      userArtistNames.addAll(extracted);
    }

    // (f) Authenticated Google/YouTube Liked Music tracks
    final ytLiked = YouTubeLibraryService().likedMusic;
    for (final song in ytLiked.take(25)) {
      final extracted = _extractArtists(song.author, song.title);
      userArtistNames.addAll(extracted);
    }

    // 2. Process top user artists (capped at 3 to prevent echo-chamber)
    int userArtistCount = 0;
    const int maxUserArtists = 3;
    for (final rawArtist in userArtistNames) {
      if (userArtistCount >= maxUserArtists) break;
      final norm = PlaylistArtistFilter.normalize(rawArtist);
      if (norm.isEmpty || !_isValidArtistName(rawArtist)) continue;

      final matchedInCatalog = _catalogByNormalized[norm];
      final canonicalName =
          matchedInCatalog?.name ?? _formatArtistName(rawArtist);
      final key = canonicalName.toLowerCase();

      if (addedNames.contains(key)) continue;

      if (matchedInCatalog != null) {
        userLanguages.add(matchedInCatalog.language);
        result.add(
          matchedInCatalog.copyWith(
            isFromUserHistory: true,
            badge: 'TOP ARTIST',
          ),
        );
      } else {
        // Dynamic artist from user history not in static catalog
        final cachedImg = _artistImageCache[key];
        final artistItem = ArtistItem(
          name: canonicalName,
          genre: 'Most Played • Fan Favorite',
          imageUrl: cachedImg ?? _generateAvatarPlaceholder(canonicalName),
          language: 'For You',
          badge: 'TOP ARTIST',
          isFromUserHistory: true,
        );
        result.add(artistItem);

        // Safely fetch verified image in background if not cached yet
        if (cachedImg == null) {
          _fetchArtistImageAsync(canonicalName);
        }
      }
      addedNames.add(key);
      userArtistCount++;
    }

    // 3. Add genre/language-similar artists based on detected user languages
    if (userLanguages.isNotEmpty) {
      for (final artist in _curatedCatalog) {
        final key = artist.name.toLowerCase();
        if (addedNames.contains(key)) continue;

        if (userLanguages.contains(artist.language)) {
          result.add(artist.copyWith(badge: 'FOR YOU'));
          addedNames.add(key);
        }
      }
    }

    // 4. Fill with popular artists of all languages to guarantee variety
    for (final artist in _curatedCatalog) {
      final key = artist.name.toLowerCase();
      if (!addedNames.contains(key)) {
        result.add(artist);
        addedNames.add(key);
      }
    }

    return result;
  }

  /// Extracts genuine artist names from song author & title
  static List<String> _extractArtists(String author, String title) {
    final extracted = PlaylistArtistFilter.extractArtistsFromSong({
      'author': author,
      'title': title,
    });
    if (extracted.isNotEmpty) {
      return extracted.where(_isValidArtistName).toList();
    }

    final cleaned = CanonicalSongDedup.cleanArtist(author);
    if (cleaned.isNotEmpty && _isValidArtistName(cleaned)) {
      return [cleaned];
    }

    if (author.trim().isNotEmpty && _isValidArtistName(author)) {
      return [author.trim()];
    }
    return [];
  }

  static bool _isValidArtistName(String raw) {
    final s = raw.trim();
    if (s.length < 3 || s.length > 35) return false;

    final lower = s.toLowerCase();
    if (_isBlacklistedChannel(lower)) return false;

    // Reject non-artist keywords, record labels, and common video/soundtrack tokens
    const nonArtistTokens = [
      'aditya',
      't-series',
      'tseries',
      'sony music',
      'zee music',
      'speed audio',
      'saregama',
      'lahari music',
      'tips official',
      'geetha arts',
      'mythri',
      'annapurna',
      'suresh productions',
      'mango music',
      'madhura',
      'think music',
      'muzik247',
      'svcc',
      'sithara',
      'dvv',
      'entertainment',
      'records',
      'productions',
      'company',
      'channel',
      'jukebox',
      'mashup',
      'lyrical',
      'video song',
      'official song',
      'full song',
      'remix',
      'promo',
      'teaser',
      'trailer',
      'cover song',
      'karaoke',
      'theme',
      'title track',
      '(from',
      'from "',
      'feat.',
      'ft.',
    ];

    for (final token in nonArtistTokens) {
      if (lower.contains(token)) return false;
    }

    return true;
  }

  static bool _isBlacklistedChannel(String norm) {
    return norm == 'aditya music' ||
        norm == 'tseries' ||
        norm == 't-series' ||
        norm == 'sony music' ||
        norm == 'zee music' ||
        norm == 'speed audio' ||
        norm == 'saregama' ||
        norm == 'lahari music' ||
        norm == 'tips official';
  }

  static String _formatArtistName(String raw) {
    final words = raw.trim().split(RegExp(r'\s+'));
    return words
        .map((w) {
          if (w.isEmpty) return '';
          return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  static String _generateAvatarPlaceholder(String name) {
    final encoded = Uri.encodeComponent(name);
    return 'https://ui-avatars.com/api/?name=$encoded&background=1E1E2C&color=fff&size=512&bold=true';
  }

  /// Background fetch for unknown artist from JioSaavn official catalog
  Future<void> _fetchArtistImageAsync(String artistName) async {
    final key = artistName.toLowerCase();
    if (_artistImageCache.containsKey(key) ||
        _attemptedArtistFetches.contains(key)) {
      return;
    }
    _attemptedArtistFetches.add(key);

    // On Web, direct fetches to www.jiosaavn.com are blocked by CORS policy.
    // Immediately assign avatar placeholder to avoid connection clogging and console errors.
    if (kIsWeb) {
      _artistImageCache[key] = _generateAvatarPlaceholder(artistName);
      return;
    }

    try {
      final url = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getArtistResults&_format=json&cc=in&api_version=4&ctx=android&q=${Uri.encodeComponent(artistName)}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = data['results'] as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          final first = items.first as Map<String, dynamic>;
          final returnedName = (first['name'] as String? ?? '').toLowerCase();
          // Check that the returned artist name actually matches our search query
          if (returnedName.contains(key) || key.contains(returnedName)) {
            final rawImg = first['image'] as String?;
            if (rawImg != null &&
                rawImg.contains('c.saavncdn.com/artists/') &&
                !rawImg.contains('artist-default')) {
              final img = rawImg
                  .replaceAll('50x50', '500x500')
                  .replaceAll('150x150', '500x500');
              _artistImageCache[key] = img;
              return;
            }
          }
        }
      }
      _artistImageCache[key] = _generateAvatarPlaceholder(artistName);
    } catch (e) {
      _artistImageCache[key] = _generateAvatarPlaceholder(artistName);
      debugPrint(
        '[DynamicArtistService] Image fetch error for $artistName: $e',
      );
    }
  }

  /// Returns whether a search query matches a known artist in the catalog or alias map
  static final Set<String> _verifiedGlobalArtists = {
    // Curated & Major Pop
    'the weeknd', 'taylor swift', 'ed sheeran', 'dua lipa', 'billie eilish',
    'bruno mars', 'ariana grande', 'justin bieber', 'drake', 'rihanna',
    'beyonce', 'adele', 'post malone', 'maroon 5', 'katy perry',
    'lady gaga', 'selena gomez', 'charlie puth', 'shawn mendes',
    'camila cabello', 'halsey', 'sza', 'olivia rodrigo', 'sabrina carpenter',
    'chappell roan', 'lana del rey', 'sia', 'bebe rexha', 'ellie goulding',
    'zara larsson', 'sam smith', 'harry styles', 'zayn', 'miley cyrus',
    'lorde', 'troye sivan', 'conan gray', 'lauv', 'jeremy zucker',
    'alec benjamin', 'khalid', 'frank ocean', 'daniel caesar', 'giveon',
    'chris brown', 'usher', 'justin timberlake', 'pitbull', 'the kid laroi',
    'lil nas x', 'benson boone', 'teddy swims', 'tate mcrae', 'gracie abrams',
    // EDM / Electronic / Remixers
    'david guetta',
    'calvin harris',
    'avicii',
    'the chainsmokers',
    'chainsmokers',
    'alan walker', 'marshmello', 'kygo', 'martin garrix', 'dj snake',
    'tiesto', 'zedd', 'skrillex', 'steve aoki', 'major lazer',
    'swedish house mafia', 'alesso', 'axwell', 'sebastian ingrosso',
    'deadmau5', 'daft punk', 'robin schulz', 'lost frequencies', 'felix jaehn',
    'alok', 'kshmr', 'r3hab', 'afrojack', 'hardwell', 'armin van buuren',
    'galantis', 'disclosure', 'flume', 'illenium', 'gryffin', 'clean bandit',
    'jonas blue', 'meduza', 'sigala', 'jax jones', 'regard', 'imanbek',
    'joel corry', 'topic', 'fred again', 'peggy gou', 'fisher', 'dom dolla',
    'john summit', 'the blaze', 'blessed madonna', 'the blessed madonna',
    'don diablo', 'funtcase', 'blasterjaxx', 'timmy trumpet', 'w&w', 'kura',
    // Bands & Rock
    'coldplay', 'imagine dragons', 'onerepublic', 'linkin park', 'queen',
    'the beatles', 'michael jackson', 'green day', 'twenty one pilots',
    'the neighbourhood', 'arctic monkeys', 'the 1975', 'panic at the disco',
    'fall out boy', '5 seconds of summer', 'bastille', 'glass animals',
    'hozier', 'vance joy', 'dean lewis', 'james arthur', 'lewis capaldi',
    // Hip-hop / Rap
    'kendrick lamar', 'travis scott', 'j cole', 'kanye west',
    'eminem', 'nicki minaj', 'cardi b', 'megan thee stallion', 'doja cat',
    'future', 'metro boomin', '21 savage', 'lil baby', 'gunna', 'playboi carti',
    'juice wrld', 'xxxtentacion', 'asap rocky', 'tyler the creator',
    'jack harlow', 'central cee',
    // Indic & Regional
    'devi sri prasad', 'dsp', 'thaman s', 'thaman', 'sid sriram',
    'anurag kulkarni', 'ram miriyala', 'mm keeravaani', 'keeravani',
    'mickey j meyer', 'sp balasubrahmanyam', 'spb', 'ks chithra', 'chithra',
    'mangli', 'sunitha', 'karthik', 'haricharan', 'anirudh ravichander',
    'anirudh', 'ar rahman', 'a r rahman', 'rahman', 'sai abhyankkar',
    'yuvan shankar raja', 'yuvan', 'santhosh narayanan', 'harris jayaraj',
    'ilaiyaraaja', 'gv prakash kumar', 'gv prakash', 'arijit singh', 'pritam',
    'shreya ghoshal',
    'badshah',
    'atif aslam',
    'sonu nigam',
    'shankar mahadevan',
    'armaan malik', 'neha kakkar', 'jubin nautiyal', 'diljit dosanjh',
    'karan aujla', 'ap dhillon', 'sidhu moose wala', 'guru randhawa',
    'sushin shyam', 'kj yesudas', 'hesham abdul wahab', 'darshan raval',
    'b praak', 'jasleen royal', 'prateek kuhad', 'anuv jain', 'ritviz',
    'nucleya', 'yo yo honey singh', 'honey singh', 'raftaar', 'divine',
    'mc stan', 'king', 'shubh', 'dhee', 'jonita gandhi', 'mohit chauhan',
    'kk', 'lucky ali', 'javed ali', 'neeti mohan', 'shilpa rao', 'amit trivedi',
    'vishal shekhar', 'vishal dadlani', 'shekhar ravjiani', 'sachin jigar',
    'shankar ehsaan loy', 'ajay atul', 'himesh reshammiya', 'vijay prakash',
    'sanjith hegde', 'raghu dixit', 'benny dayal', 'neeraj shridhar',
    'mika singh', 'sukhwinder singh', 'udit narayan', 'kumar sanu',
    'alka yagnik', 'kavita krishnamurthy', 'asha bhosle', 'lata mangeshkar',
  };

  /// Returns whether a search query matches a known artist in the catalog or alias map
  bool isKnownArtist(String query) {
    final norm = PlaylistArtistFilter.normalize(query);
    if (norm.isEmpty) return false;
    if (_catalogByNormalized.containsKey(norm)) return true;
    for (final artist in _curatedCatalog) {
      if (artist.name.toLowerCase() == query.trim().toLowerCase()) return true;
      final aNorm = PlaylistArtistFilter.normalize(artist.name);
      if (aNorm == norm) return true;
    }
    return false;
  }

  /// Returns whether a query corresponds to a recognized, verified recording artist in DilSe,
  /// checking the curated catalog, known Indic composers/singers, verified global artist registry,
  /// or multi-credit collaborative tokens.
  bool isVerifiedArtist(String query) {
    if (query.trim().isEmpty) return false;
    final norm = PlaylistArtistFilter.normalize(query);
    if (norm.isEmpty) return false;

    if (isKnownArtist(query)) return true;
    if (_verifiedGlobalArtists.contains(norm)) return true;

    // Check individual artist tokens if separated by commas / feat / with / &
    final parts = query.split(
      RegExp(
        r'[,/;&]|(?:\s+feat\.?\s+)|\s+ft\.?\s+|(?:\s+with\s+)',
        caseSensitive: false,
      ),
    );
    for (final p in parts) {
      final pNorm = PlaylistArtistFilter.normalize(p);
      if (pNorm.isNotEmpty &&
          (isKnownArtist(p) || _verifiedGlobalArtists.contains(pNorm))) {
        return true;
      }
    }

    return false;
  }

  /// Returns the matched artist item from the curated catalog or alias map, if any
  ArtistItem? findArtist(String query) {
    final norm = PlaylistArtistFilter.normalize(query);
    if (norm.isEmpty) return null;
    if (_catalogByNormalized.containsKey(norm)) {
      return _catalogByNormalized[norm];
    }
    for (final artist in _curatedCatalog) {
      if (artist.name.toLowerCase() == query.trim().toLowerCase()) {
        return artist;
      }
      final aNorm = PlaylistArtistFilter.normalize(artist.name);
      if (aNorm == norm) return artist;
    }
    return null;
  }

  /// Returns the verified filmography or iconic album catalog for an artist.
  List<String> getFilmography(String artistName) {
    final clean = artistName.trim();
    if (clean.isEmpty) return const [];
    final matched = findArtist(clean);
    final canonicalName = matched?.name ?? clean;
    final norm = PlaylistArtistFilter.normalize(canonicalName);
    return _artistFilmographies[norm] ?? const [];
  }

  /// Returns the active languages associated with an artist (e.g. multi-lingual repertoire).
  List<String> getArtistLanguages(String artistName) {
    final clean = artistName.trim();
    final matched = findArtist(clean);
    final primary = matched?.language ?? 'Telugu';
    final norm = PlaylistArtistFilter.normalize(matched?.name ?? clean);

    const multiLingual = {
      'devi sri prasad': ['Telugu', 'Tamil', 'Hindi'],
      'a r rahman': ['Tamil', 'Hindi', 'Telugu'],
      'ar rahman': ['Tamil', 'Hindi', 'Telugu'],
      'anirudh ravichander': ['Tamil', 'Telugu', 'Hindi'],
      'thaman s': ['Telugu', 'Tamil', 'Kannada'],
      'sid sriram': ['Telugu', 'Tamil', 'Malayalam', 'Kannada'],
      's p balasubrahmanyam': ['Telugu', 'Tamil', 'Kannada', 'Hindi'],
      'spb': ['Telugu', 'Tamil', 'Kannada', 'Hindi'],
      'k s chithra': ['Telugu', 'Tamil', 'Malayalam', 'Kannada'],
      'chithra': ['Telugu', 'Tamil', 'Malayalam', 'Kannada'],
      'shreya ghoshal': ['Hindi', 'Telugu', 'Tamil', 'Kannada', 'Malayalam'],
      'ilaiyaraaja': ['Tamil', 'Telugu', 'Malayalam', 'Hindi'],
      'harris jayaraj': ['Tamil', 'Telugu'],
      'm m keeravani': ['Telugu', 'Hindi', 'Tamil'],
      'yuvan shankar raja': ['Tamil', 'Telugu'],
      'g v prakash kumar': ['Tamil', 'Telugu'],
      'santhosh narayanan': ['Tamil', 'Telugu'],
      'arijit singh': ['Hindi', 'Bengali', 'Telugu'],
      'sushin shyam': ['Malayalam', 'Tamil'],
      'ravi basrur': ['Kannada', 'Telugu', 'Hindi', 'Tamil'],
    };

    final list = multiLingual[norm];
    if (list != null) return list;
    return [primary];
  }

  /// Returns a curated 6–7 line biographical profile of the artist.
  /// Falls back to an intelligent dynamic editorial profile if not in the curated registry.
  String getArtistBio(String artistName) {
    final clean = artistName.trim();
    if (clean.isEmpty) return '';
    final matched = findArtist(clean);
    final canonicalName = matched?.name ?? clean;
    final norm = PlaylistArtistFilter.normalize(canonicalName);

    final curated = _artistBiographies[norm];
    if (curated != null && curated.isNotEmpty) {
      return curated;
    }

    // Dynamic intelligent editorial fallback (6–7 lines)
    final genre = matched?.genre ?? 'Contemporary & Playback Music';
    final lang = matched?.language ?? 'Multi-lingual';
    final badge = matched?.badge ?? 'FEATURED ARTIST';
    final films = getFilmography(canonicalName);
    final filmHighlight = films.isNotEmpty
        ? ' Notable soundtracks and albums include ${films.take(4).join(', ')}.'
        : '';

    return '$canonicalName is an acclaimed musical artist recognized for exceptional contributions to the $lang music landscape. '
        'Celebrated under the badge of $badge, their repertoire spans $genre, resonating with listeners across regional and global music communities. '
        'Their distinctive style brings rich acoustic arrangements, expressive vocal performances, and genre-blending compositions.$filmHighlight '
        'With a rapidly growing discography and multiple streaming favorites available on DilSe, their sound continues to captivate music enthusiasts. '
        'Explore their complete catalog of original master recordings, film collaborations, and chart-topping hits above.';
  }

  /// Curated 6–7 line biographies for top composers, directors, and vocalists.
  static const Map<String, String> _artistBiographies = {
    // --- Telugu ---
    'devi sri prasad':
        'Devi Sri Prasad (DSP) is a National Award-winning Indian composer, lyricist, and singer who revolutionized commercial South Indian cinema with his high-energy mass rhythms, dynamic brass sections, and evergreen romantic melodies. '
        'Debuting with Devi (1999), he rose to nationwide acclaim across Telugu and Tamil cinema with landmark soundtracks like Arya, Varsham, Bommarillu, Jalsa, and Rangasthalam. '
        'His monumental score for the global blockbuster franchise Pushpa: The Rise and Pushpa 2: The Rule earned him the National Film Award for Best Music Direction. '
        'Over a career spanning more than two decades and over 100 films, DSP has accumulated numerous Filmfare and SIIMA trophies. '
        'A consummate live performer, he is as renowned for his electrifying stadium concerts as he is for his genre-defining dance hooks. '
        'His versatile catalog remains an enduring cornerstone of contemporary South Indian pop culture.',
    'dsp':
        'Devi Sri Prasad (DSP) is a National Award-winning Indian composer, lyricist, and singer who revolutionized commercial South Indian cinema with his high-energy mass rhythms, dynamic brass sections, and evergreen romantic melodies. '
        'Debuting with Devi (1999), he rose to nationwide acclaim across Telugu and Tamil cinema with landmark soundtracks like Arya, Varsham, Bommarillu, Jalsa, and Rangasthalam. '
        'His monumental score for the global blockbuster franchise Pushpa: The Rise and Pushpa 2: The Rule earned him the National Film Award for Best Music Direction. '
        'Over a career spanning more than two decades and over 100 films, DSP has accumulated numerous Filmfare and SIIMA trophies. '
        'A consummate live performer, he is as renowned for his electrifying stadium concerts as he is for his genre-defining dance hooks. '
        'His versatile catalog remains an enduring cornerstone of contemporary South Indian pop culture.',
    'thaman s':
        'Thaman S is an acclaimed Indian music composer and drummer who reshaped the sonic identity of contemporary Telugu and Tamil cinema through thumping EDM basslines, live orchestral brass, and viral mass anthems. '
        'Beginning his musical journey as a rhythmist under legendary directors, his breakthrough with Kick and Dookudu established him as a premier hitmaker. '
        'His epochal soundtrack for Ala Vaikunthapurramuloo shattered digital streaming records globally, earning him the prestigious National Film Award for Best Music Direction. '
        'Thaman\'s high-octane background scores in films like Sarrainodu, Akhanda, and Bheemla Nayak are celebrated for their visceral theatrical energy. '
        'Blending traditional Indian percussion with cutting-edge electronic synthesizers, he consistently delivers chart-topping singles. '
        'He stands as one of the most prolific and technically adept music producers in Indian cinema.',
    'thaman':
        'Thaman S is an acclaimed Indian music composer and drummer who reshaped the sonic identity of contemporary Telugu and Tamil cinema through thumping EDM basslines, live orchestral brass, and viral mass anthems. '
        'Beginning his musical journey as a rhythmist under legendary directors, his breakthrough with Kick and Dookudu established him as a premier hitmaker. '
        'His epochal soundtrack for Ala Vaikunthapurramuloo shattered digital streaming records globally, earning him the prestigious National Film Award for Best Music Direction. '
        'Thaman\'s high-octane background scores in films like Sarrainodu, Akhanda, and Bheemla Nayak are celebrated for their visceral theatrical energy. '
        'Blending traditional Indian percussion with cutting-edge electronic synthesizers, he consistently delivers chart-topping singles. '
        'He stands as one of the most prolific and technically adept music producers in Indian cinema.',
    'sid sriram':
        'Sid Sriram is an Indian-American singer, songwriter, and composer who seamlessly bridges the intricate worlds of South Indian Carnatic classical music with modern R&B, soul, and contemporary film playback. '
        'Raised in California and an alumnus of Berklee College of Music, he was introduced to Indian cinema by A.R. Rahman with the breakthrough song \'Adiye\' from Kadal. '
        'His deeply emotive vocal timbre and improvisational gamakas propelled him to superstardom with viral anthems like \'Inkem Inkem\', \'Samajavaragamana\', \'Srivalli\', and \'Kannaana Kanney\'. '
        'Beyond film playback, Sid has released critically acclaimed independent albums and performed at premier international festivals including Coachella. '
        'His unique ability to infuse spiritual classical nuances into urban pop ballads has redefined the sound of modern Indian romantic music. '
        'He remains one of the most sought-after vocalists across South Asian music.',
    'anurag kulkarni':
        'Anurag Kulkarni is a celebrated Indian playback singer acclaimed for his resonant vocal power, emotional depth, and versatility across Telugu cinema. '
        'Rising to fame as the winner of Super Singer season 8, he swiftly transitioned into mainstream cinema with standout performances that captured hearts across the Telugu states. '
        'His soul-stirring rendition of \'Asha Pasham\' from Care of Kancharapalem and festive mega-hits like \'Ramuloo Ramulaa\' and \'Pilla Raa\' showcased his extraordinary dynamic range. '
        'Frequently collaborating with top composers including Thaman S, Devi Sri Prasad, and Mickey J Meyer, Anurag brings authenticity to rural folk as effortlessly as modern urban melodies. '
        'He has won multiple Filmfare and SIIMA awards for his evocative playback singing. '
        'His distinct baritone voice continues to define heartfelt contemporary cinema.',
    'ram miriyala':
        'Ram Miriyala is a trailblazing Telugu indie musician, composer, and playback singer celebrated for his grassroots folk-rock aesthetic, candid storytelling, and vibrant vocal delivery. '
        'First capturing public imagination as the lead vocalist of ChowRaasta, his viral independent tracks like \'Oorellipota Mama\' and \'Maya\' struck a deep chord with youth across Telangana and Andhra Pradesh. '
        'His transition into mainstream film music produced unstoppable viral chartbusters, notably \'Chitti\' from Jathi Ratnalu, \'Tillu Anna DJ Pedithe\', and \'Dhoom Dhaam\' from Dasara. '
        'Ram\'s signature sound marries earthy rural folk cadence with acoustic indie guitars and infectious rhythmic bounce. '
        'He represents a new generation of self-made regional artists revitalizing local dialects and indie culture. '
        'His energetic tracks remain instant crowd favorites across concerts and streaming charts.',
    'mm keeravaani':
        'M.M. Keeravaani is an Academy Award and Golden Globe-winning maestro, classical composer, and playback singer who stands as a titan of Indian cinema. '
        'Over an illustrious career spanning three decades and more than 200 films, he has composed timeless scores in Telugu, Hindi, Tamil, and Malayalam. '
        'His legendary partnership with visionary filmmaker S.S. Rajamouli yielded cinematic landmarks including Magadheera, Eega, the Baahubali duology, and RRR. '
        'The viral global phenomenon \'Naatu Naatu\' made history by winning the Oscar for Best Original Song, elevating Indian film music onto the highest international stage. '
        'Keeravaani\'s compositions are distinguished by rich classical counterpoint, dramatic orchestral storytelling, and profound devotional serenity. '
        'He is a recipient of the Padma Shri and multiple National Film Awards.',
    'keeravani':
        'M.M. Keeravaani is an Academy Award and Golden Globe-winning maestro, classical composer, and playback singer who stands as a titan of Indian cinema. '
        'Over an illustrious career spanning three decades and more than 200 films, he has composed timeless scores in Telugu, Hindi, Tamil, and Malayalam. '
        'His legendary partnership with visionary filmmaker S.S. Rajamouli yielded cinematic landmarks including Magadheera, Eega, the Baahubali duology, and RRR. '
        'The viral global phenomenon \'Naatu Naatu\' made history by winning the Oscar for Best Original Song, elevating Indian film music onto the highest international stage. '
        'Keeravaani\'s compositions are distinguished by rich classical counterpoint, dramatic orchestral storytelling, and profound devotional serenity. '
        'He is a recipient of the Padma Shri and multiple National Film Awards.',
    'mickey j meyer':
        'Mickey J Meyer is an acclaimed Indian music composer known for introducing a fresh, breezy, and youthful acoustic soundscape to contemporary Telugu cinema. '
        'A graduate of the prestigious Trinity College of Music in London, he established his signature style with lush piano chords, string arrangements, and acoustic guitar textures. '
        'His breakthrough soundtracks for Happy Days and Kotha Bangaru Lokam became cultural touchstones for an entire generation of college students. '
        'He continued his artistic triumph with celebrated scores like Leader, SVSC, A Aa, and the biographical epic Mahanati, earning multiple Filmfare Awards. '
        'Mickey\'s music is marked by gentle melodies, clean orchestral harmonies, and deeply nostalgic emotional undertones. '
        'He remains one of the most respected purveyors of melodic cinema in South India.',
    'sp balasubrahmanyam':
        'Sripathi Panditaradhyula Balasubrahmanyam (SPB) was a legendary Indian playback singer, composer, and actor whose peerless career spanned over five decades with more than 40,000 recorded songs across 16 languages. '
        'Recipient of six National Film Awards, the Padma Shri, Padma Bhushan, and Padma Vibhushan, SPB was the definitive voice for generations of icons across Indian cinema. '
        'Renowned for his astonishing breath control, impeccable diction, and infectious expressive joy, he collaborated with maestros from Ilaiyaraaja to A.R. Rahman. '
        'His historic recordings in Sankarabharanam, Saagara Sangamam, Ek Duuje Ke Liye, and Keladi Kanmani remain gold standards in world vocal music. '
        'SPB\'s profound musicality, warmth, and generous spirit made him a revered cultural ambassador. '
        'His timeless catalog lives on as an enduring cornerstone of Indian musical heritage.',
    'spb':
        'Sripathi Panditaradhyula Balasubrahmanyam (SPB) was a legendary Indian playback singer, composer, and actor whose peerless career spanned over five decades with more than 40,000 recorded songs across 16 languages. '
        'Recipient of six National Film Awards, the Padma Shri, Padma Bhushan, and Padma Vibhushan, SPB was the definitive voice for generations of icons across Indian cinema. '
        'Renowned for his astonishing breath control, impeccable diction, and infectious expressive joy, he collaborated with maestros from Ilaiyaraaja to A.R. Rahman. '
        'His historic recordings in Sankarabharanam, Saagara Sangamam, Ek Duuje Ke Liye, and Keladi Kanmani remain gold standards in world vocal music. '
        'SPB\'s profound musicality, warmth, and generous spirit made him a revered cultural ambassador. '
        'His timeless catalog lives on as an enduring cornerstone of Indian musical heritage.',
    'ks chithra':
        'Krishnan Nair Shantakumari Chithra, revered across the subcontinent as the \'Nightingale of South India\' and \'Chinna Kuyil\', is a six-time National Film Award-winning playback singer and Carnatic exponent. '
        'With an extraordinary legacy of over 25,000 recorded songs across Indian and foreign languages, her crystal-pure voice has graced cinema for four decades. '
        'Her historic collaborations with Ilaiyaraaja, A.R. Rahman, and M.M. Keeravaani produced timeless classics across Malayalam, Tamil, Telugu, Kannada, and Hindi. '
        'Honored with the Padma Bhushan and Padma Shri, Chithra\'s pitch-perfect precision and emotional nuance remain unmatched. '
        'From delicate classical ragas to soaring cinematic ballads, she traverses musical boundaries with effortless grace. '
        'She is universally celebrated as one of India\'s greatest living vocal treasures.',
    'chithra':
        'Krishnan Nair Shantakumari Chithra, revered across the subcontinent as the \'Nightingale of South India\' and \'Chinna Kuyil\', is a six-time National Film Award-winning playback singer and Carnatic exponent. '
        'With an extraordinary legacy of over 25,000 recorded songs across Indian and foreign languages, her crystal-pure voice has graced cinema for four decades. '
        'Her historic collaborations with Ilaiyaraaja, A.R. Rahman, and M.M. Keeravaani produced timeless classics across Malayalam, Tamil, Telugu, Kannada, and Hindi. '
        'Honored with the Padma Bhushan and Padma Shri, Chithra\'s pitch-perfect precision and emotional nuance remain unmatched. '
        'From delicate classical ragas to soaring cinematic ballads, she traverses musical boundaries with effortless grace. '
        'She is universally celebrated as one of India\'s greatest living vocal treasures.',
    'mangli':
        'Mangli (Satyavathi Rathod) is a dynamic Indian playback singer, television presenter, and cultural icon renowned for her spirited Banjara and Telangana folk anthems. '
        'With electrifying vocals and charismatic energy, she popularized traditional folk celebrations through viral Bathukamma and Bonalu festival tracks. '
        'In mainstream cinema, her hits including \'Saranga Dariya\' from Love Story, \'Ramuloo Ramulaa\', and \'Jwala Reddy\' achieved hundreds of millions of streams, celebrating rural roots on the global stage. '
        'Her authentic rustic cadences and fearless stage performances have made her a household name in Telugu culture. '
        'Mangli stands as a pioneering vocal force connecting heritage folk music with modern cinematic pop.',
    'sunitha':
        'Sunitha Upadrashta is an acclaimed Indian playback singer, dubbing artist, and television host celebrated for her velvety melodious voice and classical finesse in Telugu cinema. '
        'Winner of nine state Nandi Awards and two Filmfare Awards, Sunitha has voiced hundreds of iconic romantic songs and lent her voice to leading heroines across three decades. '
        'Her crystal-clear pronunciation and expressive emotional cadence make her one of the most respected vocalists in South India. '
        'From evergreen duets to serene devotional albums, her vocal warmth resonates deeply across generations of music lovers. '
        'She continues to be an inspiring mentor and classical icon in the South Indian music fraternity.',
    'karthik':
        'Karthik is a versatile Indian playback singer and composer celebrated for his silky vocal texture, effortless high register, and romantic chartbusters across Tamil, Telugu, and Malayalam cinema. '
        'Mentored by A.R. Rahman, Karthik has performed thousands of memorable songs under legendary composers like Harris Jayaraj, Ilaiyaraaja, and Yuvan Shankar Raja, winning several Filmfare and state awards. '
        'His voice became the definitive soundtrack for college romance in films like Orange, Happy Days, Kotha Bangaru Lokam, and Ghajini. '
        'With a smooth, contemporary vocal style and impeccable melodic phrasing, he bridges acoustic pop with soulful film melodies. '
        'His songs remain perpetual favorites on streaming and radio channels.',
    'haricharan':
        'Haricharan is an Indian playback singer and Carnatic classical musician who has contributed extensively to Tamil, Telugu, and Malayalam film music. '
        'Trained under stalwart classical masters, he made his film debut in Kaadhal (2004) under Joshua Sridhar with multiple hit songs, instantly receiving critical praise. '
        'He has since delivered monumental tracks for A.R. Rahman, Santhosh Narayanan, and Harris Jayaraj, notably \'Unakkenna Venum Sollu\' from Yennai Arindhaal. '
        'His rich timbre, expressive microtonal nuances, and effortless classical ornamentation make him a standout interpreter of emotional ballads. '
        'Haricharan regularly performs worldwide in prestigious Carnatic concerts and multi-genre live tours.',

    // --- Tamil ---
    'anirudh ravichander':
        'Anirudh Ravichander is a powerhouse Indian composer, singer, and producer widely celebrated as the rockstar of modern South Indian and Hindi cinema. '
        'Bursting onto the international scene with the viral phenomenon \'Why This Kolaveri Di\', he revolutionized film soundtracks with cutting-edge EDM, trap beats, and soaring rock guitars. '
        'His phenomenal discography features historic blockbusters including Master, Vikram, Jailer, Leo, Jawan, and Devara, regularly generating billions of streams. '
        'Anirudh\'s distinctive fusion of infectious electronic hooks, stadium-scale crowd vocals, and atmospheric background scores commands a massive youth following. '
        'Renowned for high-energy stadium tours and unmatched chart domination, he defines the contemporary commercial sound. '
        'He stands as one of the most influential and bankable music directors in India today.',
    'anirudh':
        'Anirudh Ravichander is a powerhouse Indian composer, singer, and producer widely celebrated as the rockstar of modern South Indian and Hindi cinema. '
        'Bursting onto the international scene with the viral phenomenon \'Why This Kolaveri Di\', he revolutionized film soundtracks with cutting-edge EDM, trap beats, and soaring rock guitars. '
        'His phenomenal discography features historic blockbusters including Master, Vikram, Jailer, Leo, Jawan, and Devara, regularly generating billions of streams. '
        'Anirudh\'s distinctive fusion of infectious electronic hooks, stadium-scale crowd vocals, and atmospheric background scores commands a massive youth following. '
        'Renowned for high-energy stadium tours and unmatched chart domination, he defines the contemporary commercial sound. '
        'He stands as one of the most influential and bankable music directors in India today.',
    'ar rahman':
        'Allahrakha Rahman, universally revered as the \'Mozart of Madras\', is a two-time Academy Award, two-time Grammy Award, and six-time National Film Award-winning maestro and cultural icon. '
        'Since his groundbreaking debut in Roja (1992), Rahman transformed Indian cinema by pioneering the fusion of Eastern classical traditions with electronic synthesizers and Western symphonic palettes. '
        'His illustrious catalog features epochal soundtracks including Bombay, Dil Se.., Lagaan, Slumdog Millionaire, Rockstar, and Ponniyin Selvan. '
        'Honored with the Padma Bhushan, Rahman\'s spiritual Sufi compositions and sonic innovations reshaped world music. '
        'A visionary orchestrator and producer, he continually pushes acoustic frontiers while fostering global cross-cultural collaborations. '
        'He remains one of the world\'s all-time greatest and most celebrated cinematic composers.',
    'a r rahman':
        'Allahrakha Rahman, universally revered as the \'Mozart of Madras\', is a two-time Academy Award, two-time Grammy Award, and six-time National Film Award-winning maestro and cultural icon. '
        'Since his groundbreaking debut in Roja (1992), Rahman transformed Indian cinema by pioneering the fusion of Eastern classical traditions with electronic synthesizers and Western symphonic palettes. '
        'His illustrious catalog features epochal soundtracks including Bombay, Dil Se.., Lagaan, Slumdog Millionaire, Rockstar, and Ponniyin Selvan. '
        'Honored with the Padma Bhushan, Rahman\'s spiritual Sufi compositions and sonic innovations reshaped world music. '
        'A visionary orchestrator and producer, he continually pushes acoustic frontiers while fostering global cross-cultural collaborations. '
        'He remains one of the world\'s all-time greatest and most celebrated cinematic composers.',
    'sai abhyankkar':
        'Sai Abhyankkar is a sensationally talented Indian indie singer, composer, and multi-instrumentalist who emerged as a Gen-Z pop prodigy. '
        'His viral breakout hits \'Katchi Sera\' and \'Aasa Kooda\' shattered records across streaming platforms and social media, blending contemporary Afrobeat rhythms, jazz chords, and Tamil melodies. '
        'Hailing from a celebrated musical lineage, his organic blend of infectious grooves and effortless falsetto singing captivates millions of young listeners. '
        'With slick vocal delivery and inventive musicality, he has swiftly become one of the most exciting young creative forces in South Indian music. '
        'He represents the vanguard of independent music making unprecedented waves in mainstream Indian popular culture.',
    'yuvan shankar raja':
        'Yuvan Shankar Raja, fondly hailed as the \'King of BGM\' and youth icon, is a versatile Indian composer and singer in Tamil cinema. '
        'The younger son of maestro Ilaiyaraaja, Yuvan carved his own distinct legacy by pioneering hip-hop, electronic synth-pop, and melancholic lo-fi vibes in South Indian film music. '
        'Soundtracks like 7G Rainbow Colony, Pudhupettai, Paiyaa, Mankatha, and Super Deluxe established his reputation for unforgettable background scores and moody, heartfelt tracks. '
        'A multi-instrumentalist with an instinct for evocative melodies, his music captures youthful longing and urban angst like few others. '
        'Yuvan\'s raw vocal delivery and atmospheric soundscapes enjoy a passionate, generational cult following. '
        'He stands as one of Tamil cinema\'s most beloved and inventive musical mavericks.',
    'santhosh narayanan':
        'Santhosh Narayanan is an innovative Indian music composer and producer celebrated for his raw, boundary-pushing acoustic sound, rustic folk arrangements, and avant-garde cinematic storytelling. '
        'Debuting with Attakathi (2012), he quickly established a reputation for spotlighting indigenous folk percussion, raw street instruments, and independent voices. '
        'His standout soundtracks include Pizza, Madras, Kabali, Kaala, Karnan, Sarpatta Parambarai, and the pan-Indian sci-fi epic Kalki 2898 AD. '
        'Santhosh deftly blends traditional Gaana and Oppari roots with international jazz, blues, and symphonic brass. '
        'His unconventional arrangements and organic sound engineering have earned him widespread critical and commercial acclaim. '
        'He is recognized as one of the most creatively fearless composers in modern Indian cinema.',
    'harris jayaraj':
        'Harris Jayaraj is a celebrated Indian music director renowned for his cosmopolitan pop aesthetics, breezy romantic melodies, and innovative synth programming in Tamil and Telugu cinema. '
        'Debuting with Minnale (2001), he delivered an instant golden streak of iconic albums including Kaakha Kaakha, Ghajini, Anniyan, Vettaiyaadu Vilaiyaadu, and Orange. '
        'Known for blending slick Western pop rhythms, acoustic nylon guitars, and jazz chords with catchy vocalise hooks, his sound became the quintessential romance soundtrack of the 2000s. '
        'He has won multiple Filmfare Awards South and state film accolades for his trendsetting musical production. '
        'Harris\'s ability to craft timeless, headphone-friendly audio mixes commands enduring nostalgic devotion. '
        'His melodies remain evergreen fixtures on streaming playlists across South India.',
    'ilaiyaraaja':
        'Ilaiyaraaja, venerated as \'Isaignani\' (the Musical Genius), is an Indian composer, orchestrator, and multi-instrumentalist who stands among the greatest musical minds in history. '
        'Having composed over 7,000 songs and scored more than 1,000 films across five decades, he pioneered the synthesis of authentic Tamil folk idioms with Western classical counterpoint. '
        'Recipient of five National Film Awards and the Padma Vibhushan, he was the first Asian composer to write a full symphony for the Royal Philharmonic Orchestra. '
        'His breathtaking scores for Nayakan, Thalapathi, Geethanjali, and Sagarasangamam are studied globally for their harmonic genius. '
        'His music defined the emotional fabric of multiple generations across South India. '
        'He remains a monumental figure whose orchestral mastery is celebrated worldwide.',
    'gv prakash kumar':
        'G.V. Prakash Kumar is an acclaimed Indian music composer, playback singer, and actor in Tamil cinema. '
        'Making his debut at age 19 with Veyil, he established a stellar career with critical masterworks such as Aadukalam, Mayakkam Enna, Asuran, and Soorarai Pottru, for which he won the National Film Award for Best Music Direction. '
        'Nephew to A.R. Rahman, G.V. Prakash has developed his own unmistakable musical vocabulary characterized by acoustic warmth, earthy rural folk, and infectious urban hooks. '
        'As a playback singer and actor, he maintains a high-energy creative output with chartbusters across Tamil and Telugu. '
        'He continues to be one of the most prolific and creatively versatile artists in South India.',

    // --- Hindi / Bollywood ---
    'arijit singh':
        'Arijit Singh is a multiple National Film Award-winning Indian playback singer and composer, widely celebrated as the definitive voice of modern Indian romance and soul. '
        'Following his epochal breakthrough with \'Tum Hi Ho\' from Aashiqui 2, his raw, melancholic, and deeply resonant timbre came to dominate Indian cinema and digital streaming charts. '
        'Trained rigorously in Indian classical music, he effortlessly infuses complex vocal nuances into contemporary pop, indie folk, and rock ballads. '
        'He is consistently ranked as the most-streamed Indian artist globally, with an unprecedented catalog of beloved songs across Hindi and Bengali. '
        'Renowned for his grounded humility and captivating live acoustic performances, Arijit continues to inspire a new generation of musicians. '
        'His emotive vocal artistry has defined the soundtrack of contemporary Indian youth.',
    'pritam':
        'Pritam Chakraborty is a prolific Bollywood composer and music producer responsible for defining the commercial sound of modern Indian cinema for over two decades. '
        'With an unmatched track record of chart-topping soundtracks from Dhoom, Jab We Met, Love Aaj Kal, Yeh Jawaani Hai Deewani, Ae Dil Hai Mushkil, to Brahmāstra, he is the undisputed architect of Bollywood pop. '
        'Pritam\'s sound is characterized by infectious melodic hooks, driving pop-rock percussion, and soulful Sufi influences. '
        'Winner of multiple National Film Awards and Filmfare trophies, his studio JAM8 has mentored numerous rising singers and composers. '
        'His songs are permanent fixtures in Indian celebrations, parties, and romantic playlists.',
    'shreya ghoshal':
        'Shreya Ghoshal is a five-time National Film Award-winning playback singer universally hailed as the melody queen of modern Indian music. '
        'Making an extraordinary debut at age sixteen in Sanjay Leela Bhansali\'s Devdas, she immediately captured nationwide acclaim with her sweet, pristine vocal timbre. '
        'Her prolific repertoire spans more than twenty languages, delivering iconic chartbusters in Hindi, Telugu, Tamil, Bengali, and Malayalam. '
        'With classical training and effortless mastery across semi-classical, romantic, and pop genres, Shreya is the definitive female playback voice of the 21st century. '
        'Recipient of numerous Filmfare trophies, she holds the distinction of being honored with an official \'Shreya Ghoshal Day\' in the United States. '
        'Her expressive emotional nuance and pitch perfection continue to mesmerize millions of listeners worldwide.',
    'badshah':
        'Badshah is a prominent Indian rapper, singer, and music producer who revolutionized modern Desi hip-hop and commercial club culture. '
        'Breaking streaming records with global party anthems like \'DJ Waley Babu\', \'Genda Phool\', \'Jugnu\', and \'Kala Chashma\', his high-energy hooks and urban beats define contemporary Indian party music. '
        'Recognized on international charts and collaborating with global stars like J Balvin, Badshah bridged Indian rap with mainstream pop. '
        'With billions of streams across YouTube and Spotify, he has shaped contemporary commercial dance music. '
        'His infectious rhythmic production and sharp lyrical punchlines remain unmatched in Indian pop.',
    'atif aslam':
        'Atif Aslam is a celebrated Pakistani playback singer and songwriter whose distinctive vocal belt, raspy romantic timbre, and Sufi rock ballads captivated audiences across South Asia. '
        'Emerging with the rock band Jal and his breakthrough hit \'Aadat\', he transitioned into Bollywood with an extraordinary streak of romantic anthems including \'Woh Lamhe\', \'Tere Bin\', \'Pehli Nazar Mein\', and \'Dil Diyan Gallan\'. '
        'His effortless vocal projection and emotive passion made him one of the most beloved romantic voices in modern cinema. '
        'Honored with the Tamgha-e-Imtiaz, Atif has performed in sold-out arenas across the globe. '
        'His timeless ballads continue to command massive international streaming numbers.',
    'sonu nigam':
        'Sonu Nigam is revered as one of the finest and most versatile vocalists in Indian musical history, celebrated as the \'Lord of Chords\'. '
        'With an illustrious career spanning three decades, multiple National Film Awards, and the prestigious Padma Shri, he has recorded thousands of songs in over a dozen languages. '
        'His mastery across romantic melodies, patriotic anthems, ghazals, and bhajans in films like Kal Ho Naa Ho, Border, and Deewana is peerless. '
        'Trained in the classical tradition, his extraordinary pitch perfection, breath control, and expressive range remain a benchmark for playback singing. '
        'He is globally respected as a living legend of Indian vocal arts.',
    'shankar mahadevan':
        'Shankar Mahadevan is a four-time National Film Award-winning singer, composer, and part of the iconic Shankar-Ehsaan-Loy trio. '
        'Shooting to fame with the groundbreaking non-stop track \'Breathless\', he possesses a virtuoso voice capable of bridging classical Hindustani and Carnatic music with modern jazz and pop. '
        'As a composer, he has scored landmark films including Dil Chahta Hai, Kal Ho Naa Ho, Taare Zameen Par, and Bhaag Milkha Bhaag. '
        'Honored with the Padma Shri, his energetic vocal presence and classical improvisations inspire musicians worldwide. '
        'He stands as a monumental bridge between classical traditions and modern Indian film music.',
    'armaan malik':
        'Armaan Malik is an acclaimed Indian singer, songwriter, and actor known as the \'Prince of Romance\' for his velvety pop ballads and crossover singles. '
        'Trained in Indian classical music, he quickly rose to stardom with romantic hits like \'Bol Do Na Zara\', \'Main Hoon Hero Tera\', and \'Butta Bomma\' in Telugu. '
        'The youngest Indian singer to win two MTV Europe Music Awards, Armaan has successfully crossed over into English pop with singles like \'Control\' and \'You\'. '
        'His clean vocal tone, modern phrasing, and multilingual versatility have earned him millions of passionate fans globally. '
        'He represents the forefront of modern Indian artists achieving genuine international recognition.',
    'neha kakkar':
        'Neha Kakkar is one of India\'s most popular playback singers, renowned for her peppy dance anthems, infectious energy, and party hits. '
        'Rising from Indian Idol to become a streaming powerhouse, she has delivered chartbusters like \'Aankh Marey\', \'Dilbar\', \'Garmi\', and \'Kar Gayi Chull\'. '
        'Her vibrant personality and distinctive vocal texture have made her one of the most followed Indian musicians on social media. '
        'Winner of numerous music awards, she has dominated Bollywood party tracks for nearly a decade. '
        'Her high-energy club numbers are staples across celebrations and weddings worldwide.',
    'jubin nautiyal':
        'Jubin Nautiyal is an Indian playback singer celebrated for his rich, soothing voice and soul-stirring romantic and devotional ballads. '
        'His breakout hits including \'Raataan Lambiyan\' from Shershaah, \'Lut Gaye\', \'Tum Hi Aana\', and \'Kuch Toh Bata Zindagi\' achieved record-breaking digital streaming numbers. '
        'Trained in Western classical guitar and Indian classical vocals, Jubin brings an acoustic warmth and quiet emotional intimacy to his tracks. '
        'Winner of the IIFA Award for Best Male Playback Singer, he is a leading voice in modern Bollywood romance. '
        'His comforting melodies remain enduring favorites across global streaming audiences.',

    // --- Punjabi ---
    'diljit dosanjh':
        'Diljit Dosanjh is an international superstar, singer, and actor who brought Punjabi music to the global center stage. '
        'Making history as the first Punjabi artist to perform at Coachella, Diljit\'s magnetic stage presence and vocal power have garnered an enormous worldwide fanbase. '
        'His blockbuster albums G.O.A.T., MoonChild Era, and Ghost blend traditional Punjabi tumbi and dhol rhythms with modern trap and R&B production. '
        'Alongside his record-breaking musical career, he has earned critical acclaim as a leading actor in Punjabi and Hindi cinema. '
        'His sold-out global arena tours and chart-topping singles continue to break cultural and linguistic barriers. '
        'He is universally recognized as the foremost ambassador of modern Punjabi pop culture.',
    'karan aujla':
        'Karan Aujla is a leading singer, songwriter, and rapper in contemporary Punjabi music, renowned for his razor-sharp lyricism, hard-hitting trap beats, and viral international hits. '
        'With chart-topping albums like Bacthatha and Making Memories, he became the first Punjabi artist to win a Juno Award in Canada. '
        'His viral mega-hits including \'Tauba Tauba\' and \'Softly\' dominated global streaming charts and social media reels. '
        'Aujla\'s signature blend of folk Punjabi cadence with Western hip-hop production has redefined commercial Punjabi music. '
        'He stands at the pinnacle of the modern Punjabi music renaissance.',
    'sidhu moose wala':
        'Sidhu Moose Wala was a legendary Punjabi rapper, singer, and songwriter who became a global icon for modern Punjabi music and street poetry. '
        'Known for his fearless, raw lyricism, hard-hitting boom-bap hip-hop beats, and pride in rural roots, he revolutionized the Punjabi music industry with albums like PBX 1 and Moosetape. '
        'His profound influence transcended borders, charting on the Billboard Canadian Albums and UK Asian Music charts. '
        'Sidhu gave voice to youth culture, authenticity, and self-determination with an unforgettable vocal presence. '
        'His timeless tracks continue to resonate as an iconic cultural legacy worldwide.',
    'ap dhillon':
        'AP Dhillon is an Indo-Canadian singer, rapper, and record producer whose fusion of Punjabi vocals with 80s synthwave, trap, and R&B sparked a global cultural phenomenon. '
        'Alongside his Run-Up Records team, his era-defining tracks like \'Brown Munde\', \'Excuses\', \'Insane\', and \'Dil Nu\' achieved hundreds of millions of streams. '
        'Selling out arenas in North America, the UK, and India, Dhillon created a sleek, aesthetic sound that bridged South Asian youth culture with Western diaspora music. '
        'His genre-bending production continues to inspire contemporary urban music.',
    'guru randhawa':
        'Guru Randhawa is a high-profile Indian singer, songwriter, and music composer known for his infectious, upbeat Punjabi pop anthems. '
        'His chartbusters like \'High Rated Gabru\', \'Lahore\', \'Suit Suit\', and \'Ban Ja Rani\' made him one of the most viewed Indian artists on YouTube. '
        'He was among the first Indian artists to collaborate with international stars like Pitbull on \'Slowly Slowly\'. '
        'With catchy hooks, energetic dance beats, and a charming vocal style, Guru remains a dominant force in modern Indian pop.',

    // --- Malayalam ---
    'sushin shyam':
        'Sushin Shyam is an award-winning Indian music composer, producer, and instrumentalist who spearheads the contemporary sound revolution in Malayalam cinema. '
        'Starting his career as a keyboardist and bassist with the thrash metal band The Down Troddence, he brought an innovative indie sensibility to film music. '
        'His distinctive scores for Kumbalangi Nights, Minnal Murali, Romancham, Manjummel Boys, and Aavesham captivated audiences across India. '
        'Winning the Kerala State Film Award for Best Music Director, Sushin combines electronic synthwave, acoustic folk, and atmospheric ambient textures. '
        'His infectious hooks and minimalist storytelling have made him one of the most exciting young composers in Indian cinema. '
        'He continues to set new sonic standards with every release.',
    'kj yesudas':
        'Kattassery Joseph Yesudas is revered as the \'Celestial Singer\' (Gandharva Gaayakan), standing as a monumental institution of Indian classical and playback music. '
        'In a peerless career spanning over six decades, he has recorded more than 50,000 songs across Malayalam, Tamil, Telugu, Hindi, Kannada, and other languages. '
        'Recipient of a record eight National Film Awards, the Padma Shri, Padma Bhushan, and Padma Vibhushan, his voice possesses divine clarity, classical perfection, and emotional depth. '
        'His timeless film recordings and devotional hymns are woven into the cultural identity of South India. '
        'He is universally honored as one of the greatest singers in human history.',
    'hesham abdul wahab':
        'Hesham Abdul Wahab is an Indian music director, music producer, and playback singer who achieved widespread acclaim with the superhit Malayalam film Hridayam. '
        'Trained in audio engineering and Middle Eastern music, he blends acoustic guitars, violins, and choral melodies with modern indie pop. '
        'Winning the Kerala State Film Award for Best Music Director, Hesham expanded into Telugu cinema with celebrated scores like Kushi and Hi Nanna. '
        'His deeply romantic melodies and lush organic orchestration have made him one of the most sought-after composers in contemporary South Indian cinema.',

    // --- Global / English ---
    'the weeknd':
        'Abel Tesfaye, known globally as The Weeknd, is a Canadian singer, songwriter, and record producer celebrated for his genre-defining dark R&B, synth-pop, and cinematic concept albums. '
        'Rising to fame with his enigmatic mixtapes Trilogy, he achieved global megastardom with historic chartbusters like \'Can\'t Feel My Face\', \'Starboy\', and \'Blinding Lights\'. '
        'His magnum opus album After Hours broke all-time streaming records, with \'Blinding Lights\' becoming the number-one Billboard Hot 100 song of all time. '
        'Trained in the falsetto tradition of pop royalty, his music explores themes of nocturnal escapism and emotional vulnerability. '
        'Winner of multiple Grammy Awards and headliner of the Super Bowl LV halftime show, he is one of the best-selling artists in music history. '
        'His visionary sound continues to shape the vanguard of global pop music.',
    'taylor swift':
        'Taylor Swift is a global cultural phenomenon and 14-time Grammy-winning singer-songwriter celebrated for her narrative songwriting, versatile genre shifts, and unprecedented industry impact. '
        'Evolving from a country prodigy to an international pop titan, she has released historic albums including 1989, Folklore, Midnights, and The Tortoise Poets Department. '
        'Her record-breaking Eras Tour became the highest-grossing concert tour in history, redefining live music performance on a stadium scale. '
        'With an exceptional gift for lyricism and autobiographical storytelling, Taylor has connected with millions of devoted fans across multiple generations. '
        'She is the first artist in history to win the Grammy for Album of the Year four times. '
        'Her enduring artistic autonomy and musical catalog stand as a towering achievement in modern popular culture.',
    'ed sheeran':
        'Ed Sheeran is an acclaimed English singer-songwriter celebrated for his soulful acoustic ballads, loop-pedal live performances, and record-shattering global pop anthems. '
        'Rising from humble open mic circuits to selling out world stadiums, albums like +, x, ÷, and = produced iconic global hits such as \'Shape of You\', \'Perfect\', and \'Thinking Out Loud\'. '
        'Winner of four Grammy Awards and numerous Brit Awards, he is one of the world\'s best-selling music artists. '
        'His relatable songwriting, melodic craftsmanship, and effortless blending of pop, folk, and hip-hop resonate with diverse audiences worldwide. '
        'He remains one of the most prolific and beloved songwriters of the modern era.',
    'dua lipa':
        'Dua Lipa is an English and Albanian singer-songwriter renowned for her distinctive mezzo-soprano vocal tone and disco-infused dance-pop anthems. '
        'After garnering critical praise with her self-titled debut, her blockbuster sophomore album Future Nostalgia became an international sensation with global hits like \'Don\'t Start Now\' and \'Levitating\'. '
        'Winner of three Grammy Awards and seven Brit Awards, she revitalized modern pop with 80s nostalgia, funk basslines, and chic visual aesthetics. '
        'Her commanding stage presence and chart-topping collaborations have solidified her standing as a global pop icon. '
        'She continues to dominate international radio and streaming charts.',
    'billie eilish':
        'Billie Eilish is an American singer-songwriter who revolutionized modern pop music with her intimate whisper-vocals, dark minimalist production, and deeply introspective lyricism. '
        'Collaborating with her brother Finneas, her debut album When We All Fall Asleep, Where Do We Go? swept the top four Grammy categories in a historic single night. '
        'She followed with critical masterworks Happier Than Ever and Hit Me Hard and Soft, alongside winning two Academy Awards for Best Original Song. '
        'Her fearless sonic experimentation and atmospheric arrangements have inspired an entire generation of indie and pop artists. '
        'She stands as one of the most authentic and influential creative voices in contemporary music.',
    'bruno mars':
        'Bruno Mars is an American singer, songwriter, multi-instrumentalist, and showman celebrated for his retro funk, soulful pop ballads, and magnetic stage presence. '
        'With a glittering career that includes 15 Grammy Awards and multiple Billboard number-one singles like \'Just the Way You Are\', \'Locked Out of Heaven\', \'Uptown Funk\', and \'24K Magic\', he is a master of throwback R&B and showmanship. '
        'His duo project Silk Sonic alongside Anderson .Paak earned widespread critical acclaim for reviving vintage 70s soul. '
        'Known for electrifying live performances with The Hooligans, Mars effortlessly channels the spirit of legendary musical entertainers. '
        'He remains one of the most complete and versatile musical artists of his generation.',
  };

  /// Curated filmographies and iconic album catalogs for legendary music directors, composers, and singers.
  /// Unlocks hundreds of film soundtrack songs that plain keyword searches miss due to singer/composer metadata splitting.
  static const Map<String, List<String>> _artistFilmographies = {
    'devi sri prasad': [
      'Pushpa 2 The Rule',
      'Pushpa The Rise',
      'Rangasthalam',
      'Mirchi',
      'Gabbar Singh',
      'Arya',
      'Arya 2',
      'Jalsa',
      'Attarintiki Daredi',
      'Varsham',
      'Bommarillu',
      'Nannaku Prematho',
      'Waltair Veerayya',
      'Uppena',
      'Srimanthudu',
      'Bharat Ane Nenu',
      'Sarileru Neekevvaru',
      '100% Love',
      'Ready',
      'Julayi',
      'Venky',
      'Anandam',
      'Manmadhudu',
      'Sontham',
      'Shankar Dada MBBS',
      'Iddarammayilatho',
      'Yevadu',
      'Kumari 21F',
      'F2',
      'Legend',
      'Kanthaswamy',
      'Singam',
      'Aaru',
      'Sachien',
      'Pournami',
      'Bunny',
      'Badri',
      'King',
      'Tulasi',
      'Bhadra',
      'Nuvvostanante Nenoddantana',
      'Mass',
    ],
    'ar rahman': [
      'Roja',
      'Bombay',
      'Dil Se',
      'Rockstar',
      'Raanjhanaa',
      'Slumdog Millionaire',
      'Lagaan',
      'Swades',
      'Taal',
      'Guru',
      'Rang De Basanti',
      'Highway',
      'Tamasha',
      'Ponniyin Selvan',
      'Sivaji',
      'Enthiran',
      'OK Kanmani',
      'Vinnaithaandi Varuvaayaa',
      'Ye Maaya Chesave',
      'Robo',
      'Jodhaa Akbar',
      'Delhi-6',
      'Ghajini',
      'Saathiya',
      'Yuva',
      'Raavanan',
      'I',
      '24',
      'Mersal',
      'Bigil',
      'Chekka Chivantha Vaanam',
      'Maryan',
      'Kadal',
      'Ayitha Ezhuthu',
    ],
    'anirudh ravichander': [
      '3',
      'VIP',
      'Kaththi',
      'Petta',
      'Master',
      'Vikram',
      'Jailer',
      'Leo',
      'Devara',
      'Jawan',
      'Beast',
      'Doctor',
      'Naanum Rowdy Dhaan',
      'Maari',
      'Remo',
      'Don',
      'Thiruchitrambalam',
      'Indian 2',
      'Vettaiyan',
      'Darbar',
      'Kolamaavu Kokila',
      'Kaathuvaakula Rendu Kaadhal',
      'Ethir Neechal',
      'Vanakkam Chennai',
    ],
    'thaman s': [
      'Ala Vaikunthapurramuloo',
      'Sarrainodu',
      'Race Gurram',
      'Kick',
      'Dookudu',
      'Businessman',
      'Aagadu',
      'Bheeshma',
      'Krack',
      'Akhanda',
      'Guntur Kaaram',
      'Bhagavanth Kesari',
      'Game Changer',
      'Bro',
      'Varisu',
      'Brindavanam',
      'Aravinda Sametha',
      'Vakeel Saab',
      'Sarkaru Vaari Paata',
      'Godfather',
      'Veera Simha Reddy',
      'Skanda',
      'Disco Raja',
      'Mirapakay',
    ],
    'mm keeravaani': [
      'Baahubali',
      'Baahubali 2',
      'RRR',
      'Magadheera',
      'Eega',
      'Chatrapathi',
      'Simhadri',
      'Student No 1',
      'Annamayya',
      'Sri Ramadasu',
      'Shirdi Sai',
      'Criminal',
      'Kshana Kshanam',
      'Yamadonga',
      'Maryada Ramanna',
      'Allari Bullodu',
      'Subha Sankalpam',
      'Seetharamaiah Gari Manavaralu',
    ],
    'mickey j meyer': [
      'Happy Days',
      'Kotha Bangaru Lokam',
      'Leader',
      'Seethamma Vakitlo Sirimalle Chettu',
      'A Aa',
      'Mukunda',
      'Brahmotsavam',
      'Shatamanam Bhavati',
      'Mahanati',
      'Gaddalakonda Ganesh',
      'Shyam Singha Roy',
      'Mr. Bachchan',
    ],
    'harris jayaraj': [
      'Minnale',
      'Chellamae',
      'Ghajini',
      'Anniyan',
      'Vettaiyaadu Vilaiyaadu',
      'Vaaranam Aayiram',
      'Ayan',
      'Aadhavan',
      '7aum Arivu',
      'Thuppakki',
      'Yennai Arindhaal',
      'Orange',
      'Vasu',
      'Ko',
      'Nanban',
      'Maattrraan',
      'Kaakha Kaakha',
    ],
    'yuvan shankar raja': [
      'Pudhupettai',
      '7G Rainbow Colony',
      'Mankatha',
      'Paiyaa',
      'Biriyani',
      'Maanaadu',
      'GOAT',
      'Aaranya Kaandam',
      'Raam',
      'Kaadhal Kondein',
      'Billa',
      'Paruthiveeran',
      'Thulluvadho Ilamai',
      'Oye',
      'Panjaa',
      'Aadavari Matalaku Arthale Verule',
    ],
    'ilaiyaraaja': [
      'Geethanjali',
      'Sagarasangamam',
      'Swathimuthyam',
      'Rudraveena',
      'Nayakan',
      'Thalapathi',
      'Anjali',
      'Sindhu Bhairavi',
      'Moondram Pirai',
      'Johnny',
      'Payanangal Mudivadhillai',
      'Shiva',
      'Abhinandana',
      'Jagadeka Veerudu Athiloka Sundari',
      'Bobbili Raja',
      'Chanti',
      'Guna',
      'Hey Ram',
    ],
    'sp balasubrahmanyam': [
      'Sankarabharanam',
      'Sagara Sangamam',
      'Rudraveena',
      'Swathi Muthyam',
      'Dalapathi',
      'Roja',
      'Annamayya',
      'Prema',
      'Padamati Sandhya Ragam',
      'Sirivennela',
      'Geethanjali',
      'Shiva',
      'Jagadeka Veerudu',
      'Aditya 369',
      'Gharana Mogudu',
      'Major Chandrakanth',
    ],
    'ks chithra': [
      'Sindhu Bhairavi',
      'Geethanjali',
      'Roja',
      'Bombay',
      'Annamayya',
      'Matrudevobhava',
      'Ninne Pelladata',
      'Choodalani Vundi',
      'Murari',
      'Nuvve Kavali',
      'Santosham',
      'Varsham',
      'Autograph',
    ],
    'sid sriram': [
      'Geetha Govindam',
      'Ala Vaikunthapurramuloo',
      'Pushpa',
      'Majili',
      'Dear Comrade',
      'Taxiwaala',
      'Husharu',
      'Rang De',
      'Uppena',
      'Sarkaru Vaari Paata',
      'Kushi',
      'Hi Nanna',
      'Enai Noki Paayum Thota',
      'Pyaar Prema Kaadhal',
    ],
    'arijit singh': [
      'Aashiqui 2',
      'Yeh Jawaani Hai Deewani',
      'Dilwale',
      'Ae Dil Hai Mushkil',
      'Half Girlfriend',
      'Raabta',
      'Kalank',
      'Kabir Singh',
      'Brahmastra',
      'Jawan',
      'Pathaan',
      'Dunki',
      'Animal',
      'Chhichhore',
      'Kedarnath',
      'Tamasha',
      'Roy',
    ],
    'shreya ghoshal': [
      'Devdas',
      'Jism',
      'Guru',
      'Jab We Met',
      'Om Shanti Om',
      'Rab Ne Bana Di Jodi',
      'Singh Is Kinng',
      'Bajirao Mastani',
      'Padmaavat',
      'Kalank',
      'Rocky Aur Rani Kii Prem Kahaani',
      'Animal',
      'Pushpa 2',
    ],
    'pritam': [
      'Yeh Jawaani Hai Deewani',
      'Ae Dil Hai Mushkil',
      'Brahmastra',
      'Tu Jhoothi Main Makkaar',
      'Dhoom 2',
      'Dhoom 3',
      'Jab We Met',
      'Cocktail',
      'Barfi',
      'Love Aaj Kal',
      'Race',
      'Race 2',
      'Bajrangi Bhaijaan',
      'Ludo',
      'Dangal',
    ],
    'sonu nigam': [
      'Kal Ho Naa Ho',
      'Border',
      'Kabhi Khushi Kabhie Gham',
      'Saathiya',
      'Main Hoon Na',
      'Fanaa',
      'Veer-Zaara',
      'Om Shanti Om',
      'Agneepath',
      'Deewana',
      'Parineeta',
    ],
    'atif aslam': [
      'Aadat',
      'Tajdar E Haram',
      'Woh Lamhe',
      'Tere Bin',
      'Pehli Nazar Mein',
      'Tu Jaane Na',
      'Jeene Laga Hoon',
      'Tera Hone Laga Hoon',
      'Dil Diyan Gallan',
      'Dekhte Dekhte',
      'Be Intehaan',
    ],
    'diljit dosanjh': [
      'G.O.A.T.',
      'MoonChild Era',
      'Ghost',
      'Lover',
      'Proper Patola',
      'Do You Know',
      'Born to Shine',
      'Chamkila',
      'Udta Punjab',
      'Honsla Rakh',
      'Jatt & Juliet 3',
    ],
    'karan aujla': [
      'Making Memories',
      'Street Dreams',
      'Four Me',
      'Tauba Tauba',
      'Softly',
      'Winning Speech',
      'Admirin You',
      'White Brown Black',
      'On Top',
      'Chithiyaan',
    ],
    'sidhu moose wala': [
      'Moosetape',
      'PBX 1',
      'No Name',
      'The Last Ride',
      '295',
      'So High',
      'Same Beef',
      'Levels',
      'Never Fold',
      'Bambiha Bole',
    ],
    'taylor swift': [
      '1989',
      'Red',
      'Fearless',
      'Lover',
      'Folklore',
      'Evermore',
      'Midnights',
      'The Tortured Poets Department',
      'Reputation',
      'Speak Now',
    ],
    'ed sheeran': [
      'Divide',
      'Multiply',
      'Equals',
      'Subtract',
      'Plus',
      'No.6 Collaborations Project',
      'Autumn Variations',
    ],
    'the weeknd': [
      'After Hours',
      'Dawn FM',
      'Starboy',
      'Beauty Behind The Madness',
      'House of Balloons',
      'Trilogy',
      'My Dear Melancholy',
    ],
    'justin bieber': [
      'Purpose',
      'Justice',
      'Changes',
      'Believe',
      'My World 2.0',
      'Journals',
      'Under the Mistletoe',
    ],
    'sushin shyam': [
      'Aavesham',
      'Manjummel Boys',
      'Romancham',
      'Kumbalangi Nights',
      'Bheeshma Parvam',
      'Minnal Murali',
      'Virus',
      'Varathan',
    ],
    'ravi basrur': [
      'KGF Chapter 1',
      'KGF Chapter 2',
      'Salaar',
      'Kabzaa',
      'Antim',
      'Ugramm',
      'Bharaate',
    ],
  };

  /// Returns language-tailored discography search queries for an artist across paginated tiers.
  List<String> getArtistDiscographyQueries(String artistName, {int page = 1}) {
    final clean = artistName.trim();
    if (clean.isEmpty) return [];

    final matched = findArtist(clean);
    final canonicalName = matched?.name ?? clean;
    final lang = matched?.language.toLowerCase() ?? 'telugu';
    final norm = PlaylistArtistFilter.normalize(canonicalName);

    if (page == 1) {
      // Tier 1 (Immediate 150-250+ songs on first load): Core Vocal, Melodies, Mass Hits, Dance, Blockbusters & Regional Classics
      if (lang == 'telugu') {
        return [
          canonicalName,
          '$canonicalName melody hits',
          '$canonicalName mass hits',
          '$canonicalName dance hits',
          '$canonicalName classics',
          '$canonicalName Tollywood',
          '$canonicalName golden hits',
          '$canonicalName item songs',
          '$canonicalName party songs',
          '$canonicalName blockbuster',
        ];
      } else if (lang == 'tamil') {
        return [
          canonicalName,
          '$canonicalName Tamil hits',
          '$canonicalName melody',
          '$canonicalName mass hits',
          '$canonicalName dance hits',
          '$canonicalName Kollywood',
          '$canonicalName classics',
          '$canonicalName golden hits',
          '$canonicalName blockbuster',
        ];
      } else if (lang == 'hindi') {
        return [
          canonicalName,
          '$canonicalName Bollywood hits',
          '$canonicalName romantic hits',
          '$canonicalName classics',
          '$canonicalName melody',
          '$canonicalName dance hits',
          '$canonicalName unplugged',
          '$canonicalName party hits',
          '$canonicalName golden hits',
        ];
      } else if (lang == 'punjabi') {
        return [
          canonicalName,
          '$canonicalName Punjabi hits',
          '$canonicalName bhangra',
          '$canonicalName dance hits',
          '$canonicalName beats',
          '$canonicalName songs',
          '$canonicalName all songs',
        ];
      } else if (lang == 'english' || lang == 'global') {
        return [
          canonicalName,
          '$canonicalName greatest hits',
          '$canonicalName billboard',
          '$canonicalName live',
          '$canonicalName acoustic',
          '$canonicalName dance',
          '$canonicalName remix',
          '$canonicalName songs',
        ];
      } else {
        return [
          canonicalName,
          '$canonicalName $lang hits',
          '$canonicalName melody',
          '$canonicalName dance hits',
          '$canonicalName classics',
          '$canonicalName golden hits',
          '$canonicalName songs',
        ];
      }
    }

    // Pages 2+: If artist has a curated filmography/album catalog, paginate through their real albums
    final filmography = _artistFilmographies[norm];
    if (filmography != null && filmography.isNotEmpty) {
      const albumsPerPage = 6;
      final albumStartIndex = (page - 2) * albumsPerPage;
      if (albumStartIndex < filmography.length) {
        final albumEndIndex = (albumStartIndex + albumsPerPage).clamp(
          0,
          filmography.length,
        );
        final pageAlbums = filmography.sublist(albumStartIndex, albumEndIndex);
        return pageAlbums.map((film) => '$canonicalName $film').toList();
      }
    }

    // Fallback/Era/Deep-Catalog queries for later pages or artists without filmography
    return _getDeepEraQueries(canonicalName, lang, page);
  }

  /// Generates non-overlapping era, stylistic, and deep archive queries for infinite pagination
  List<String> _getDeepEraQueries(String clean, String lang, int page) {
    if (page == 2) {
      if (lang == 'telugu') {
        return [
          '$clean 2024 hits',
          '$clean 2023 hits',
          '$clean 2022',
          '$clean 2021',
          '$clean 2020',
          '$clean mass songs',
        ];
      } else if (lang == 'tamil') {
        return [
          '$clean 2024 hits',
          '$clean 2023 hits',
          '$clean 2022',
          '$clean 2021',
          '$clean 2020',
          '$clean kuthu songs',
        ];
      } else if (lang == 'hindi') {
        return [
          '$clean 2024 hits',
          '$clean 2023 hits',
          '$clean 2022',
          '$clean 2021',
          '$clean 2020',
          '$clean romantic songs',
        ];
      } else {
        return [
          '$clean 2024',
          '$clean 2023',
          '$clean 2022',
          '$clean 2021',
          '$clean 2020',
          '$clean greatest hits',
        ];
      }
    } else if (page == 3) {
      return [
        '$clean 2019',
        '$clean 2018',
        '$clean 2017',
        '$clean 2016',
        '$clean 2015',
        '$clean melody hits',
      ];
    } else if (page == 4) {
      return [
        '$clean 2014',
        '$clean 2013',
        '$clean 2012',
        '$clean 2011',
        '$clean 2010',
        '$clean super hits',
      ];
    } else if (page == 5) {
      return [
        '$clean 2009',
        '$clean 2008',
        '$clean 2007',
        '$clean 2006',
        '$clean 2005',
        '$clean golden hits',
      ];
    } else if (page == 6) {
      return [
        '$clean 2004',
        '$clean 2003',
        '$clean 2002',
        '$clean 2001',
        '$clean 2000',
        '$clean evergreen',
      ];
    } else if (page == 7) {
      return [
        '$clean 90s',
        '$clean classic hits',
        '$clean original soundtrack',
        '$clean live in concert',
        '$clean acoustic',
      ];
    } else {
      final decade = 2025 - ((page - 7) * 3);
      return [
        '$clean $decade hits',
        '$clean $lang songs $page',
        '$clean all songs $page',
        '$clean album cuts $page',
      ];
    }
  }
}
