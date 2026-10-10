import 'dart:async';
import 'dart:io' show InternetAddress, SocketException, Platform;
import 'package:flutter/foundation.dart';

/// Central observer for internet connectivity and offline status across the application.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOffline = false;
  bool get isOffline => _isOffline;
  bool get isOnline => !_isOffline;

  Timer? _timer;

  void init() {
    if (_timer != null) return;
    checkConnectivity();
    if (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        checkConnectivity();
      });
    }
  }

  @visibleForTesting
  void setOfflineForTesting(bool offline) {
    if (_isOffline != offline) {
      _isOffline = offline;
      notifyListeners();
    }
  }

  Future<void> checkConnectivity() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      final result = await InternetAddress.lookup(
        '1.1.1.1',
      ).timeout(const Duration(seconds: 2));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (_isOffline == online) {
        _isOffline = !online;
        notifyListeners();
      }
    } on SocketException catch (_) {
      if (!_isOffline) {
        _isOffline = true;
        notifyListeners();
      }
    } on TimeoutException catch (_) {
      if (!_isOffline) {
        _isOffline = true;
        notifyListeners();
      }
    } catch (_) {
      // Keep previous state on transient lookup errors
    }
  }

  void disposeService() {
    _timer?.cancel();
    _timer = null;
  }
}
