import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/preferences_service.dart';
import '../services/music_service.dart';
import '../widgets/animated_equalizer.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showAvatarOptionsSheet(BuildContext context, PreferencesService prefs) {
    HapticFeedback.lightImpact();
    final customImagePath = prefs.profileImagePath;
    final hasCustomImage =
        customImagePath != null && File(customImagePath).existsSync();

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
                        final pickedPath = pickedFiles.first.path;
                        if (pickedPath != null &&
                            File(pickedPath).existsSync()) {
                          await prefs.setProfileImagePath(pickedPath);
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
                        color: const Color(0xFFFA2D48).withValues(alpha: 0.15),
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
                  'This name personalizes your greetings and mixes.',
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
        final hasCustomImage =
            customImagePath != null && File(customImagePath).existsSync();

        return Scaffold(
          backgroundColor: const Color(0xFF0B0B0F),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B0B0F),
            elevation: 0,
            title: const Text(
              'Profile & Activity',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white70,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),

                // Apple-style Glowing User Avatar
                GestureDetector(
                  onTap: () => _showAvatarOptionsSheet(context, prefs),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFF1B1B26),
                          backgroundImage: hasCustomImage
                              ? FileImage(File(customImagePath))
                              : null,
                          child: hasCustomImage
                              ? null
                              : Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 42,
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
                          border: Border.all(
                            color: const Color(0xFF0B0B0F),
                            width: 2.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Name with edit trigger
                GestureDetector(
                  onTap: () => _showEditNameDialog(context, prefs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_outlined,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'DilSe Audiophile • Suno Dil Se',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 28),

                // 2x2 Metric Cards Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.45,
                  children: [
                    _buildMetricCard(
                      context,
                      icon: Icons.play_arrow_rounded,
                      iconColor: const Color(0xFFFA2D48),
                      title: 'Total Plays',
                      value: '${prefs.totalPlays}',
                      subtitle: 'Tracks enjoyed',
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xFFFF4081),
                      title: 'Liked Songs',
                      value: '${music.likedSongs.length}',
                      subtitle: 'Favorites saved',
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.download_done_rounded,
                      iconColor: const Color(0xFF1DB954),
                      title: 'Offline Music',
                      value: '${music.downloadedSongs.length}',
                      subtitle: 'Offline tracks',
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.person_search_rounded,
                      iconColor: const Color(0xFF2196F3),
                      title: 'Top Artist',
                      value: prefs.mostPlayedArtist.isNotEmpty
                          ? prefs.mostPlayedArtist
                          : 'Discovering',
                      subtitle: prefs.topArtistPlayCount > 0
                          ? '${prefs.topArtistPlayCount} plays'
                          : 'Most streamed',
                      isTextValue: true,
                    ),
                  ],
                ),

                // Top Streamed Artists Section (Ranked #1, #2, #3)
                if (prefs.getTopPlayedArtists().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        const Text(
                          'TOP STREAMED ARTISTS',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: themeColor.withValues(alpha: 0.35),
                            ),
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
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161622),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: prefs
                          .getTopPlayedArtists(limit: 3)
                          .asMap()
                          .entries
                          .map((entry) {
                            final rank = entry.key + 1;
                            final artistEntry = entry.value;
                            final isFirst = rank == 1;

                            return Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: isFirst
                                                ? [
                                                    themeColor,
                                                    const Color(0xFFFF6584),
                                                  ]
                                                : [
                                                    const Color(0xFF282838),
                                                    const Color(0xFF1E1E2C),
                                                  ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.mic_external_on_rounded,
                                            color: isFirst
                                                ? Colors.white
                                                : Colors.white60,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: isFirst
                                              ? themeColor
                                              : const Color(0xFF282838),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF161622),
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
                                  const SizedBox(height: 8),
                                  Text(
                                    artistEntry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isFirst
                                          ? Colors.white
                                          : Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                      fontWeight: isFirst
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${artistEntry.value} ${artistEntry.value == 1 ? "stream" : "streams"}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ),
                ],

                // Most Played Songs Section (Ranked #1..#100)
                if (prefs.mostPlayedSongs.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        const Text(
                          'MOST PLAYED SONGS',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: themeColor.withValues(alpha: 0.35),
                            ),
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
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Action Row: Play All & Shuffle
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 20,
                          ),
                          label: Text(
                            'Play All (${prefs.mostPlayedSongs.length})',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final list = prefs.mostPlayedSongs;
                            music.playMostPlayedSong(
                              list.first,
                              allSongs: list,
                              startIndex: 0,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: music.isShuffle
                                ? const Color(0xFF1DB954)
                                : Colors.white70,
                            size: 18,
                          ),
                          label: Text(
                            'Shuffle',
                            style: TextStyle(
                              color: music.isShuffle
                                  ? const Color(0xFF1DB954)
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: music.isShuffle
                                ? const Color(
                                    0xFF1DB954,
                                  ).withValues(alpha: 0.12)
                                : null,
                            side: BorderSide(
                              color: music.isShuffle
                                  ? const Color(
                                      0xFF1DB954,
                                    ).withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            music.setShuffle(true);
                            final shuffled = List<Map<String, dynamic>>.from(
                              prefs.mostPlayedSongs,
                            )..shuffle();
                            music.playMostPlayedSong(
                              shuffled.first,
                              allSongs: shuffled,
                              startIndex: 0,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Song List Container
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161622),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: prefs.mostPlayedSongs.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Colors.white10,
                        height: 1,
                        indent: 68,
                      ),
                      itemBuilder: (context, index) {
                        final song = prefs.mostPlayedSongs[index];
                        final rank = index + 1;
                        final isTop3 = rank <= 3;
                        final playCount =
                            (song['playCount'] as num?)?.toInt() ?? 1;
                        final songId = (song['id'] as String?) ?? '';
                        final isCurrent = music.currentSong?.id.value == songId;
                        final isLiked = music.isLiked(songId);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 26,
                                child: Center(
                                  child: Text(
                                    '$rank',
                                    style: TextStyle(
                                      color: isTop3
                                          ? themeColor
                                          : Colors.white54,
                                      fontWeight: isTop3
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      fontSize: rank > 99 ? 11 : 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
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
                                          ),
                                        ),
                                      ),
                                      if (isCurrent)
                                        Container(
                                          color: Colors.black54,
                                          child: Center(
                                            child: AnimatedEqualizer(
                                              isPlaying: music.isPlaying,
                                              size: 20,
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
                              fontWeight: FontWeight.w700,
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
                              color: Colors.white.withValues(alpha: 0.6),
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
                                  color: isTop3
                                      ? themeColor.withValues(alpha: 0.15)
                                      : const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isTop3
                                        ? themeColor.withValues(alpha: 0.4)
                                        : Colors.white12,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      size: 13,
                                      color: isTop3
                                          ? themeColor
                                          : Colors.white60,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$playCount ${playCount == 1 ? "play" : "plays"}',
                                      style: TextStyle(
                                        color: isTop3
                                            ? Colors.white
                                            : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
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
                                      : Colors.white38,
                                  size: 20,
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
                              allSongs: prefs.mostPlayedSongs,
                              startIndex: index,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Recent Listening Activity Card
                if (prefs.listeningHistory.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'RECENTLY PLAYED',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161622),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: prefs.listeningHistory.take(4).length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Colors.white10,
                        height: 1,
                        indent: 68,
                      ),
                      itemBuilder: (context, index) {
                        final track = prefs.listeningHistory[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              track['thumbnail'] ?? '',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 44,
                                    height: 44,
                                    color: Colors.white12,
                                    child: const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                    ),
                                  ),
                            ),
                          ),
                          title: Text(
                            track['title'] ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            track['author'] ?? 'Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.play_circle_outline_rounded,
                            color: Colors.white38,
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Action Button: Full Settings & Preferences
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E28),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Colors.white12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.tune_rounded, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Player & Audio Preferences',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    bool isTextValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTextValue ? 16 : 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
