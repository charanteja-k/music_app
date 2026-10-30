import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme_tokens.dart';
import '../services/bug_report_service.dart';

enum DilSeNotificationType { success, info, warning, error, heart, download }

/// Modern Dynamic Island / Floating Pill in-app notification system for DilSe Music.
///
/// Replaces clunky rectangular bottom snackbars with a sleek, floating HUD pill
/// positioned at the top of the viewport (or above floating docks). Features
/// smooth spring-down entrance physics, glowing status badges, and swipe-to-dismiss.
/// Uses Flutter's TickerProvider animation lifecycle for zero timer leaks.
class DilSeNotification {
  DilSeNotification._();

  static OverlayEntry? _activeEntry;

  /// Shows a floating notification pill.
  static void show(
    BuildContext? context, {
    required String message,
    String? subtitle,
    DilSeNotificationType type = DilSeNotificationType.info,
    IconData? customIcon,
    Duration duration = const Duration(milliseconds: 2400),
    VoidCallback? onTap,
  }) {
    // Dismiss any existing notification immediately
    dismiss();

    final targetContext =
        context ?? BugReportService.instance.rootNavKey.currentContext;
    if (targetContext == null) return;

    final overlay = Overlay.maybeOf(targetContext);
    if (overlay == null) return;

    HapticFeedback.lightImpact();

    _activeEntry = OverlayEntry(
      builder: (ctx) => _DilSeNotificationPill(
        message: message,
        subtitle: subtitle,
        type: type,
        customIcon: customIcon,
        duration: duration,
        onTap: onTap,
        onDismiss: dismiss,
      ),
    );

    overlay.insert(_activeEntry!);
  }

  /// Convenience helper for success messages (e.g. downloaded, added to playlist).
  static void success(
    BuildContext? context,
    String message, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: DilSeNotificationType.success,
      onTap: onTap,
    );
  }

  /// Convenience helper for informational updates.
  static void info(
    BuildContext? context,
    String message, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: DilSeNotificationType.info,
      onTap: onTap,
    );
  }

  /// Convenience helper for warning / DRM / offline notifications.
  static void warning(
    BuildContext? context,
    String message, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: DilSeNotificationType.warning,
      onTap: onTap,
    );
  }

  /// Convenience helper for errors.
  static void error(
    BuildContext? context,
    String message, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: DilSeNotificationType.error,
      onTap: onTap,
    );
  }

  /// Convenience helper for liked / favorited songs.
  static void heart(
    BuildContext? context,
    String message, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: DilSeNotificationType.heart,
      onTap: onTap,
    );
  }

  /// Convenience helper for download operations.
  static void download(
    BuildContext? context,
    String message, {
    String? subtitle,
    bool isSuccess = true,
    VoidCallback? onTap,
  }) {
    show(
      context,
      message: message,
      subtitle: subtitle,
      type: isSuccess
          ? DilSeNotificationType.download
          : DilSeNotificationType.warning,
      onTap: onTap,
    );
  }

  /// Dismisses active notification entry.
  static void dismiss() {
    if (_activeEntry != null) {
      _activeEntry?.remove();
      _activeEntry = null;
    }
  }
}

class _DilSeNotificationPill extends StatefulWidget {
  final String message;
  final String? subtitle;
  final DilSeNotificationType type;
  final IconData? customIcon;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _DilSeNotificationPill({
    required this.message,
    this.subtitle,
    required this.type,
    this.customIcon,
    required this.duration,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_DilSeNotificationPill> createState() => _DilSeNotificationPillState();
}

class _DilSeNotificationPillState extends State<_DilSeNotificationPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    final enterMs = 280.0;
    final holdMs = widget.duration.inMilliseconds.toDouble();
    final exitMs = 220.0;
    final totalDuration = Duration(
      milliseconds: (enterMs + holdMs + exitMs).toInt(),
    );

    _controller = AnimationController(vsync: this, duration: totalDuration);

    _slideAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: enterMs,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: holdMs),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: -1.2,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: exitMs,
      ),
    ]).animate(_controller);

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: enterMs,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: holdMs),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: exitMs,
      ),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.88,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: enterMs,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: holdMs),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.90,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: exitMs,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDismiss();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _controller.stop();
    widget.onDismiss();
  }

  Color get _accentColor {
    switch (widget.type) {
      case DilSeNotificationType.success:
      case DilSeNotificationType.download:
        return const Color(0xFF1DB954); // Emerald Green
      case DilSeNotificationType.heart:
        return AppThemeTokens.brandRuby; // Ruby Red
      case DilSeNotificationType.warning:
        return const Color(0xFFFF9F0A); // Amber
      case DilSeNotificationType.error:
        return const Color(0xFFFF453A); // Crimson Red
      case DilSeNotificationType.info:
        return const Color(0xFF64D2FF); // Cyan Accent
    }
  }

  IconData get _icon {
    if (widget.customIcon != null) return widget.customIcon!;
    switch (widget.type) {
      case DilSeNotificationType.success:
        return Icons.check_circle_rounded;
      case DilSeNotificationType.download:
        return Icons.download_done_rounded;
      case DilSeNotificationType.heart:
        return Icons.favorite_rounded;
      case DilSeNotificationType.warning:
        return Icons.info_outline_rounded;
      case DilSeNotificationType.error:
        return Icons.error_outline_rounded;
      case DilSeNotificationType.info:
        return Icons.music_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top > 0
        ? mediaQuery.padding.top + 8
        : 28.0;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slideAnimation.value * 40),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value.clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            );
          },
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! < -4) {
                _handleDismiss();
              }
            },
            onTap: () {
              if (widget.onTap != null) {
                widget.onTap!();
              }
              _handleDismiss();
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(100), // Pill Shape
                  border: Border.all(
                    color: _accentColor.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.65),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glowing Icon Container
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_icon, color: _accentColor, size: 17),
                    ),
                    const SizedBox(width: 12),
                    // Message / Subtitle
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle != null &&
                              widget.subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Subtle close/dismiss button
                    GestureDetector(
                      onTap: _handleDismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.4),
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
}
