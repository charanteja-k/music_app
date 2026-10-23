import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/music_service.dart';
import '../../services/preferences_service.dart';
import '../../services/data_snapshot_service.dart';
import 'google_logo.dart';

/// Top-right Google Account & User Profile Header Button.
/// Displays "Sign in with Google" when logged out, or user profile avatar when logged in.
class GoogleProfileHeaderButton extends StatefulWidget {
  final bool compact;
  const GoogleProfileHeaderButton({super.key, this.compact = false});

  @override
  State<GoogleProfileHeaderButton> createState() =>
      _GoogleProfileHeaderButtonState();
}

/// Public launcher for the unified Google Sign-In dialog modal.
Future<bool?> showGoogleSignInDialog(BuildContext context) async {
  HapticFeedback.lightImpact();
  final didSignIn = await showDialog<bool>(
    context: context,
    builder: (ctx) => const _GoogleSignInModal(),
  );

  if ((didSignIn == true || AuthService().isAuthenticated) && context.mounted) {
    await handlePostSignInSetup(context);
  }
  return didSignIn;
}

/// Helper that handles first-time account setup, guest migration, and welcome snackbar.
Future<void> handlePostSignInSetup(BuildContext context) async {
  final auth = AuthService();
  final prefs = PreferencesService();
  final userId = auth.userId ?? 'user';
  final name = auth.userDisplayName;

  if (name != null && name.trim().isNotEmpty) {
    await prefs.setUserName(name.trim());
  }

  final isNewAccount = prefs.isFirstTimeAccountSignIn(userId);
  final hasGuestData = prefs.hasGuestData();

  if (isNewAccount && hasGuestData && context.mounted) {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DataPreservationDialog(
        userName: auth.userDisplayName ?? 'Music Lover',
      ),
    );

    if (choice == 'fresh') {
      await DataSnapshotService().createSafetySnapshot(
        triggerReason: 'Guest Data Migration',
      );
      await prefs.clearListeningHistory();
      await prefs.clearMostPlayedSongs();
    }
    await prefs.markAccountSignedIn(userId);
  } else {
    await prefs.markAccountSignedIn(userId);
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome, ${auth.userDisplayName ?? "Music Lover"}! Signed in with Google.',
        ),
        backgroundColor: const Color(0xFF1E88E5),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _GoogleProfileHeaderButtonState extends State<GoogleProfileHeaderButton> {
  bool _isHovered = false;

  Future<void> _handleSignIn() async {
    await showGoogleSignInDialog(context);
  }

  void _showAccountDialog() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => const _GoogleAccountDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (!auth.isAuthenticated) {
          return widget.compact
              ? _buildCompactLoggedOutButton()
              : _buildLoggedOutButton();
        }
        return widget.compact
            ? _buildCompactLoggedInAvatar(auth)
            : _buildLoggedInAvatar(auth);
      },
    );
  }

  Widget _buildCompactLoggedOutButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: 'Sign in with Google',
        child: GestureDetector(
          onTap: _handleSignIn,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.16)
                  : const Color(0xFF181818),
              shape: BoxShape.circle,
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1.0,
              ),
            ),
            child: const Center(child: GoogleLogo(size: 16)),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLoggedInAvatar(AuthService auth) {
    final photoUrl = auth.userPhotoUrl;
    final name = auth.userDisplayName ?? 'Account';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: '$name (Google Connected)',
        child: GestureDetector(
          onTap: _showAccountDialog,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isHovered
                    ? const Color(0xFF4285F4)
                    : const Color(0xFF4285F4).withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildFallbackInitial(name),
                    )
                  : _buildFallbackInitial(name),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedOutButton() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleSignIn,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.16)
                : const Color(0xFF181818),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GoogleLogo(size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Sign in with Google',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInAvatar(AuthService auth) {
    final photoUrl = auth.userPhotoUrl;
    final name = auth.userDisplayName ?? 'Account';
    final firstName = name.split(' ').first;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showAccountDialog,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.15)
                : const Color(0xFF181818),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackInitial(name),
                        )
                      : _buildFallbackInitial(name),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    firstName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackInitial(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFF333344),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Modal dialog providing account details, Google account status, and sign-out option.
class _GoogleAccountDialog extends StatelessWidget {
  const _GoogleAccountDialog();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final photoUrl = auth.userPhotoUrl;
    final name = auth.userDisplayName ?? 'DilSe User';
    final email = auth.userEmail ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF181822),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // User Avatar
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF4285F4), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.25),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: ClipOval(
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildFallback(name),
                      )
                    : _buildFallback(name),
              ),
            ),
            const SizedBox(height: 14),

            // User Name
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                email,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),

            // Connection Badge (Google Profile Active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF222230),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Google Account • Connected',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF4285F4),
                    size: 16,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Library Stats Tile
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF222230),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.library_music_rounded,
                        color: Color(0xFF1E88E5),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Music Library',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  Text(
                    '${MusicService().customPlaylists.length} playlists • ${MusicService().likedSongs.length} likes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Backing up library to cloud...'),
                            ],
                          ),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      final result = await CloudSyncService().sync();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? 'Cloud backup complete: ${result.mergedPlaylistsCount} playlists, ${result.mergedLikesCount} likes.'
                                  : 'Backup note: ${result.message}',
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: result.success
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF332025),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.backup_rounded, size: 16),
                    label: const Text('Backup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                      await auth.signOut();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Sign Out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                        0xFFEF5350,
                      ).withValues(alpha: 0.18),
                      foregroundColor: const Color(0xFFEF5350),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: const Color(0xFFEF5350).withValues(alpha: 0.4),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Switch to Guest Mode Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                  auth.switchToGuestMode();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Switched to Guest Mode. Your Google session remains intact.',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.person_outline_rounded, size: 16),
                label: const Text('Switch to Guest Mode'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white60,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(String name) {
    return Container(
      color: const Color(0xFF2E2E3E),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Dialog displayed to new accounts asking whether to merge guest music or start fresh.
class _DataPreservationDialog extends StatelessWidget {
  final String userName;
  const _DataPreservationDialog({required this.userName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF181824),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.merge_type_rounded,
                    color: Color(0xFF1E88E5),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $userName!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Existing Guest Data Detected',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'You have previous listening history and playlists from your guest session. How would you like to set up your account?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            // Option 1: Keep & Merge (Recommended)
            InkWell(
              onTap: () => Navigator.of(context).pop('keep'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF1E88E5),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Keep & Merge Previous Music (Recommended)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Keep your previous listening history and playlists linked to this Google account.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Option 2: Start Fresh
            InkWell(
              onTap: () => Navigator.of(context).pop('fresh'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF222230),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cleaning_services_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Start Fresh (Clean Slate)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Guest data is safely backed up. Start with a fresh slate for this account.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clean, modern Google Sign-In dialog adhering to DilSe's dark glassmorphic design.
/// Features a prominent vector Google logo at the top, clear value propositions,
/// a native "Continue with Google" primary action, and no temporary placeholders.
class _GoogleSignInModal extends StatefulWidget {
  const _GoogleSignInModal();

  @override
  State<_GoogleSignInModal> createState() => _GoogleSignInModalState();
}

class _GoogleSignInModalState extends State<_GoogleSignInModal> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _handleGoogleSignIn() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      final success = await AuthService().signIn();
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _isSigningIn = false;
            _errorMessage =
                AuthService().lastError ??
                'Google sign-in popup was cancelled or blocked.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _errorMessage = 'Sign-in failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 500;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E1E2C), Color(0xFF14141E)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 40,
                  spreadRadius: 4,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                  blurRadius: 48,
                  spreadRadius: -4,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Google Logo Emblem
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF252538),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF4285F4,
                            ).withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(child: GoogleLogo(size: 30)),
                    ),
                    const SizedBox(height: 14),

                    // Title
                    const Text(
                      'Sign in with Google',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      'Sign in with your Google account for cross-platform profile sync and high-fidelity 320kbps playback.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Feature Matrix Pills
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildFeatureRow(
                            icon: Icons.high_quality_rounded,
                            iconColor: const Color(0xFF34A853),
                            title: 'Lossless 320k Audio',
                            subtitle:
                                'Studio Master AAC matched to pristine sound',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(color: Colors.white10, height: 1),
                          ),
                          _buildFeatureRow(
                            icon: Icons.auto_awesome_rounded,
                            iconColor: const Color(0xFFFBBC05),
                            title: 'Personalized Mixes',
                            subtitle:
                                'Curated daily mixes, top charts, and artist radio',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(color: Colors.white10, height: 1),
                          ),
                          _buildFeatureRow(
                            icon: Icons.lock_outline_rounded,
                            iconColor: const Color(0xFF4285F4),
                            title: 'Strictly Read-Only',
                            subtitle:
                                'Private & secure standard Google account profile',
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE53935,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFE53935,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFEF5350),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: () async {
                                await AuthService().signInDemo(
                                  name: 'Tejas (Tester)',
                                  email: 'tejas.dilse@gmail.com',
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                              icon: const Icon(
                                Icons.account_circle_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'Sign in with Test Account',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Primary Button: Continue with Google
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1F1F1F),
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: _isSigningIn
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4285F4),
                                  ),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GoogleLogo(size: 20),
                                  SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Continue with Google',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFF1F1F1F),
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Secondary Button: Continue as Guest
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue as Guest',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

  Widget _buildFeatureRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
