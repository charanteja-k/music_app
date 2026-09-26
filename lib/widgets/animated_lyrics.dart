import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lyrics_transliteration_service.dart';
import '../services/preferences_service.dart';

enum LyricsDisplayMode {
  original,
  pronunciation,
  dual,
}

class LyricLine {
  final Duration time;
  final String text;
  final String romanizedText;

  LyricLine(this.time, this.text, [this.romanizedText = '']);
}

class AnimatedLyrics extends StatefulWidget {
  final String rawLyrics;
  final Stream<Duration> positionStream;
  final void Function(Duration)? onSeek;

  const AnimatedLyrics({
    super.key,
    required this.rawLyrics,
    required this.positionStream,
    this.onSeek,
  });

  @override
  State<AnimatedLyrics> createState() => _AnimatedLyricsState();
}

class _AnimatedLyricsState extends State<AnimatedLyrics> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  StreamSubscription<Duration>? _positionSubscription;

  List<LyricLine> _lyrics = [];
  bool _isSynced = false;
  bool _hasIndicScript = false;
  int _currentIndex = -1;
  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;

  // Auto-scroll control
  bool _isUserScrolling = false;
  Timer? _userScrollResumeTimer;

  @override
  void initState() {
    super.initState();
    _initDisplayMode();
    _parseLyrics();
    _subscribeToPosition();
  }

  void _initDisplayMode() {
    final saved = PreferencesService().lyricsDisplayMode;
    if (saved == 'pronunciation') {
      _displayMode = LyricsDisplayMode.pronunciation;
    } else if (saved == 'dual') {
      _displayMode = LyricsDisplayMode.dual;
    } else {
      _displayMode = LyricsDisplayMode.original;
    }
  }

  void _subscribeToPosition() {
    _positionSubscription?.cancel();
    _positionSubscription = widget.positionStream.listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Duration position) {
    if (!mounted || !_isSynced || _lyrics.isEmpty) return;

    // Fast binary search for active index
    int activeIndex = -1;
    int low = 0;
    int high = _lyrics.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_lyrics[mid].time <= position) {
        activeIndex = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (activeIndex != _currentIndex) {
      setState(() {
        _currentIndex = activeIndex;
      });
      if (!_isUserScrolling) {
        _scrollToActiveLine(_currentIndex);
      }
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _subscribeToPosition();
    }
    if (oldWidget.rawLyrics != widget.rawLyrics) {
      _lineKeys.clear();
      setState(() {
        _currentIndex = -1;
        _parseLyrics();
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _parseLyrics() {
    _lyrics.clear();
    _lineKeys.clear();
    _isSynced = false;
    _hasIndicScript = false;
    _currentIndex = -1;

    if (widget.rawLyrics.trim().isEmpty) return;

    final lines = widget.rawLyrics.split('\n');
    // Flexible regex matching: [01:23.45], [1:23.456], [01:23:45], [01:23]
    final tagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

    final parsedSynced = <LyricLine>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Ignore LRC header metadata tags: [ar:...], [al:...], [ti:...], [length:...]
      if (RegExp(r'^\[[a-zA-Z]+:.*\]$').hasMatch(line)) continue;

      final matches = tagRegex.allMatches(line);
      if (matches.isNotEmpty) {
        final text = line.replaceAll(tagRegex, '').trim();
        if (text.isEmpty) continue;

        if (!_hasIndicScript && LyricsTransliterationService.hasIndicScript(text)) {
          _hasIndicScript = true;
        }

        final romanized = LyricsTransliterationService.transliterateText(text);

        for (final m in matches) {
          final minutes = int.parse(m.group(1)!);
          final seconds = int.parse(m.group(2)!);
          int milliseconds = 0;
          final msGroup = m.group(3);
          if (msGroup != null) {
            if (msGroup.length == 1) {
              milliseconds = int.parse(msGroup) * 100;
            } else if (msGroup.length == 2) {
              milliseconds = int.parse(msGroup) * 10;
            } else {
              milliseconds = int.parse(msGroup.substring(0, 3));
            }
          }

          final duration = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );
          parsedSynced.add(LyricLine(duration, text, romanized));
        }
      }
    }

    if (parsedSynced.isNotEmpty) {
      _isSynced = true;
      parsedSynced.sort((a, b) => a.time.compareTo(b.time));
      _lyrics = parsedSynced;
    } else {
      // Unsynced Plain Text fallback
      _isSynced = false;
      final cleanRegex = RegExp(r'\[\d+:\d+(?:[.:]\d+)?\]');
      final cleaned = <LyricLine>[];
      bool prevWasEmpty = false;

      for (final rawLine in lines) {
        final line = rawLine.replaceAll(cleanRegex, '').trim();
        if (RegExp(r'^\[[a-zA-Z]+:.*\]$').hasMatch(line)) continue;

        if (line.isEmpty) {
          if (!prevWasEmpty && cleaned.isNotEmpty) {
            cleaned.add(LyricLine(Duration.zero, '', ''));
            prevWasEmpty = true;
          }
        } else {
          if (!_hasIndicScript && LyricsTransliterationService.hasIndicScript(line)) {
            _hasIndicScript = true;
          }
          final romanized = LyricsTransliterationService.transliterateText(line);
          cleaned.add(LyricLine(Duration.zero, line, romanized));
          prevWasEmpty = false;
        }
      }
      _lyrics = cleaned;
    }
  }

  void _scrollToActiveLine(int index) {
    if (_isUserScrolling || index < 0 || index >= _lyrics.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isUserScrolling) return;

      final key = _lineKeys[index];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients) {
        final screenH = MediaQuery.of(context).size.height;
        final targetOffset = (index * 60.0) - (screenH * 0.20);
        final clampedOffset = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);

        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _buildModeToggle(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeButton(
                mode: LyricsDisplayMode.original,
                label: 'Original',
                icon: Icons.language_rounded,
                themeColor: themeColor,
              ),
              const SizedBox(width: 4),
              _buildModeButton(
                mode: LyricsDisplayMode.pronunciation,
                label: 'English',
                icon: Icons.spellcheck_rounded,
                themeColor: themeColor,
              ),
              const SizedBox(width: 4),
              _buildModeButton(
                mode: LyricsDisplayMode.dual,
                label: 'Dual',
                icon: Icons.view_agenda_outlined,
                themeColor: themeColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required LyricsDisplayMode mode,
    required String label,
    required IconData icon,
    required Color themeColor,
  }) {
    final isSelected = _displayMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _displayMode = mode;
        });
        final modeStr = mode == LyricsDisplayMode.pronunciation
            ? 'pronunciation'
            : (mode == LyricsDisplayMode.dual ? 'dual' : 'original');
        PreferencesService().setLyricsDisplayMode(modeStr);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? themeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.white70,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncedLineText(LyricLine item, bool isCurrent, bool isPassed, Color themeColor) {
    final hasRomanized = item.romanizedText.isNotEmpty && item.romanizedText != item.text;

    if (_displayMode == LyricsDisplayMode.dual && hasRomanized) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.text,
            style: TextStyle(
              color: isCurrent
                  ? themeColor
                  : (isPassed ? Colors.white.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.28)),
              fontSize: isCurrent ? 22 : 18.5,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              height: 1.35,
              shadows: isCurrent
                  ? [
                      Shadow(
                        color: themeColor.withValues(alpha: 0.55),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.romanizedText,
            style: TextStyle(
              color: isCurrent
                  ? Colors.white.withValues(alpha: 0.95)
                  : (isPassed ? Colors.white.withValues(alpha: 0.50) : Colors.white.withValues(alpha: 0.20)),
              fontSize: isCurrent ? 16.5 : 14.5,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              fontStyle: FontStyle.italic,
              height: 1.3,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    final lineText = (_displayMode == LyricsDisplayMode.pronunciation && hasRomanized)
        ? item.romanizedText
        : item.text;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        color: isCurrent
            ? themeColor
            : (isPassed ? Colors.white.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.28)),
        fontSize: isCurrent ? 24 : 19.5,
        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
        height: 1.45,
        shadows: isCurrent
            ? [
                Shadow(
                  color: themeColor.withValues(alpha: 0.55),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: Text(lineText),
    );
  }

  Widget _buildUnsyncedLineText(LyricLine item) {
    final hasRomanized = item.romanizedText.isNotEmpty && item.romanizedText != item.text;
    if (_displayMode == LyricsDisplayMode.dual && hasRomanized) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.romanizedText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 15,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    final lineText = (_displayMode == LyricsDisplayMode.pronunciation && hasRomanized)
        ? item.romanizedText
        : item.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        lineText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.55,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInfoMessage = _lyrics.isEmpty ||
        (_lyrics.length <= 2 &&
            _lyrics.any((l) =>
                l.text.toLowerCase().contains('no lyrics') ||
                l.text.toLowerCase().contains('temporarily unavailable')));

    if (isInfoMessage) {
      final msg = _lyrics.isNotEmpty ? _lyrics.first.text : 'No lyrics available for this song';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Icon(Icons.lyrics_outlined, color: Colors.white38, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final themeColor = Theme.of(context).primaryColor;

    // Unsynced Lyrics View
    if (!_isSynced) {
      return Column(
        children: [
          if (_hasIndicScript) _buildModeToggle(themeColor),
          Expanded(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.06, 0.94, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unsynced Lyrics Pill Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notes_rounded, size: 14, color: Colors.white70),
                            SizedBox(width: 6),
                            Text(
                              'Unsynced Lyrics',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...List.generate(_lyrics.length, (idx) {
                      final item = _lyrics[idx];
                      if (item.text.isEmpty) {
                        return const SizedBox(height: 18);
                      }
                      return _buildUnsyncedLineText(item);
                    }),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Synced Lyrics View
    return Column(
      children: [
        if (_hasIndicScript) _buildModeToggle(themeColor),
        Expanded(
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.08, 0.92, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  _isUserScrolling = true;
                  _userScrollResumeTimer?.cancel();
                  _userScrollResumeTimer = Timer(const Duration(seconds: 3), () {
                    if (mounted) {
                      _isUserScrolling = false;
                      _scrollToActiveLine(_currentIndex);
                    }
                  });
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                itemCount: _lyrics.length,
                padding: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.height * 0.20,
                  horizontal: 4,
                ),
                itemBuilder: (context, index) {
                  final isCurrent = index == _currentIndex;
                  final isPassed = index < _currentIndex;
                  final item = _lyrics[index];

                  final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

                  return GestureDetector(
                    key: key,
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onSeek?.call(item.time);
                      _isUserScrolling = false;
                      _scrollToActiveLine(index);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: _buildSyncedLineText(item, isCurrent, isPassed, themeColor),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
