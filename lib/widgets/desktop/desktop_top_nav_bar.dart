import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../layouts/desktop_layout_state.dart';
import '../../services/preferences_service.dart';
import '../../services/auth_service.dart';
import '../../screens/dilse_capsule_screen.dart';
import 'desktop_search_dropdown.dart';
import '../profile_avatar_helper.dart';

/// Spotify-grade 64px Desktop Top Global Navigation Bar (#global-nav-bar).
///
/// Features:
/// 1. Leading: DilSe Official Logo image asset + branding with quick Home navigation.
/// 2. Center: Spotify-style Circular Home Button + Centered Pill Search Bar with
///    Browse categories action and `Ctrl+Shift+L` keyboard accelerator.
/// 3. Trailing: Capsule trigger, Settings, Right Panel Dock Toggle, and Profile Avatar.
class DesktopTopNavBar extends StatefulWidget {
  const DesktopTopNavBar({super.key});

  @override
  State<DesktopTopNavBar> createState() => _DesktopTopNavBarState();
}

class _DesktopTopNavBarState extends State<DesktopTopNavBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _searchLayerLink = LayerLink();
  final ValueNotifier<double> _searchWidthNotifier = ValueNotifier<double>(
    460.0,
  );

  OverlayEntry? _recentSearchesOverlay;

  @override
  void initState() {
    super.initState();
    _searchController.text = DesktopLayoutState.globalSearchQuery.value;
    DesktopLayoutState.globalSearchQuery.addListener(_syncSearchQuery);
    _searchFocusNode.addListener(_onFocusChanged);
    _searchController.addListener(_onControllerChanged);
  }

  void _syncSearchQuery() {
    if (_searchController.text != DesktopLayoutState.globalSearchQuery.value) {
      _searchController.text = DesktopLayoutState.globalSearchQuery.value;
    }
  }

  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      if (_searchController.text.trim().isEmpty) {
        _showRecentSearchesOverlay();
      }
    }
  }

  void _onControllerChanged() {
    if (_searchFocusNode.hasFocus) {
      if (_searchController.text.trim().isEmpty) {
        _showRecentSearchesOverlay();
      } else {
        _hideRecentSearchesOverlay();
      }
    }
  }

  void _showRecentSearchesOverlay() {
    if (_recentSearchesOverlay != null || !mounted) return;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _recentSearchesOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissSearchDropdown,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            DesktopSearchDropdown(
              layerLink: _searchLayerLink,
              searchWidthListenable: _searchWidthNotifier,
              onDismiss: _dismissSearchDropdown,
            ),
          ],
        );
      },
    );

    overlay.insert(_recentSearchesOverlay!);
  }

  void _hideRecentSearchesOverlay() {
    if (_recentSearchesOverlay != null && _recentSearchesOverlay!.mounted) {
      _recentSearchesOverlay?.remove();
      _recentSearchesOverlay = null;
    }
  }

  void _dismissSearchDropdown() {
    _searchFocusNode.unfocus();
    _hideRecentSearchesOverlay();
  }

  @override
  void dispose() {
    _hideRecentSearchesOverlay();
    _searchWidthNotifier.dispose();
    DesktopLayoutState.globalSearchQuery.removeListener(_syncSearchQuery);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.removeListener(_onControllerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
    if (DesktopLayoutState.activeNavTab.value != DesktopNavTab.search) {
      DesktopLayoutState.setNavTab(DesktopNavTab.search);
    }
    if (_searchController.text.trim().isEmpty) {
      _showRecentSearchesOverlay();
    }
  }

  void _onSearchChanged(String query) {
    if (query.trim().isNotEmpty) {
      _hideRecentSearchesOverlay();
    } else if (_searchFocusNode.hasFocus) {
      _showRecentSearchesOverlay();
    }
    DesktopLayoutState.globalSearchQuery.value = query.trim();
    if (DesktopLayoutState.activeNavTab.value != DesktopNavTab.search) {
      DesktopLayoutState.setNavTab(DesktopNavTab.search);
    }
  }

  void _onSearchSubmitted(String query) {
    DesktopLayoutState.submitSearch(query);
  }

  void _openBrowseCategories() {
    _hideRecentSearchesOverlay();
    _searchController.clear();
    DesktopLayoutState.globalSearchQuery.value = '';
    DesktopLayoutState.submittedSearchQuery.value = '';
    DesktopLayoutState.setNavTab(DesktopNavTab.search);
  }

  void _navigateToHome() {
    _hideRecentSearchesOverlay();
    _searchController.clear();
    DesktopLayoutState.globalSearchQuery.value = '';
    DesktopLayoutState.submittedSearchQuery.value = '';
    DesktopLayoutState.setNavTab(DesktopNavTab.home);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyL,
          control: true,
          shift: true,
        ): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true, shift: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape):
            _dismissSearchDropdown,
      },
      child: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) {
          final accentColor = prefs.themeColor;

          return Container(
            height: 64.0,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            decoration: const BoxDecoration(
              color: Color(0xFF000000),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E1E1E), width: 1.0),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 900.0;
                final isSuperCompact = constraints.maxWidth < 750.0;
                final searchWidth = isSuperCompact
                    ? 220.0
                    : (isCompact ? 300.0 : 460.0);
                _searchWidthNotifier.value = searchWidth;

                return Row(
                  children: [
                    // 1. LEADING: DILSE BRAND LOGO + HOME NAV
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8.0),
                          onTap: _navigateToHome,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 4.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10.0),
                                  child: Image.asset(
                                    'assets/images/dilse_logo.png',
                                    width: 36.0,
                                    height: 36.0,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 36.0,
                                      height: 36.0,
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        borderRadius: BorderRadius.circular(
                                          10.0,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!isCompact) ...[
                                  const SizedBox(width: 12.0),
                                  const Text(
                                    'DilSe Music',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // 2. CENTER: SPOTIFY-STYLE CIRCULAR HOME BUTTON + PILL SEARCH CONTAINER
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Spotify-style Standalone Circular Home Button
                        ValueListenableBuilder<DesktopNavTab>(
                          valueListenable: DesktopLayoutState.activeNavTab,
                          builder: (context, activeTab, _) {
                            final isHomeActive =
                                activeTab == DesktopNavTab.home;

                            return Tooltip(
                              message: 'Home',
                              child: InkWell(
                                onTap: _navigateToHome,
                                borderRadius: BorderRadius.circular(24.0),
                                child: Container(
                                  width: 44.0,
                                  height: 44.0,
                                  decoration: BoxDecoration(
                                    color: isHomeActive
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : const Color(0xFF1F1F24),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isHomeActive
                                          ? Colors.white.withValues(alpha: 0.25)
                                          : Colors.white.withValues(
                                              alpha: 0.06,
                                            ),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.home_filled,
                                    color: isHomeActive
                                        ? Colors.white
                                        : Colors.white70,
                                    size: 22.0,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(width: 10.0),

                        // Spotify Pill Search Container with LayerLink target
                        TapRegion(
                          groupId: 'desktop_search_bar',
                          onTapOutside: (_) {
                            _dismissSearchDropdown();
                          },
                          child: CompositedTransformTarget(
                            link: _searchLayerLink,
                            child: Container(
                              height: 46.0,
                              width: searchWidth,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F1F24),
                                borderRadius: BorderRadius.circular(23.0),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    icon: Icon(
                                      Icons.search_rounded,
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                      size: 20.0,
                                    ),
                                    onPressed: _focusSearch,
                                  ),
                                  const SizedBox(width: 6.0),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                      ),

                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: isSuperCompact
                                            ? 'Search...'
                                            : 'What do you want to play?',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.45,
                                          ),
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      onTap: () {
                                        if (_searchController.text
                                            .trim()
                                            .isEmpty) {
                                          _showRecentSearchesOverlay();
                                        }
                                      },
                                      onChanged: _onSearchChanged,
                                      onSubmitted: (query) {
                                        final trimmed = query.trim();
                                        if (trimmed.isNotEmpty) {
                                          unawaited(
                                            PreferencesService()
                                                .addToSearchHistory(
                                                  trimmed,
                                                  type: 'query',
                                                ),
                                          );
                                        }
                                        _onSearchSubmitted(query);
                                        _onSearchChanged(query);
                                        _dismissSearchDropdown();
                                      },
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        DesktopLayoutState
                                                .submittedSearchQuery
                                                .value =
                                            '';
                                        _onSearchChanged('');
                                        if (_searchFocusNode.hasFocus) {
                                          _showRecentSearchesOverlay();
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0,
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          size: 16.0,
                                        ),
                                      ),
                                    ),

                                  if (!isSuperCompact) ...[
                                    // Vertical divider line |
                                    Container(
                                      height: 18.0,
                                      width: 1.0,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),

                                    // Browse/Explore Categories Icon Button (Spotify-style)
                                    Tooltip(
                                      message: 'Browse Categories',
                                      child: InkWell(
                                        onTap: _openBrowseCategories,
                                        borderRadius: BorderRadius.circular(
                                          6.0,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.grid_view_rounded,
                                            color: Colors.white.withValues(
                                              alpha: 0.65,
                                            ),
                                            size: 18.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],

                                  if (!isCompact) ...[
                                    const SizedBox(width: 6.0),
                                    // Accelerator Badge (Ctrl+Shift+L)
                                    InkWell(
                                      onTap: _focusSearch,
                                      borderRadius: BorderRadius.circular(5.0),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 3.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            5.0,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.06,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          'Ctrl+Shift+L',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 10.0,
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // 3. TRAILING: CLEAN, UNCLUTTERED ACTIONS
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // DilSe Capsule Button
                        Tooltip(
                          message: 'DilSe Capsule',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Container(
                              padding: const EdgeInsets.all(5.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF24242E),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 15.0,
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DilSeCapsuleScreen(),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 4.0),

                        // Settings Gear Button
                        Tooltip(
                          message: 'Settings',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.settings_outlined,
                              color: Colors.white.withValues(alpha: 0.75),
                              size: 20.0,
                            ),
                            onPressed: () {
                              DesktopLayoutState.openSettings();
                            },
                          ),
                        ),

                        const SizedBox(width: 4.0),

                        // Right Panel Toggle
                        Tooltip(
                          message: 'Toggle Right Panel',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.view_sidebar_rounded,
                              color: Colors.white.withValues(alpha: 0.75),
                              size: 20.0,
                            ),
                            onPressed: () =>
                                DesktopLayoutState.toggleRightPanel(),
                          ),
                        ),

                        const SizedBox(width: 8.0),

                        // Single Unified User Profile Avatar (Custom Photo & Google Account Linked)
                        AnimatedBuilder(
                          animation: Listenable.merge([
                            AuthService(),
                            PreferencesService(),
                          ]),
                          builder: (context, _) {
                            final auth = AuthService();
                            final prefs = PreferencesService();
                            final isAuth = auth.isAuthenticated;
                            final customImagePath = prefs.profileImagePath;
                            final hasCustom = hasProfileImage(customImagePath);
                            final photoUrl = auth.userPhotoUrl;
                            final hasGooglePhoto =
                                isAuth &&
                                photoUrl != null &&
                                photoUrl.isNotEmpty;
                            final name =
                                isAuth &&
                                    auth.userDisplayName != null &&
                                    auth.userDisplayName!.isNotEmpty
                                ? auth.userDisplayName!
                                : (prefs.userName.isNotEmpty &&
                                          prefs.userName != 'Friend'
                                      ? prefs.userName
                                      : 'User');
                            final initial = name.trim().isNotEmpty
                                ? name.trim()[0].toUpperCase()
                                : 'U';

                            final customImageProvider = hasCustom
                                ? getProfileImageProvider(customImagePath)
                                : null;

                            return Tooltip(
                              message: isAuth
                                  ? '$name (Google Connected)'
                                  : (name != 'User' ? name : 'Profile'),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    DesktopLayoutState.openProfile();
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 32.0,
                                        height: 32.0,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF181818),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isAuth
                                                ? const Color(
                                                    0xFF4285F4,
                                                  ).withValues(alpha: 0.6)
                                                : Colors.white.withValues(
                                                    alpha: 0.18,
                                                  ),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: customImageProvider != null
                                              ? Image(
                                                  image: customImageProvider,
                                                  width: 32.0,
                                                  height: 32.0,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      Center(
                                                        child: Text(
                                                          initial,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                )
                                              : (hasGooglePhoto
                                                    ? Image.network(
                                                        photoUrl,
                                                        width: 32.0,
                                                        height: 32.0,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, _, _) => Center(
                                                              child: Text(
                                                                initial,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                      )
                                                    : (prefs
                                                                  .userName
                                                                  .isNotEmpty &&
                                                              prefs.userName !=
                                                                  'Friend'
                                                          ? Center(
                                                              child: Text(
                                                                initial,
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            )
                                                          : const Icon(
                                                              Icons
                                                                  .person_rounded,
                                                              color: Colors
                                                                  .white70,
                                                              size: 17,
                                                            ))),
                                        ),
                                      ),
                                      if (isAuth)
                                        Positioned(
                                          right: -1,
                                          bottom: -1,
                                          child: Container(
                                            width: 9.0,
                                            height: 9.0,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1DB954),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0xFF000000),
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
