import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web implementation of fullscreen helper using standard package:web.
class DesktopFullscreenHelper {
  static final ValueNotifier<bool> isFullscreenNotifier = ValueNotifier<bool>(
    false,
  );
  static bool _listenerAttached = false;

  static bool get isFullscreen {
    try {
      return web.document.fullscreenElement != null;
    } catch (_) {
      return false;
    }
  }

  static void init() {
    if (_listenerAttached) return;
    _listenerAttached = true;
    try {
      web.document.addEventListener(
        'fullscreenchange',
        ((web.Event _) {
          isFullscreenNotifier.value = isFullscreen;
        }).toJS,
      );
      isFullscreenNotifier.value = isFullscreen;
    } catch (_) {}
  }

  static void toggleFullscreen() {
    try {
      if (web.document.fullscreenElement != null) {
        web.document.exitFullscreen();
      } else {
        web.document.documentElement?.requestFullscreen();
      }
      isFullscreenNotifier.value = isFullscreen;
    } catch (_) {}
  }
}
