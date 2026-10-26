import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bug_report_service.dart';

class BugReportButton extends StatefulWidget {
  final Color? iconColor;
  final double size;

  const BugReportButton({super.key, this.iconColor, this.size = 38.0});

  @override
  State<BugReportButton> createState() => _BugReportButtonState();
}

class _BugReportButtonState extends State<BugReportButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        BugReportService.instance.triggerReport(context);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.bug_report_rounded,
                  size: 20,
                  color: widget.iconColor ?? Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
