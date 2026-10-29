import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/music_service.dart';
import '../services/bug_report_service.dart';
import '../constants/app_theme_tokens.dart';
import 'main_screen.dart';
import 'recovery_shell_screen.dart';

class IntroSplashScreen extends StatefulWidget {
  const IntroSplashScreen({super.key});

  /// Tracks whether the splash animation has completed once during this app session.
  /// Prevents MaterialApp rebuilds from re-triggering the splash screen.
  static bool hasCompletedSplash = false;

  @override
  State<IntroSplashScreen> createState() => _IntroSplashScreenState();
}

class _IntroSplashScreenState extends State<IntroSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _fallbackTimer;
  Timer? _hardFallbackTimer;
  bool _navigated = false;
  bool _showMainFallback = false;
  int _lastCharCount = 0;

  static const String _fullTitle = 'DilSe';
  static const String _fullTagline = 'Suno Dil Se.';

  @override
  void initState() {
    super.initState();

    // 1. Kick off concurrent background preloading of Home data immediately
    MusicService().preloadHomeData();

    // 2. Setup 60-120 FPS animation controller
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: kIsWeb ? 900 : 2500),
    );

    _controller.addListener(() {
      final t = _controller.value;
      if (!kIsWeb) {
        // Haptic ticking as characters appear
        final currentChars = _calculateTotalChars(t);
        if (currentChars > _lastCharCount) {
          _lastCharCount = currentChars;
          HapticFeedback.selectionClick();
        }
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToMain();
      }
    });

    // Safety fallback timer so user can NEVER be stuck on the splash screen
    _fallbackTimer = Timer(Duration(milliseconds: kIsWeb ? 1100 : 2900), () {
      if (mounted) _navigateToMain();
    });

    // Ultimate hard failsafe: if still mounted after 2.5s on web (or 3.5s on mobile), switch internal state to render MainScreen directly
    _hardFallbackTimer = Timer(
      Duration(milliseconds: kIsWeb ? 2500 : 3500),
      () {
        if (mounted && !_showMainFallback) {
          setState(() {
            _showMainFallback = true;
          });
        }
      },
    );

    _controller.forward();
  }

  int _calculateTotalChars(double t) {
    if (t < 0.20) return 0;
    if (t < 0.55) {
      final p = ((t - 0.20) / 0.35).clamp(0.0, 1.0);
      return (p * _fullTitle.length).floor();
    }
    final p = ((t - 0.55) / 0.35).clamp(0.0, 1.0);
    return _fullTitle.length + (p * _fullTagline.length).floor();
  }

  void _navigateToMain() {
    _fallbackTimer?.cancel();
    if (!mounted || _navigated) return;
    _navigated = true;
    IntroSplashScreen.hasCompletedSplash = true;
    try {
      final nav =
          BugReportService.instance.rootNavKey.currentState ??
          Navigator.of(context);
      nav.pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              ),
              child: child,
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('[IntroSplashScreen] Navigation error: $e');
      try {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _showMainFallback = true;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _hardFallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showMainFallback) {
      return const MainScreen();
    }
    return Scaffold(
      backgroundColor: AppThemeTokens.oledBackground,
      body: Stack(
        children: [
          // Minimalist ambient center glow
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final glowOpacity =
                  (t < 0.3 ? (t / 0.3) * 0.18 : 0.18 + (0.06 * (1.0 - t)))
                      .clamp(0.0, 0.28);

              return Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeTokens.brandRuby.withValues(
                          alpha: glowOpacity,
                        ),
                        blurRadius: 90,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Center: Logo + Typewriter text reveal
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;

                // 1. Logo entrance (0.0 -> 0.25)
                final logoOpacity = (t / 0.20).clamp(0.0, 1.0);
                final logoScale = 0.8 + (0.2 * (t / 0.22).clamp(0.0, 1.0));

                // 2. Typewriter Title "DilSe" (0.20 -> 0.55)
                final titleProgress = ((t - 0.20) / 0.35).clamp(0.0, 1.0);
                final titleCharCount = (titleProgress * _fullTitle.length)
                    .floor();
                final currentTitle = _fullTitle.substring(
                  0,
                  titleCharCount.clamp(0, _fullTitle.length),
                );

                // 3. Typewriter Tagline "Suno Dil Se." (0.55 -> 0.90)
                final taglineProgress = ((t - 0.55) / 0.35).clamp(0.0, 1.0);
                final taglineCharCount = (taglineProgress * _fullTagline.length)
                    .floor();
                final currentTagline = _fullTagline.substring(
                  0,
                  taglineCharCount.clamp(0, _fullTagline.length),
                );

                // Blinking cursor calculation
                final isTyping = t >= 0.20 && t < 0.92;
                final cursorBlink = ((t * 12).floor() % 2 == 0);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Heart Logo
                    Opacity(
                      opacity: logoOpacity,
                      child: Transform.scale(
                        scale: logoScale,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppThemeTokens.brandRuby.withValues(
                                  alpha: 0.5,
                                ),
                                blurRadius: 28,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/dilse_logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Typewriter Title
                    if (t >= 0.20)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) {
                              return const LinearGradient(
                                colors: [
                                  Colors.white,
                                  Color(0xFFFF758C),
                                  Color(0xFFFA2D48),
                                ],
                              ).createShader(bounds);
                            },
                            child: Text(
                              currentTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0,
                                height: 1.0,
                              ),
                            ),
                          ),
                          if (t < 0.55 && isTyping && cursorBlink)
                            Container(
                              width: 3,
                              height: 36,
                              margin: const EdgeInsets.only(left: 4),
                              color: AppThemeTokens.brandRuby,
                            ),
                        ],
                      ),

                    const SizedBox(height: 8),

                    // Typewriter Tagline
                    if (t >= 0.55)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentTagline,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.0,
                            ),
                          ),
                          if (t >= 0.55 && isTyping && cursorBlink)
                            Container(
                              width: 2,
                              height: 16,
                              margin: const EdgeInsets.only(left: 4),
                              color: AppThemeTokens.brandRuby,
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),

          // Emergency Recovery entry point (Rule #7: Zero-Black-Screen Invariant)
          Positioned(
            left: 20,
            bottom: 40,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (!kIsWeb && _controller.value < 0.25) {
                  return const SizedBox.shrink();
                }
                return TextButton.icon(
                  onPressed: () {
                    _fallbackTimer?.cancel();
                    _hardFallbackTimer?.cancel();
                    _controller.stop();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const RecoveryShellScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.shield_outlined,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  label: Text(
                    'Recovery',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),

          // Subtle skip button in bottom right corner
          Positioned(
            right: 20,
            bottom: 40,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (!kIsWeb && _controller.value < 0.25) {
                  return const SizedBox.shrink();
                }
                return TextButton(
                  onPressed: () {
                    _navigated = false;
                    _navigateToMain();
                    Future.delayed(const Duration(milliseconds: 350), () {
                      if (mounted && !_showMainFallback) {
                        setState(() {
                          _showMainFallback = true;
                        });
                      }
                    });
                  },
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
