import 'package:flutter/foundation.dart';

/// Stub implementation of fullscreen helper for non-web platforms.
class DesktopFullscreenHelper {
  static final ValueNotifier<bool> isFullscreenNotifier = ValueNotifier<bool>(
    false,
  );
  static bool get isFullscreen => false;
  static void init() {}
  static void toggleFullscreen() {}
}
