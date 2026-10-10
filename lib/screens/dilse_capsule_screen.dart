import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/dilse_capsule_data.dart';
import '../services/capsule_service.dart';
import '../services/preferences_service.dart';
import '../constants/app_theme_tokens.dart';

/// Full-screen, interactive on-device "DilSe Capsule" Story Experience.
/// Generates and renders a private, Spotify Wrapped-style journey completely locally.
class DilSeCapsuleScreen extends StatefulWidget {
  final DilSeCapsuleData? initialData;
  final bool autoAdvance;

  const DilSeCapsuleScreen({
    super.key,
    this.initialData,
    this.autoAdvance = true,
  });

  @override
  State<DilSeCapsuleScreen> createState() => _DilSeCapsuleScreenState();
}

class _DilSeCapsuleScreenState extends State<DilSeCapsuleScreen>
    with SingleTickerProviderStateMixin {
  late final DilSeCapsuleData _data;
  late final PreferencesService _prefs;

  final GlobalKey _cardKey = GlobalKey();
  static const int _totalSlides = 5;

  int _currentSlide = 0;
  late AnimationController _progressController;
  bool _isPaused = false;
  bool _isSavingImage = false;

  @override
  void initState() {
    super.initState();
    _prefs = PreferencesService();
    _data = widget.initialData ?? CapsuleService().buildCapsuleData(_prefs);

    _progressController =
        AnimationController(vsync: this, duration: const Duration(seconds: 7))
          ..addStatusListener((status) {
            if (widget.autoAdvance && status == AnimationStatus.completed) {
              _advanceSlide();
            }
          });

    if (widget.autoAdvance) {
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _advanceSlide() {
    if (_currentSlide < _totalSlides - 1) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentSlide++;
      });
      if (widget.autoAdvance) {
        _progressController.forward(from: 0.0);
      }
    } else {
      _progressController.stop();
    }
  }

  void _previousSlide() {
    if (_currentSlide > 0) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentSlide--;
      });
      if (widget.autoAdvance) {
        _progressController.forward(from: 0.0);
      }
    } else {
      if (widget.autoAdvance) {
        _progressController.forward(from: 0.0);
      }
    }
  }

  void _pauseProgress() {
    if (!_isPaused) {
      _isPaused = true;
      _progressController.stop();
    }
  }

  void _resumeProgress() {
    if (_isPaused) {
      _isPaused = false;
      if (_currentSlide < _totalSlides - 1 || _progressController.value < 1.0) {
        _progressController.forward();
      }
    }
  }

  Future<void> _saveCardImage() async {
    if (_isSavingImage) return;
    setState(() => _isSavingImage = true);
    HapticFeedback.mediumImpact();

    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not locate render boundary');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Image byte encoding failed');
      }

      final pngBytes = byteData.buffer.asUint8List();

      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/dilse_capsule_$timestamp.png');
        await file.writeAsBytes(pngBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved Capsule Card to Documents/dilse_capsule_$timestamp.png',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1DB954),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Card snapshot captured successfully!'),
              backgroundColor: Color(0xFF1DB954),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save card: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingImage = false);
      }
    }
  }

  void _copySummaryText() {
    HapticFeedback.selectionClick();
    final topArtistStr = _data.topArtists.take(3).map((a) => a.name).join(', ');
    final topTrackStr = _data.topTracks.take(3).map((t) => t.title).join(', ');

    final summary =
        '''
✨ My DilSe Music Capsule ✨
🎵 Total Minutes: ${_data.totalMinutes} mins (${_data.totalStreams} streams)
👑 Top Artists: $topArtistStr
🔥 Top Songs: $topTrackStr
🌙 Sonic Identity: ${_data.personaEmoji} ${_data.personaTitle}
📻 Streamed 100% privately on DilSe Music • Suno Dil Se
''';

    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Capsule summary copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E28),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeTokens.oledBackground,
      body: Stack(
        children: [
          // Dynamic Ambient Mesh Background
          _buildAnimatedBackground(),

          // Celebratory Confetti & Particle Layer
          _buildConfettiOverlay(),

          // Slide Content with Tap Detection
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => _pauseProgress(),
            onLongPressEnd: (_) => _resumeProgress(),
            onTapUp: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.localPosition.dx < screenWidth * 0.32) {
                _previousSlide();
              } else {
                _advanceSlide();
              }
            },
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Top Story Segment Progress Bars
                  _buildStoryProgressHeader(),

                  const SizedBox(height: 12),
                  // App Title & Close Button
                  _buildTopBar(),

                  // Active Slide View
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSlideContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF1DB954),
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'DILSE CAPSULE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '100% On-Device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStoryProgressHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(_totalSlides, (index) {
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) {
                  double fill = 0.0;
                  if (index < _currentSlide) {
                    fill = 1.0;
                  } else if (index == _currentSlide) {
                    fill = _progressController.value;
                  }
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fill,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.5),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    final colorsBySlide = [
      [
        const Color(0xFF6A0DAD),
        const Color(0xFFE91E63),
        const Color(0xFF0F0C29),
      ],
      [
        const Color(0xFF1DB954),
        const Color(0xFF0D47A1),
        const Color(0xFF0B0B14),
      ],
      [
        const Color(0xFFFF5722),
        const Color(0xFF7B1FA2),
        const Color(0xFF140727),
      ],
      [
        const Color(0xFF00B4D8),
        const Color(0xFF7209B7),
        const Color(0xFF080D21),
      ],
      [
        const Color(0xFF4A148C),
        const Color(0xFF880E4F),
        const Color(0xFF090A0F),
      ],
    ];

    final currentColors = colorsBySlide[_currentSlide % colorsBySlide.length];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: currentColors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildSlideContent() {
    switch (_currentSlide) {
      case 0:
        return _buildSlide0Intro();
      case 1:
        return _buildSlide1TopTracks();
      case 2:
        return _buildSlide2TopArtists();
      case 3:
        return _buildSlide3Persona();
      case 4:
        return _buildSlide4GrandCard();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── SLIDE 0: INTRO ODYSSEY ───────────────────────────────────────────────
  Widget _buildSlide0Intro() {
    final name = _prefs.userName;
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE040FB), Color(0xFF00E5FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE040FB).withValues(alpha: 0.5),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.headphones_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              ),
            ),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE040FB), Color(0xFF00E5FF)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE040FB).withValues(alpha: 0.45),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '2026 CELEBRATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'YOUR 2026 SOUNDSCAPE',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name.isNotEmpty
                  ? '$name, You Listened Deeply.'
                  : 'You Listened Deeply.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 10,
              children: [
                _buildStatPill(
                  title: '${_data.totalMinutes}',
                  label: 'MINUTES',
                  icon: Icons.timer_outlined,
                ),
                _buildStatPill(
                  title: '${_data.totalStreams}',
                  label: 'STREAMS',
                  icon: Icons.play_arrow_rounded,
                ),
              ],
            ),
            const SizedBox(height: 36),
            Text(
              'Tap anywhere on the right to continue →',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill({
    required String title,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE040FB).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ─── SLIDE 1: TOP TRACKS ──────────────────────────────────────────────────
  Widget _buildSlide1TopTracks() {
    final top = _data.topTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          'ON REPEAT',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your Top Tracks',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 16),
        if (top.isNotEmpty) ...[
          // #1 Spotlight
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1DB954).withValues(alpha: 0.28),
                  const Color(0xFFFFD700).withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF1DB954).withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.25),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: top.first.thumbnail.isNotEmpty
                      ? Image.network(
                          top.first.thumbnail,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _fallbackArtwork(),
                        )
                      : _fallbackArtwork(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.black,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '#1 MOST PLAYED',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        top.first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        top.first.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Tracks 2-5
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: top.length > 1 ? top.length - 1 : 0,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final track = top[idx + 1];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '#${idx + 2}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: track.thumbnail.isNotEmpty
                            ? Image.network(
                                track.thumbnail,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _fallbackArtwork(size: 40),
                              )
                            : _fallbackArtwork(size: 40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              track.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${track.playCount} plays',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else ...[
          const Expanded(
            child: Center(
              child: Text(
                'Play tracks to see your top songs ranked here!',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── SLIDE 2: TOP ARTISTS ─────────────────────────────────────────────────
  Widget _buildSlide2TopArtists() {
    final artists = _data.topArtists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          'THE SOUNDMAKERS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Artists Who Moved You',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 16),
        if (artists.isNotEmpty) ...[
          // Lead Artist Spotlight
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF4081).withValues(alpha: 0.32),
                  const Color(0xFFFF9100).withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF4081).withValues(alpha: 0.7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4081).withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF5252), Color(0xFFFF4081)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFF80AB),
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'YOUR #1 ARTIST',
                              style: TextStyle(
                                color: Color(0xFFFF80AB),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artists.first.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${artists.first.percentage}% of your listening',
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
          ),
          const SizedBox(height: 14),
          // Other Top Artists
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: artists.length > 1 ? artists.length - 1 : 0,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = artists[i + 1];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '#${i + 2}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          a.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${a.percentage}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else ...[
          const Expanded(
            child: Center(
              child: Text(
                'Stream music to discover your artist affinity!',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── SLIDE 3: PERSONA & ACOUSTIC IDENTITY ─────────────────────────────────
  Widget _buildSlide3Persona() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _data.personaEmoji,
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'YOUR LISTENING PERSONA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _data.personaTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _data.personaDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    color: Colors.white70,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Peak Hours: ${_data.peakTimeDescription}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Vibe Breakdown
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _data.vibeScores.entries.map((e) {
                final pct = (e.value * 100).round();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        e.key,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SLIDE 4: GRAND SHAREABLE CARD ────────────────────────────────────────
  Widget _buildSlide4GrandCard() {
    return Column(
      children: [
        const SizedBox(height: 6),
        // Card Wrapped in RepaintBoundary for PNG capture
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: RepaintBoundary(
                key: _cardKey,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131F).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Branding & Avatar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFE040FB),
                                        Color(0xFF1DB954),
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'DilSe Music',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        _prefs.userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1DB954), Color(0xFF00E5FF)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1DB954,
                                  ).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.black,
                                  size: 11,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '2026 CAPSULE',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // Persona Badge
                      Row(
                        children: [
                          Text(
                            _data.personaEmoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _data.personaTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${_data.totalMinutes} Mins',
                            style: const TextStyle(
                              color: Color(0xFF1DB954),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Top 3 Artists
                      const Text(
                        'TOP ARTISTS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      if (_data.topArtists.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'Exploring new rhythms...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        ..._data.topArtists
                            .take(3)
                            .map(
                              (a) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        a.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${a.percentage}%',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      const SizedBox(height: 10),

                      // Top 3 Tracks
                      const Text(
                        'TOP SONGS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      if (_data.topTracks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'First tracks incoming...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        ..._data.topTracks
                            .take(3)
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${t.playCount}x',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      const SizedBox(height: 14),

                      // Watermark footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Suno Dil Se • 100% Private',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 13,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),
        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: _isSavingImage
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Save Card',
                    maxLines: 1,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
                onPressed: _isSavingImage ? null : _saveCardImage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Copy Text',
                    maxLines: 1,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _copySummaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: TextButton.icon(
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.white70,
              size: 16,
            ),
            label: const Text(
              'Finish & Close',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _fallbackArtwork({double size = 64}) {
    return Container(
      width: size,
      height: size,
      color: Colors.white12,
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white38),
      ),
    );
  }

  Widget _buildConfettiOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _progressController,
          builder: (context, _) {
            return CustomPaint(
              painter: _FestiveConfettiPainter(
                progress: _progressController.value,
                particles: _particles,
              ),
            );
          },
        ),
      ),
    );
  }

  static const List<_CapsuleParticle> _particles = [
    _CapsuleParticle(
      x: 0.12,
      yOffset: 0.05,
      speed: 0.7,
      size: 7,
      sway: 1.2,
      color: Color(0xFFFFD700),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.28,
      yOffset: 0.22,
      speed: 0.9,
      size: 5,
      sway: 0.8,
      color: Color(0xFFFA2D48),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.45,
      yOffset: 0.15,
      speed: 0.6,
      size: 8,
      sway: 1.5,
      color: Color(0xFF00E5FF),
      shape: 2,
    ),
    _CapsuleParticle(
      x: 0.62,
      yOffset: 0.35,
      speed: 1.1,
      size: 6,
      sway: 0.9,
      color: Color(0xFFE040FB),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.78,
      yOffset: 0.10,
      speed: 0.8,
      size: 7,
      sway: 1.1,
      color: Color(0xFF1DB954),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.90,
      yOffset: 0.45,
      speed: 0.7,
      size: 5,
      sway: 1.4,
      color: Color(0xFFFF9100),
      shape: 2,
    ),
    _CapsuleParticle(
      x: 0.06,
      yOffset: 0.60,
      speed: 1.0,
      size: 6,
      sway: 0.7,
      color: Color(0xFFFA2D48),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.22,
      yOffset: 0.50,
      speed: 0.8,
      size: 8,
      sway: 1.3,
      color: Color(0xFFFFD700),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.38,
      yOffset: 0.75,
      speed: 0.5,
      size: 5,
      sway: 1.0,
      color: Color(0xFF00E5FF),
      shape: 2,
    ),
    _CapsuleParticle(
      x: 0.54,
      yOffset: 0.65,
      speed: 0.9,
      size: 7,
      sway: 1.2,
      color: Color(0xFFE040FB),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.71,
      yOffset: 0.80,
      speed: 0.7,
      size: 6,
      sway: 0.8,
      color: Color(0xFF1DB954),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.85,
      yOffset: 0.70,
      speed: 1.2,
      size: 5,
      sway: 1.6,
      color: Color(0xFFFF9100),
      shape: 2,
    ),
    _CapsuleParticle(
      x: 0.18,
      yOffset: 0.85,
      speed: 0.6,
      size: 7,
      sway: 1.1,
      color: Color(0xFFFFD700),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.33,
      yOffset: 0.40,
      speed: 1.0,
      size: 5,
      sway: 0.9,
      color: Color(0xFFFA2D48),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.50,
      yOffset: 0.90,
      speed: 0.8,
      size: 8,
      sway: 1.4,
      color: Color(0xFF00E5FF),
      shape: 2,
    ),
    _CapsuleParticle(
      x: 0.67,
      yOffset: 0.25,
      speed: 0.7,
      size: 6,
      sway: 1.0,
      color: Color(0xFFE040FB),
      shape: 0,
    ),
    _CapsuleParticle(
      x: 0.82,
      yOffset: 0.95,
      speed: 1.1,
      size: 7,
      sway: 1.3,
      color: Color(0xFF1DB954),
      shape: 1,
    ),
    _CapsuleParticle(
      x: 0.95,
      yOffset: 0.18,
      speed: 0.8,
      size: 5,
      sway: 0.7,
      color: Color(0xFFFF9100),
      shape: 2,
    ),
  ];
}

class _CapsuleParticle {
  final double x;
  final double yOffset;
  final double speed;
  final double size;
  final double sway;
  final Color color;
  final int shape; // 0: rect, 1: circle, 2: strip

  const _CapsuleParticle({
    required this.x,
    required this.yOffset,
    required this.speed,
    required this.size,
    required this.sway,
    required this.color,
    required this.shape,
  });
}

class _FestiveConfettiPainter extends CustomPainter {
  final double progress;
  final List<_CapsuleParticle> particles;

  const _FestiveConfettiPainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final yNorm = (p.yOffset + progress * p.speed) % 1.0;
      final y = yNorm * size.height;
      final xNorm =
          (p.x + 0.05 * math.sin((progress * 4.0 + p.yOffset * 10.0) * p.sway))
              .clamp(0.02, 0.98);
      final x = xNorm * size.width;

      final paint = Paint()
        ..color = p.color.withValues(alpha: 0.65)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      final angle = (progress * 6.0 + p.yOffset * 5.0) * p.sway;
      canvas.rotate(angle);

      if (p.shape == 0) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          paint,
        );
      } else if (p.shape == 1) {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.4,
              height: p.size * 0.4,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FestiveConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
