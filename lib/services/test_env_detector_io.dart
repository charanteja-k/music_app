import 'dart:io' show Platform;

/// Detects if the current process is running under `flutter test` in VM/native environments.
bool isFlutterTestEnvironment() {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}
