import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WaveformScrubber extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final String songId;
  final Color accentColor;
  final ValueChanged<Duration> onSeek;

  final bool showTimestamps;
  final double height;

  const WaveformScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.songId,
    required this.accentColor,
    required this.onSeek,
    this.showTimestamps = true,
    this.height = 44.0,
  });

  @override
  State<WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<WaveformScrubber> {
  double? _dragProgress;
  bool _isDragging = false;
  late List<double> _waveformHeights;

  @override
  void initState() {
    super.initState();
    _generateWaveform();
  }

  @override
  void didUpdateWidget(covariant WaveformScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _generateWaveform();
    }
  }

  void _generateWaveform() {
    // Generate deterministic pleasing acoustic waveform heights based on songId seed
    final seed = widget.songId.hashCode;
    final random = math.Random(seed);
    const int count = 48;
    _waveformHeights = List.generate(count, (i) {
      // Natural music waveform envelope (higher in the middle, varied beats)
      final envelope = math.sin((i / count) * math.pi);
      final noise = 0.25 + (random.nextDouble() * 0.75);
      return (0.2 + (envelope * noise * 0.8)).clamp(0.18, 1.0);
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final nonNegative = duration.isNegative ? Duration.zero : duration;
    final hours = nonNegative.inHours;
    final minutes = nonNegative.inMinutes.remainder(60);
    final seconds = (nonNegative.inSeconds.remainder(
      60,
    )).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _handleSeek(double localDx, double width) {
    if (widget.duration.inMilliseconds <= 0 || width <= 0) return;
    final progress = (localDx / width).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = progress;
    });
  }

  void _commitSeek() {
    if (_dragProgress != null && widget.duration.inMilliseconds > 0) {
      final seekMs = (_dragProgress! * widget.duration.inMilliseconds).round();
      widget.onSeek(Duration(milliseconds: seekMs));
      HapticFeedback.selectionClick();
    }
    setState(() {
      _isDragging = false;
      _dragProgress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final bool hasValidDuration = totalMs > 0;
    final currentMs = widget.position.inMilliseconds;
    final liveProgress = hasValidDuration
        ? (currentMs / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final activeProgress = hasValidDuration
        ? (_dragProgress ?? liveProgress)
        : 0.0;

    final displayPosition = _dragProgress != null && hasValidDuration
        ? Duration(milliseconds: (_dragProgress! * totalMs).round())
        : widget.position;
    final remaining = hasValidDuration && widget.duration > displayPosition
        ? widget.duration - displayPosition
        : Duration.zero;

    final waveformTrack = LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: hasValidDuration
              ? (details) {
                  _isDragging = true;
                  _handleSeek(details.localPosition.dx, trackWidth);
                  HapticFeedback.lightImpact();
                }
              : null,
          onHorizontalDragUpdate: hasValidDuration
              ? (details) {
                  _handleSeek(details.localPosition.dx, trackWidth);
                }
              : null,
          onHorizontalDragEnd: hasValidDuration ? (_) => _commitSeek() : null,
          onHorizontalDragCancel: () {
            setState(() {
              _isDragging = false;
              _dragProgress = null;
            });
          },
          onTapDown: hasValidDuration
              ? (details) {
                  _handleSeek(details.localPosition.dx, trackWidth);
                  _commitSeek();
                }
              : null,
          child: Container(
            height: widget.height,
            alignment: Alignment.center,
            child: CustomPaint(
              size: Size(trackWidth, widget.height * 0.9),
              painter: _WaveformPainter(
                waveform: _waveformHeights,
                progress: activeProgress,
                isDragging: _isDragging,
                accentColor: widget.accentColor,
              ),
            ),
          ),
        );
      },
    );

    if (!widget.showTimestamps) {
      return waveformTrack;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        waveformTrack,
        const SizedBox(height: 4),

        // Timestamps with Tabular Numbers (prevents jitter)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPosition),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                hasValidDuration ? '-${_formatDuration(remaining)}' : '--:--',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final bool isDragging;
  final Color accentColor;

  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.isDragging,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final barCount = waveform.length;
    const barSpacing = 2.4;
    final totalSpacing = (barCount - 1) * barSpacing;
    final barWidth = (size.width - totalSpacing) / barCount;
    final maxHeight = size.height * 0.85;

    final playedPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final unplayedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = (isDragging ? accentColor : Colors.white).withValues(
        alpha: 0.35,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (int i = 0; i < barCount; i++) {
      final barX = i * (barWidth + barSpacing);
      final barHeight = (waveform[i] * maxHeight).clamp(4.0, maxHeight);
      final barY = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      final barProgress = (i + 0.5) / barCount;

      if (barProgress <= progress) {
        if (isDragging) {
          canvas.drawRRect(rect, glowPaint);
        }
        canvas.drawRRect(rect, playedPaint);
      } else {
        canvas.drawRRect(rect, unplayedPaint);
      }
    }

    // Scrubber Playhead Indicator (Sleek luminous pin)
    final headX = (progress * size.width).clamp(0.0, size.width);
    final indicatorPaint = Paint()
      ..color = isDragging ? accentColor : Colors.white
      ..style = PaintingStyle.fill;

    final headGlow = Paint()
      ..color = (isDragging ? accentColor : Colors.white).withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(
      Offset(headX, size.height / 2),
      isDragging ? 6.0 : 4.0,
      headGlow,
    );
    canvas.drawCircle(
      Offset(headX, size.height / 2),
      isDragging ? 5.0 : 3.5,
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.accentColor != accentColor;
  }
}
