import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/preferences_service.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../widgets/auth/google_logo.dart';
import '../widgets/auth/google_profile_header_button.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/profile_avatar_helper.dart';
import 'dilse_capsule_screen.dart';
import 'artist_profile_screen.dart';
import 'custom_playlist_screen.dart';
import '../layouts/desktop_layout_state.dart';

/// Spotify-grade Profile & Activity Screen.
///
/// Features:
/// 1. Dynamic Ambient Hero Header with large Circular Avatar, display name, and metadata subtitle.
/// 2. Interactive DilSe Capsule Glowing Hero Banner & Edit Profile button.
/// 3. Responsive 4-Column / 2-Row Metrics Cards (Total Plays, Liked Songs, Offline Cache, Top Artist).
/// 4. Spotify-style Top Streamed Artists Circular Avatars carousel with rank badges and tap-to-profile.
/// 5. Spotify-style Top Tracks this month list with rank numbers, album art, play count, like toggle, and Play All / Shuffle.
/// 6. Public Playlists / Your Playlists card row with cover art and tap-to-playlist.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showAllTopTracks = false;

  void _showAvatarOptionsSheet(BuildContext context, PreferencesService prefs) {
    HapticFeedback.lightImpact();
    final customImagePath = prefs.profileImagePath;
    final hasCustomImage = hasProfileImage(customImagePath);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF181824).withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white12),
          ),
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Profile Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.photo_library_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Choose from Gallery',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Select a photo from your device',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final pickedFiles = await FilePicker.pickFiles(
                          type: FileType.image,
                        );
                        if (pickedFiles.isNotEmpty) {
                          final file = pickedFiles.first;
                          final bytes = await file.xFile.readAsBytes();
                          if (bytes.isNotEmpty) {
                            if (bytes.lengthInBytes > 2 * 1024 * 1024) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please select an image smaller than 2MB.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            final ext = file.extension ?? 'png';
                            final base64String = base64Encode(bytes);
                            final dataUri =
                                'data:image/$ext;base64,$base64String';
                            await prefs.setProfileImagePath(dataUri);
                          } else if (file.path != null) {
                            await prefs.setProfileImagePath(file.path!);
                          }
                        }
                      } catch (_) {}
                    },
                  ),
                  if (hasCustomImage) ...[
                    const SizedBox(height: 6),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFA2D48,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFA2D48),
                          size: 22,
                        ),
                      ),
                      title: const Text(
                        'Remove Photo',
                        style: TextStyle(
                          color: Color(0xFFFA2D48),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Revert back to avatar initials',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await prefs.setProfileImagePath(null);
                      },
                    ),
                  ],
                  const SizedBox(height: 6),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Edit Display Name',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Change your profile nickname',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditNameDialog(context, prefs);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEditNameDialog(BuildContext context, PreferencesService prefs) {
    HapticFeedback.lightImpact();
    final controller = TextEditingController(
      text: prefs.userName == 'Friend' ? '' : prefs.userName,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181824).withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Edit Display Name',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This name personalizes your profile, greetings, and mixes.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFFA2D48),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFA2D48),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final name = controller.text.trim();
                      prefs.setUserName(name.isEmpty ? 'Friend' : name);
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService();
    final music = MusicService();

    return AnimatedBuilder(
      animation: Listenable.merge([prefs, music]),
      builder: (context, _) {
        final themeColor = prefs.themeColor;
        final name = prefs.userName;
        final initials = name.isNotEmpty
            ? name.substring(0, 1).toUpperCase()
            : 'F';
        final customImagePath = prefs.profileImagePath;
        final hasCustomImage = hasProfileImage(customImagePath);

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 720;
              final horizontalPadding = isDesktop ? 32.0 : 16.0;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Spotify-style Ambient Header Sliver
                  SliverToBoxAdapter(
                    child: _buildSpotifyHeroHeader(
                      context,
                      prefs: prefs,
                      music: music,
                      name: name,
                      initials: initials,
                      hasCustomImage: hasCustomImage,
                      customImagePath: customImagePath,
                      themeColor: themeColor,
                      isDesktop: isDesktop,
                    ),
                  ),

                  // Main Content Body with Max Width Constraint on wide monitors
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 20.0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Google Account Binding Card (positioned directly beneath profile header)
                          _buildGoogleAccountCard(context),

                          // ✨ DilSe Capsule Hero Banner
                          _buildCapsuleBanner(context),

                          const SizedBox(height: 16),

                          // Quick Action Row (Edit Profile)
                          _buildActionBar(context, prefs: prefs),

                          const SizedBox(height: 24),

                          // Sleek Metrics Row (Total Plays, Liked, Offline, Top Artist)
                          _buildListeningHighlightsGrid(
                            context,
                            prefs: prefs,
                            music: music,
                            isDesktop: isDesktop,
                          ),

                          const SizedBox(height: 32),

                          // Top Streamed Artists (Circular Avatars)
                          if (prefs.getTopPlayedArtists().isNotEmpty) ...[
                            _buildTopArtistsSection(
                              context,
                              prefs: prefs,
                              themeColor: themeColor,
                              isDesktop: isDesktop,
                            ),
                            const SizedBox(height: 36),
                          ],

                          // Top Tracks this month (Most Played Songs)
                          if (prefs.mostPlayedSongs.isNotEmpty) ...[
                            _buildTopTracksSection(
                              context,
                              prefs: prefs,
                              music: music,
                              themeColor: themeColor,
                            ),
                            const SizedBox(height: 36),
                          ],

                          // Public Playlists / Your Playlists
                          if (music.customPlaylists.isNotEmpty) ...[
                            _buildPlaylistsSection(
                              context,
                              music: music,
                              userName: name,
                            ),
                            const SizedBox(height: 36),
                          ],

                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Spotify-grade Dynamic Ambient Hero Header.
  Widget _buildSpotifyHeroHeader(
    BuildContext context, {
    required PreferencesService prefs,
    required MusicService music,
    required String name,
    required String initials,
    required bool hasCustomImage,
    required String? customImagePath,
    required Color themeColor,
    required bool isDesktop,
  }) {
    final publicPlaylistsCount = music.customPlaylists.length;
    final likedSongsCount = music.likedSongs.length;
    final totalPlays = prefs.totalPlays;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF4A1521).withValues(alpha: 0.85),
            const Color(0xFF221118).withValues(alpha: 0.9),
            const Color(0xFF121212),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 32.0 : 20.0,
            12.0,
            isDesktop ? 32.0 : 20.0,
            24.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar Navigation actions (Back + Settings)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Back to Home',
                      onPressed: () =>
                          DesktopLayoutState.setNavTab(DesktopNavTab.home),
                    ),
                  const Expanded(
                    child: Text(
                      'Profile & Activity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),

              // Hero Identity row
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Avatar
                    _buildAvatarWidget(
                      context,
                      prefs: prefs,
                      initials: initials,
                      hasCustomImage: hasCustomImage,
                      customImagePath: customImagePath,
                      themeColor: themeColor,
                      radius: 64,
                    ),
                    const SizedBox(width: 24),

                    // User Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'PROFILE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showEditNameDialog(context, prefs),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                '$publicPlaylistsCount Public ${publicPlaylistsCount == 1 ? "Playlist" : "Playlists"}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                '•',
                                style: TextStyle(color: Colors.white54),
                              ),
                              Text(
                                '$likedSongsCount Liked Songs',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                '•',
                                style: TextStyle(color: Colors.white54),
                              ),
                              Text(
                                '$totalPlays Streams',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Center(
                  child: Column(
                    children: [
                      _buildAvatarWidget(
                        context,
                        prefs: prefs,
                        initials: initials,
                        hasCustomImage: hasCustomImage,
                        customImagePath: customImagePath,
                        themeColor: themeColor,
                        radius: 50,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'PROFILE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _showEditNameDialog(context, prefs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.edit_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$publicPlaylistsCount Playlists • $likedSongsCount Likes • $totalPlays Streams',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Avatar with glowing rim and edit badge.
  Widget _buildAvatarWidget(
    BuildContext context, {
    required PreferencesService prefs,
    required String initials,
    required bool hasCustomImage,
    required String? customImagePath,
    required Color themeColor,
    required double radius,
  }) {
    return GestureDetector(
      onTap: () => _showAvatarOptionsSheet(context, prefs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black26,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: radius,
                backgroundColor: const Color(0xFF282838),
                backgroundImage: getProfileImageProvider(customImagePath),
                child: hasCustomImage
                    ? null
                    : Text(
                        initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: radius * 0.75,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: themeColor,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0B0B0F), width: 2.5),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clean Obsidian Google Account Binding Card.
  Widget _buildGoogleAccountCard(BuildContext context) {
    final auth = AuthService();

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final isConnected = auth.isAuthenticated;
        final displayName =
            auth.userDisplayName ??
            (isConnected ? 'Google Account' : 'Guest Account');
        final email =
            auth.userEmail ??
            (isConnected
                ? 'Account Connected'
                : 'Sign in to backup and sync your library across devices');
        final photoUrl = auth.userPhotoUrl;

        final avatarWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44.0,
              height: 44.0,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isConnected
                      ? const Color(0xFF4285F4).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: isConnected && photoUrl != null && photoUrl.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          photoUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const GoogleLogo(size: 22),
                        ),
                      )
                    : const GoogleLogo(size: 22),
              ),
            ),
            if (isConnected)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12.0,
                  height: 12.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF16161E),
                      width: 2.0,
                    ),
                  ),
                ),
              ),
          ],
        );

        final statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
          decoration: BoxDecoration(
            color: isConnected
                ? const Color(0xFF1DB954).withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: isConnected
                  ? const Color(0xFF1DB954).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              width: 1.0,
            ),
          ),
          child: Text(
            isConnected ? 'Connected' : 'Not Connected',
            style: TextStyle(
              color: isConnected ? const Color(0xFF1DB954) : Colors.white60,
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

        final identityColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8.0),
                statusBadge,
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              email,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

        final actionButton = isConnected
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 10.0,
                  ),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF181824),
                      title: const Text(
                        'Sign Out of Google?',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'Are you sure you want to sign out? Your local playlists and downloads remain intact.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFA2D48),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await auth.signOut();
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 16.0),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600),
                ),
              )
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 10.0,
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  await showGoogleSignInDialog(context);
                },
                icon: const GoogleLogo(size: 16.0),
                label: const Text(
                  'Sign In',
                  style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600),
                ),
              );

        return Container(
          margin: const EdgeInsets.only(bottom: 20.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: const Color(0xFF16161E),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 500;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        avatarWidget,
                        const SizedBox(width: 14.0),
                        Expanded(child: identityColumn),
                      ],
                    ),
                    const SizedBox(height: 14.0),
                    actionButton,
                  ],
                );
              }

              return Row(
                children: [
                  avatarWidget,
                  const SizedBox(width: 16.0),
                  Expanded(child: identityColumn),
                  const SizedBox(width: 16.0),
                  actionButton,
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// ✨ DilSe Capsule Hero Banner
  Widget _buildCapsuleBanner(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DilSeCapsuleScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFE040FB).withValues(alpha: 0.22),
              const Color(0xFF00E5FF).withValues(alpha: 0.14),
              const Color(0xFF1DB954).withValues(alpha: 0.18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE040FB).withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE040FB), Color(0xFF1DB954)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE040FB).withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Your DilSe Capsule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'READY',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap to reveal your private, on-device listening journey',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// Action bar beneath header (Edit profile).
  Widget _buildActionBar(
    BuildContext context, {
    required PreferencesService prefs,
  }) {
    return Row(
      children: [
        // Edit Profile Button
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit Profile'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          onPressed: () => _showEditNameDialog(context, prefs),
        ),
      ],
    );
  }

  /// Clean, Lightweight 4-Column Listening Highlights Grid.
  Widget _buildListeningHighlightsGrid(
    BuildContext context, {
    required PreferencesService prefs,
    required MusicService music,
    required bool isDesktop,
  }) {
    final topArtist = prefs.mostPlayedArtist.isNotEmpty
        ? prefs.mostPlayedArtist
        : 'Discovering';
    final topArtistPlays = prefs.topArtistPlayCount > 0
        ? '${prefs.topArtistPlayCount} plays'
        : 'Most streamed';

    final cards = [
      _buildCompactMetricCard(
        context,
        icon: Icons.play_arrow_rounded,
        iconColor: const Color(0xFFFA2D48),
        title: 'Total Plays',
        value: '${prefs.totalPlays}',
        subtitle: 'Tracks enjoyed',
      ),
      _buildCompactMetricCard(
        context,
        icon: Icons.favorite_rounded,
        iconColor: const Color(0xFFFF4081),
        title: 'Liked Songs',
        value: '${music.likedSongs.length}',
        subtitle: 'Favorites saved',
      ),
      _buildCompactMetricCard(
        context,
        icon: Icons.download_done_rounded,
        iconColor: const Color(0xFF1DB954),
        title: 'Offline Music',
        value: '${music.downloadedSongs.length}',
        subtitle: 'Offline tracks',
      ),
      _buildCompactMetricCard(
        context,
        icon: Icons.person_search_rounded,
        iconColor: const Color(0xFF2196F3),
        title: 'Top Artist',
        value: topArtist,
        subtitle: topArtistPlays,
        onTap: prefs.mostPlayedArtist.isNotEmpty
            ? () {
                if (isDesktop) {
                  DesktopLayoutState.openArtist(prefs.mostPlayedArtist);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistProfileScreen(
                        artistName: prefs.mostPlayedArtist,
                      ),
                    ),
                  );
                }
              }
            : null,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map(
              (c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: c,
                ),
              ),
            )
            .toList(),
      );
    } else {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
        children: cards,
      );
    }
  }

  /// Compact, aesthetic metric card.
  Widget _buildCompactMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: iconColor, size: 15),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Streamed Artists Section (Spotify Circular Avatars).
  Widget _buildTopArtistsSection(
    BuildContext context, {
    required PreferencesService prefs,
    required Color themeColor,
    required bool isDesktop,
  }) {
    final topArtists = prefs.getTopPlayedArtists(limit: 6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top artists this month',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Only visible to you',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Live Sync',
                    style: TextStyle(
                      color: themeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Spotify-style circular cards carousel
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: topArtists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 18),
            itemBuilder: (context, index) {
              final rank = index + 1;
              final entry = topArtists[index];
              final artistName = entry.key;
              final streams = entry.value;
              final isFirst = rank == 1;

              return InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (kIsWeb && MediaQuery.of(context).size.width >= 1024) {
                    DesktopLayoutState.openArtist(artistName);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ArtistProfileScreen(artistName: artistName),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 128,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: isFirst
                                    ? [themeColor, const Color(0xFFFF6584)]
                                    : [
                                        const Color(0xFF2C2C3E),
                                        const Color(0xFF1A1A26),
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                artistName.isNotEmpty
                                    ? artistName.substring(0, 1).toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isFirst
                                  ? themeColor
                                  : const Color(0xFF282838),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF14141E),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '#$rank',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$streams ${streams == 1 ? "stream" : "streams"}',
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
        ),
      ],
    );
  }

  /// Top Tracks this month Section (Spotify Tracklist).
  Widget _buildTopTracksSection(
    BuildContext context, {
    required PreferencesService prefs,
    required MusicService music,
    required Color themeColor,
  }) {
    final allSongs = prefs.mostPlayedSongs;
    final displaySongs = _showAllTopTracks
        ? allSongs
        : allSongs.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top tracks this month',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Only visible to you',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (allSongs.length > 5)
              TextButton(
                onPressed: () {
                  setState(() => _showAllTopTracks = !_showAllTopTracks);
                },
                child: Text(
                  _showAllTopTracks ? 'Show less' : 'Show all',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Play All & Shuffle Buttons Row
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 20,
              ),
              label: Text(
                'Play All (${allSongs.length})',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                music.playMostPlayedSong(
                  allSongs.first,
                  allSongs: allSongs,
                  startIndex: 0,
                );
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(
                Icons.shuffle_rounded,
                color: Colors.white70,
                size: 18,
              ),
              label: const Text(
                'Shuffle',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                final shuffled = List<Map<String, dynamic>>.from(allSongs)
                  ..shuffle();
                music.playMostPlayedSong(
                  shuffled.first,
                  allSongs: shuffled,
                  startIndex: 0,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Spotify-grade Tracklist
        Material(
          color: const Color(0xFF14141E),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displaySongs.length,
            separatorBuilder: (context, index) => Divider(
              color: Colors.white.withValues(alpha: 0.05),
              height: 1,
              indent: 68,
            ),
            itemBuilder: (context, index) {
              final song = displaySongs[index];
              final rank = index + 1;
              final songId = (song['id'] as String?) ?? '';
              final isCurrent = music.currentSong?.id.value == songId;
              final isLiked = music.isLiked(songId);
              final playCount = (song['playCount'] as num?)?.toInt() ?? 1;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            color: isCurrent
                                ? themeColor
                                : Colors.white.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
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
                                  size: 20,
                                ),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                color: Colors.black54,
                                child: Center(
                                  child: AnimatedEqualizer(
                                    isPlaying: music.isPlaying,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(
                  song['title'] ?? 'Unknown Track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? themeColor : Colors.white,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
                subtitle: Text(
                  song['author'] ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$playCount ${playCount == 1 ? "play" : "plays"}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isLiked
                            ? const Color(0xFFFA2D48)
                            : Colors.white30,
                        size: 19,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        music.toggleLikeMap(song);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  music.playMostPlayedSong(
                    song,
                    allSongs: allSongs,
                    startIndex: index,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Public / Saved Playlists Section (Spotify Cards Carousel).
  Widget _buildPlaylistsSection(
    BuildContext context, {
    required MusicService music,
    required String userName,
  }) {
    final playlists = music.customPlaylists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Public Playlists',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: playlists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final name = (playlist['name'] as String?) ?? 'My Playlist';
              final songs = (playlist['songs'] as List?) ?? [];
              final thumbnail = (playlist['thumbnail'] as String?) ?? '';

              return InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final playlistId = playlist['id'] ?? '';
                  if (kIsWeb && MediaQuery.of(context).size.width >= 1024) {
                    DesktopLayoutState.openPlaylist(playlistId);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CustomPlaylistScreen(playlistId: playlistId),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 116,
                          height: 100,
                          color: const Color(0xFF222232),
                          child: thumbnail.isNotEmpty
                              ? Image.network(
                                  thumbnail,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.queue_music_rounded,
                                    color: Colors.white38,
                                    size: 32,
                                  ),
                                )
                              : const Icon(
                                  Icons.queue_music_rounded,
                                  color: Colors.white38,
                                  size: 32,
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'By $userName • ${songs.length} songs',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 11),
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
}
