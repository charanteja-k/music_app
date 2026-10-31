import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web implementation using native HTML5 Navigator and window events.
bool isWebOnline() {
  try {
    return web.window.navigator.onLine;
  } catch (_) {
    return true;
  }
}

void setupWebConnectivityListeners(void Function(bool isOnline) onChange) {
  try {
    web.window.addEventListener(
      'online',
      ((web.Event _) {
        onChange(true);
      }).toJS,
    );
    web.window.addEventListener(
      'offline',
      ((web.Event _) {
        onChange(false);
      }).toJS,
    );
  } catch (_) {}
}
