import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/custom_playlist_screen.dart';
import '../screens/artist_profile_screen.dart';
import '../screens/album_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/profile_screen.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../screens/curated_playlist_screen.dart';
import '../models/jio_album.dart';
import 'desktop_layout_state.dart';

/// Spotify-grade Center Main Viewport (#main-view).
///
/// Features:
/// 1. Independent vertical scrolling container for central navigation routes.
/// 2. Preserves scroll states using [PageStorageKey] and [IndexedStack].
/// 3. Automatically updates when [DesktopLayoutState.activeNavTab] changes.
/// 4. Renders playlists, artist profiles, albums, settings, and profile seamlessly inside the desktop spatial grid.
class DesktopMainViewport extends StatelessWidget {
  const DesktopMainViewport({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFF1E1E1E), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: ValueListenableBuilder<DesktopNavTab>(
          valueListenable: DesktopLayoutState.activeNavTab,
          builder: (context, activeTab, _) {
            if (activeTab == DesktopNavTab.settings) {
              return const SettingsScreen(
                key: ValueKey('desktop_settings_viewport'),
              );
            }

            if (activeTab == DesktopNavTab.profile) {
              return const ProfileScreen(
                key: ValueKey('desktop_profile_viewport'),
              );
            }

            if (activeTab == DesktopNavTab.customPlaylist) {
              return ValueListenableBuilder<String?>(
                valueListenable: DesktopLayoutState.activePlaylistId,
                builder: (context, playlistId, _) {
                  if (playlistId == null || playlistId.isEmpty) {
                    return _buildIndexedStack(DesktopNavTab.home);
                  }
                  final curatedData =
                      DesktopLayoutState.activeCuratedPlaylistData.value;
                  if (curatedData != null) {
                    return CuratedPlaylistScreen(
                      key: ValueKey('desktop_curated_$playlistId'),
                      title: curatedData['title'] as String,
                      subtitle: curatedData['subtitle'] as String,
                      query: curatedData['query'] as String?,
                      initialSongs: curatedData['initialSongs'] as List<Video>?,
                      fetchSongs:
                          curatedData['fetchSongs']
                              as Future<List<Video>> Function()?,
                      gradientColors:
                          curatedData['gradientColors'] as List<Color>?,
                      icon: curatedData['icon'] as IconData?,
                      imageUrl: curatedData['imageUrl'] as String?,
                    );
                  }
                  return CustomPlaylistScreen(
                    key: ValueKey('desktop_playlist_$playlistId'),
                    playlistId: playlistId,
                  );
                },
              );
            }

            if (activeTab == DesktopNavTab.artistProfile) {
              return ValueListenableBuilder<String?>(
                valueListenable: DesktopLayoutState.activeArtistName,
                builder: (context, artistName, _) {
                  if (artistName == null || artistName.isEmpty) {
                    return _buildIndexedStack(DesktopNavTab.home);
                  }
                  return ArtistProfileScreen(
                    key: ValueKey('desktop_artist_$artistName'),
                    artistName: artistName,
                  );
                },
              );
            }

            if (activeTab == DesktopNavTab.album) {
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: DesktopLayoutState.activeAlbumData,
                builder: (context, albumData, _) {
                  if (albumData == null) {
                    return _buildIndexedStack(DesktopNavTab.home);
                  }
                  final album = albumData['album'] as JioAlbum?;
                  final albumId = albumData['albumId'] as String?;
                  final albumTitle = albumData['albumTitle'] as String?;
                  final albumArtwork = albumData['albumArtwork'] as String?;
                  final albumArtist = albumData['albumArtist'] as String?;

                  return AlbumScreen(
                    key: ValueKey(
                      'desktop_album_${albumId ?? albumTitle ?? 'default'}',
                    ),
                    album: album,
                    albumId: albumId,
                    albumTitle: albumTitle,
                    albumArtwork: albumArtwork,
                    albumArtist: albumArtist,
                  );
                },
              );
            }

            return _buildIndexedStack(activeTab);
          },
        ),
      ),
    );
  }

  Widget _buildIndexedStack(DesktopNavTab tab) {
    return IndexedStack(
      index: _getTabIndex(tab),
      children: const [
        HomeScreen(key: PageStorageKey('desktop_home_viewport')),
        SearchScreen(
          key: PageStorageKey('desktop_search_viewport'),
          isDesktopView: true,
        ),
        LibraryScreen(key: PageStorageKey('desktop_library_viewport')),
      ],
    );
  }

  int _getTabIndex(DesktopNavTab tab) {
    switch (tab) {
      case DesktopNavTab.home:
      case DesktopNavTab.customPlaylist:
      case DesktopNavTab.artistProfile:
      case DesktopNavTab.album:
      case DesktopNavTab.settings:
      case DesktopNavTab.profile:
        return 0;
      case DesktopNavTab.search:
        return 1;
      case DesktopNavTab.library:
        return 2;
    }
  }
}
