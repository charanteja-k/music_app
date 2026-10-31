import 'dart:async';
import 'dart:io' show InternetAddress, SocketException, Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'web_connectivity_helper.dart';

enum NetworkQuality { good, poor, offline }

/// Central observer for internet connectivity, network quality, and offline status.
///
/// Automatically tracks connection quality (good, poor, offline) across Web,
/// Android, iOS, and Desktop platforms. Emits telemetry events to notify users
/// when bandwidth/latency degrades so they can smoothly transition to offline mode.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOffline = false;
  bool get isOffline => _isOffline;
  bool get isOnline => !_isOffline;

  bool _isLowConnectivity = false;
  bool get isLowConnectivity => _isLowConnectivity;

  NetworkQuality _quality = NetworkQuality.good;
  NetworkQuality get quality => _quality;

  /// Global value notifier for observing quality transitions without rebuilds.
  static final ValueNotifier<NetworkQuality> qualityNotifier =
      ValueNotifier<NetworkQuality>(NetworkQuality.good);

  Timer? _timer;
  bool _isChecking = false;

  void init() {
    if (_timer != null) return;

    if (kIsWeb) {
      if (!isWebOnline()) {
        _isOffline = true;
        _quality = NetworkQuality.offline;
        qualityNotifier.value = NetworkQuality.offline;
      }
      setupWebConnectivityListeners((bool online) {
        if (!online) {
          _updateState(offline: true, low: false, q: NetworkQuality.offline);
        } else {
          _updateState(offline: false, low: false, q: NetworkQuality.good);
          unawaited(checkConnectivity());
        }
      });
    }

    unawaited(checkConnectivity());

    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _timer = Timer.periodic(const Duration(seconds: 12), (_) {
        unawaited(checkConnectivity());
      });
    }
  }

  void _updateState({
    required bool offline,
    required bool low,
    required NetworkQuality q,
  }) {
    if (_isOffline != offline || _isLowConnectivity != low || _quality != q) {
      _isOffline = offline;
      _isLowConnectivity = low;
      _quality = q;
      qualityNotifier.value = q;
      notifyListeners();
    }
  }

  @visibleForTesting
  void setOfflineForTesting(bool offline) {
    _updateState(
      offline: offline,
      low: false,
      q: offline ? NetworkQuality.offline : NetworkQuality.good,
    );
  }

  @visibleForTesting
  void setQualityForTesting(NetworkQuality q) {
    _updateState(
      offline: q == NetworkQuality.offline,
      low: q == NetworkQuality.poor,
      q: q,
    );
  }

  Future<void> checkConnectivity() async {
    if (_isChecking) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    _isChecking = true;
    try {
      if (kIsWeb) {
        if (!isWebOnline()) {
          _updateState(offline: true, low: false, q: NetworkQuality.offline);
          return;
        }

        final stopwatch = Stopwatch()..start();
        try {
          final uri = Uri.base.resolve(
            'favicon.png?t=${DateTime.now().millisecondsSinceEpoch}',
          );
          final response = await http
              .get(uri)
              .timeout(const Duration(milliseconds: 2500));
          stopwatch.stop();

          if (response.statusCode == 200) {
            final elapsed = stopwatch.elapsedMilliseconds;
            if (elapsed > 1800) {
              _updateState(offline: false, low: true, q: NetworkQuality.poor);
            } else {
              _updateState(offline: false, low: false, q: NetworkQuality.good);
            }
          } else {
            _updateState(offline: false, low: true, q: NetworkQuality.poor);
          }
        } catch (_) {
          // If ping timed out or failed while navigator was online, mark as poor/unstable connection
          _updateState(offline: false, low: true, q: NetworkQuality.poor);
        }
        return;
      }

      // Native Mobile / Desktop implementation
      final stopwatch = Stopwatch()..start();
      try {
        final result = await InternetAddress.lookup(
          '1.1.1.1',
        ).timeout(const Duration(milliseconds: 2400));
        stopwatch.stop();

        final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        if (!online) {
          _updateState(offline: true, low: false, q: NetworkQuality.offline);
        } else {
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed > 1800) {
            _updateState(offline: false, low: true, q: NetworkQuality.poor);
          } else {
            _updateState(offline: false, low: false, q: NetworkQuality.good);
          }
        }
      } on SocketException catch (_) {
        _updateState(offline: true, low: false, q: NetworkQuality.offline);
      } on TimeoutException catch (_) {
        // High packet drop / extreme latency
        _updateState(offline: false, low: true, q: NetworkQuality.poor);
      } catch (_) {
        // Transient error
      }
    } finally {
      _isChecking = false;
    }
  }

  void disposeService() {
    _timer?.cancel();
    _timer = null;
  }
}
