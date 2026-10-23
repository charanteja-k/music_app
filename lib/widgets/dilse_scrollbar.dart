import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive, responsive fast-scroller and scrollbar widget for DilSe Music.
///
/// Wraps any scrollable child (e.g. [ListView], [CustomScrollView]) and displays
/// a sleek glassmorphic draggable thumb on the right edge. Supports touch, hold,
/// and vertical drag gestures to immediately seek through large playlists.
class DilSeScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final double topPadding;
  final double bottomPadding;
  final Color thumbColor;
  final Color activeThumbColor;
  final bool showBubble;
  final String Function(double progress, double maxScroll)? bubbleLabelBuilder;

  const DilSeScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.topPadding = 0.0,
    this.bottomPadding = 90.0,
    this.thumbColor = const Color(0x66FFFFFF),
    this.activeThumbColor = const Color(0xFF1DB954),
    this.showBubble = true,
    this.bubbleLabelBuilder,
  });

  @override
  State<DilSeScrollbar> createState() => _DilSeScrollbarState();
}

class _DilSeScrollbarState extends State<DilSeScrollbar>
    with SingleTickerProviderStateMixin {
  ScrollController? _internalController;
  ScrollController get _effectiveController {
    if (widget.controller != null) return widget.controller!;
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary != null && primary.hasClients) return primary;
    return _internalController ??= ScrollController();
  }

  double _scrollProgress = 0.0; // 0.0 to 1.0
  double _maxScrollExtent = 0.0;
  bool _isDragging = false;
  bool _isVisible = false;
  Timer? _fadeTimer;
  int _lastHapticPercent = -1;

  static const double _thumbHeight = 44.0;
  static const double _idleWidth = 4.0;
  static const double _activeWidth = 9.0;
  static const double _touchAreaWidth = 36.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _internalController?.dispose();
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.maxScrollExtent <= 0) {
      if (_isVisible) {
        setState(() {
          _isVisible = false;
          _maxScrollExtent = 0.0;
        });
      }
      return;
    }

    final maxExtent = notification.metrics.maxScrollExtent;
    final currentPixels = notification.metrics.pixels.clamp(0.0, maxExtent);
    final progress = (currentPixels / maxExtent).clamp(0.0, 1.0);

    setState(() {
      _maxScrollExtent = maxExtent;
      _scrollProgress = progress;
      _isVisible = true;
    });

    _resetFadeTimer();
  }

  void _resetFadeTimer() {
    if (_isDragging) return;
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_isDragging) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  void _handleDragStart(DragStartDetails details, double trackHeight) {
    if (_maxScrollExtent <= 0) return;
    _fadeTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _isDragging = true;
      _isVisible = true;
    });
    _updateScrollFromLocalY(details.localPosition.dy, trackHeight);
  }

  void _handleDragUpdate(DragUpdateDetails details, double trackHeight) {
    if (_maxScrollExtent <= 0 || !_isDragging) return;
    _updateScrollFromLocalY(details.localPosition.dy, trackHeight);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    _resetFadeTimer();
  }

  void _handleDragCancel() {
    setState(() {
      _isDragging = false;
    });
    _resetFadeTimer();
  }

  void _updateScrollFromLocalY(double localY, double trackHeight) {
    if (trackHeight <= 0 || _maxScrollExtent <= 0) return;

    final usableHeight = trackHeight - _thumbHeight;
    if (usableHeight <= 0) return;

    final clampedY = (localY - (_thumbHeight / 2)).clamp(0.0, usableHeight);
    final fraction = (clampedY / usableHeight).clamp(0.0, 1.0);
    final targetPixels = fraction * _maxScrollExtent;

    final controller = _effectiveController;
    if (controller.hasClients) {
      controller.jumpTo(targetPixels);
    }

    // Trigger subtle haptic feedback every 10% step
    final currentPercent = (fraction * 10).floor();
    if (currentPercent != _lastHapticPercent) {
      _lastHapticPercent = currentPercent;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _scrollProgress = fraction;
    });
  }

  String _formatBubbleText() {
    if (widget.bubbleLabelBuilder != null) {
      return widget.bubbleLabelBuilder!(_scrollProgress, _maxScrollExtent);
    }
    final percent = (_scrollProgress * 100).round();
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final trackHeight =
            (totalHeight - widget.topPadding - widget.bottomPadding).clamp(
              0.0,
              totalHeight,
            );
        final usableHeight = (trackHeight - _thumbHeight).clamp(
          0.0,
          trackHeight,
        );
        final thumbOffset =
            widget.topPadding + (_scrollProgress * usableHeight);

        return Stack(
          fit: StackFit.passthrough,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _onScrollNotification(notification);
                return false;
              },
              child: widget.child,
            ),

            if (_maxScrollExtent > 0)
              Positioned(
                top: widget.topPadding,
                bottom: widget.bottomPadding,
                right: 0,
                width: _touchAreaWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragDown: (_) {
                    if (_maxScrollExtent > 0) {
                      _fadeTimer?.cancel();
                      setState(() {
                        _isVisible = true;
                      });
                    }
                  },
                  onVerticalDragStart: (details) =>
                      _handleDragStart(details, trackHeight),
                  onVerticalDragUpdate: (details) =>
                      _handleDragUpdate(details, trackHeight),
                  onVerticalDragEnd: _handleDragEnd,
                  onVerticalDragCancel: _handleDragCancel,
                  child: Container(color: Colors.transparent),
                ),
              ),

            if (_maxScrollExtent > 0)
              Positioned(
                top: thumbOffset,
                right: 3,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: (_isVisible || _isDragging) ? 1.0 : 0.0,
                    duration: Duration(milliseconds: _isDragging ? 80 : 250),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.showBubble && _isDragging)
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF181818,
                              ).withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: widget.activeThumbColor.withValues(
                                  alpha: 0.6,
                                ),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              _formatBubbleText(),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),

                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: _isDragging ? _activeWidth : _idleWidth,
                          height: _thumbHeight,
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? widget.activeThumbColor
                                : widget.thumbColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _isDragging
                                ? [
                                    BoxShadow(
                                      color: widget.activeThumbColor.withValues(
                                        alpha: 0.6,
                                      ),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
