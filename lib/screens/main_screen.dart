import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'spotify_import_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/floating_nav_dock.dart';
import '../widgets/interactive_update_dialog.dart';
import '../widgets/welcome_onboarding_dialog.dart';
import '../services/music_service.dart';
import '../services/preferences_service.dart';
import '../services/notification_permission_service.dart';
import '../services/update_service.dart';
import '../services/spotify_import_service.dart';
import '../services/data_snapshot_service.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/offline_indicator_banner.dart';
import '../widgets/dilse_notification.dart';
import '../services/connectivity_service.dart';
import '../layouts/desktop_app_shell.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static _MainScreenState? _instance;

  /// Programmatically switch active navigation tab (0: Home, 1: Search, 2: Library, 3: Downloads).
  static void switchToTab(int index) {
    _instance?._switchToTab(index);
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  final GlobalKey<SearchScreenState> _searchScreenKey =
      GlobalKey<SearchScreenState>();
  DateTime? _lastPoorNetworkNotif;

  @override
  void initState() {
    super.initState();
    MainScreen._instance = this;
    _pageController = PageController(initialPage: _selectedIndex);
    MusicService().addListener(_onMusicServiceChanged);
    ConnectivityService().init();
    ConnectivityService.qualityNotifier.addListener(_onNetworkQualityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAutoRestore();
        _checkFirstTimeNamePrompt();
        NotificationPermissionService.promptIfNeeded(context);
        _checkAutoAppUpdate();
      }
    });
  }

  void _onNetworkQualityChanged() {
    if (!mounted) return;
    final quality = ConnectivityService.qualityNotifier.value;
    if (quality == NetworkQuality.good) return;

    final now = DateTime.now();
    if (_lastPoorNetworkNotif != null &&
        now.difference(_lastPoorNetworkNotif!) < const Duration(seconds: 45)) {
      return;
    }
    _lastPoorNetworkNotif = now;

    final isOffline = quality == NetworkQuality.offline;
    DilSeNotification.warning(
      context,
      isOffline ? 'You are Offline' : 'Weak Internet Connection',
      subtitle: kIsWeb
          ? 'Tap to open Offline Library'
          : 'Tap to switch to Downloads',
      onTap: () {
        _switchToTab(3);
      },
    );
  }

  void _switchToTab(int index) {
    if (mounted && _selectedIndex != index) {
      setState(() => _selectedIndex = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _checkAutoRestore() async {
    try {
      final restored = await DataSnapshotService().autoRestoreIfEmpty();
      if (restored && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.restore_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Welcome back! Restored your playlists & library from backup snapshot.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF1DB954),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[MainScreen] Auto restore check error: $e');
    }
  }

  Future<void> _checkAutoAppUpdate() async {
    // Only check for updates on mobile devices after intro animation
    if (kIsWeb) return;
    final prefs = PreferencesService();
    if (!prefs.hasPromptedName) return; // Wait until name prompt is completed
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    try {
      final updateInfo = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (updateInfo != null && updateInfo.hasUpdate) {
        showDialog(
          context: context,
          barrierDismissible: true,
          barrierColor: Colors.black.withValues(alpha: 0.75),
          builder: (ctx) => InteractiveUpdateDialog(info: updateInfo),
        );
      }
    } catch (e) {
      debugPrint('[MainScreen] Auto update check deferred: $e');
    }
  }

  void _checkFirstTimeNamePrompt() {
    final prefs = PreferencesService();
    if (!prefs.hasPromptedName) {
      WelcomeOnboardingDialog.show(
        context,
        onCompleted: () {
          _checkAutoAppUpdate();
        },
      );
    }
  }

  @override
  void dispose() {
    if (MainScreen._instance == this) {
      MainScreen._instance = null;
    }
    ConnectivityService.qualityNotifier.removeListener(
      _onNetworkQualityChanged,
    );
    _pageController.dispose();
    MusicService().removeListener(_onMusicServiceChanged);
    super.dispose();
  }

  void _onMusicServiceChanged() {
    if (MusicService().currentSong != null && mounted) {
      NotificationPermissionService.promptIfNeeded(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // If on Search Tab (index 1), verify whether active sub-search was handled
        if (_selectedIndex == 1) {
          final searchState = _searchScreenKey.currentState;
          if (searchState != null) {
            if (searchState.wasBackHandledRecently()) {
              return;
            }
            if (searchState.isSearchActive) {
              searchState.clearSearchAndDismiss();
              return;
            }
          }
        }

        // With no active sub-search on Tab 1, or currently on Tab 2 (Library):
        // Switch back to Tab 0 (Home) before exiting the app.
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        body: DesktopAppShell(
          mobileBody: ResponsiveWrapper(
            child: Stack(
              children: [
                PageView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  children: [
                    const HomeScreen(),
                    SearchScreen(
                      key: _searchScreenKey,
                      isActive: _selectedIndex == 1,
                    ),
                    const LibraryScreen(),
                    const DownloadsScreen(),
                  ],
                ),
                // Floating Mini Player & Floating Glass Dock stacked at the bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _BackgroundImportBanner(),
                      const MiniPlayer(),
                      FloatingNavDock(
                        selectedIndex: _selectedIndex,
                        onTabSelected: (index) {
                          _switchToTab(index);
                        },
                      ),
                    ],
                  ),
                ),
                // Persistent non-intrusive offline indicator banner
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OfflineIndicatorBanner(
                    onGoToDownloads: () {
                      _switchToTab(3);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating background import pill indicating real-time background import progress
class _BackgroundImportBanner extends StatelessWidget {
  const _BackgroundImportBanner();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SpotifyImportService(),
      builder: (context, _) {
        final service = SpotifyImportService();
        if (!service.isImporting) return const SizedBox.shrink();

        final pct = (service.overallProgress * 100).toInt();
        final playlistText = service.totalPlaylists > 1
            ? 'Importing ${service.totalPlaylists} Playlists ($pct%)'
            : 'Importing Playlist ($pct%)';
        final detailText = service.currentTrackName.isNotEmpty
            ? '${service.currentPlaylistName} • ${service.currentTrackName}'
            : service.currentPlaylistName;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SpotifyImportScreen()),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF181818).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF1DB954).withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: service.overallProgress > 0
                        ? service.overallProgress
                        : null,
                    strokeWidth: 2.4,
                    color: const Color(0xFF1DB954),
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              playlistText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              color: Color(0xFF1DB954),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (detailText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detailText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIEW',
                        style: TextStyle(
                          color: Color(0xFF1DB954),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFF1DB954),
                        size: 9,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
