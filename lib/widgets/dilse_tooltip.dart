import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Reusable Tooltip component for DilSe Music.
/// Provides desktop/web hover labels and screen-reader accessibility semantics
/// while gracefully avoiding mobile touch gesture conflicts.
class DilSeTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final Duration? waitDuration;
  final Duration? showDuration;
  final bool preferBelow;

  const DilSeTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration,
    this.showDuration,
    this.preferBelow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return child;

    return Semantics(
      label: message,
      button: true,
      child: Tooltip(
        message: message,
        preferBelow: preferBelow,
        waitDuration: waitDuration ?? const Duration(milliseconds: 300),
        showDuration: showDuration ?? const Duration(milliseconds: 1500),
        triggerMode: kIsWeb
            ? TooltipTriggerMode.tap
            : (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS
                  ? TooltipTriggerMode.manual
                  : TooltipTriggerMode.tap),
        child: child,
      ),
    );
  }
}
