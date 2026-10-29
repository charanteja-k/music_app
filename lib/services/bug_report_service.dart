import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show File, Platform;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'music_service.dart';
import 'web_attachment_helper.dart';
import '../widgets/bug_report_sheet.dart';

class _EvidenceZipPayload {
  final List<Uint8List> images;
  final String diagnostics;

  const _EvidenceZipPayload({required this.images, required this.diagnostics});
}

Uint8List _packEvidenceZipSync(_EvidenceZipPayload payload) {
  final archive = Archive();

  // 1. Diagnostics file
  final diagBytes = utf8.encode(payload.diagnostics);
  archive.addFile(ArchiveFile('diagnostics.txt', diagBytes.length, diagBytes));

  // 2. Screenshots & images
  for (int i = 0; i < payload.images.length; i++) {
    final img = payload.images[i];
    final filename = i == 0
        ? 'sentry_viewport.png'
        : 'sentry_attachment_$i.png';
    archive.addFile(ArchiveFile(filename, img.length, img));
  }

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

class BugReportSnapshot {
  final Uint8List? screenshotBytes;
  final Map<String, dynamic> diagnostics;

  const BugReportSnapshot({
    required this.screenshotBytes,
    required this.diagnostics,
  });
}

class BugReportService with WidgetsBindingObserver {
  static final BugReportService instance = BugReportService._internal();
  factory BugReportService() => instance;

  BugReportService._internal();

  final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();
  final GlobalKey repaintBoundaryKey = GlobalKey();
  GlobalKey get rootRepaintBoundaryKey => repaintBoundaryKey;

  static const String prefShakeToReport = 'sentrylens_shake_to_report';

  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  final List<DateTime> _shakeTimestamps = [];
  DateTime? _lastTriggerTime;
  bool _isModalOpen = false;
  bool _shakeEnabled = true;

  bool get isShakeEnabled => _shakeEnabled;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shakeEnabled = prefs.getBool(prefShakeToReport) ?? true;
    } catch (_) {}

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}

    if (_shakeEnabled) {
      startShakeListener();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_shakeEnabled) {
        startShakeListener();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      stopShakeListener();
    }
  }

  Future<void> setShakeEnabled(bool enabled) async {
    _shakeEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefShakeToReport, enabled);
    } catch (_) {}

    if (enabled) {
      startShakeListener();
    } else {
      stopShakeListener();
    }
  }

  void startShakeListener() {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    _accelerometerSub?.cancel();
    _shakeTimestamps.clear();

    try {
      _accelerometerSub = accelerometerEventStream().listen(
        _onAccelerometerEvent,
        onError: (err) {
          debugPrint('[SentryLens] Accelerometer stream error: $err');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[SentryLens] Failed to bind accelerometer: $e');
    }
  }

  void stopShakeListener() {
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _shakeTimestamps.clear();
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_shakeEnabled || _isModalOpen) return;

    final now = DateTime.now();

    // 2.5-second debounce window to prevent repeated trigger loops
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!).inMilliseconds < 2500) {
      return;
    }

    // Magnitude minus gravity: sqrt(x*x + y*y + z*z) - 9.80665
    final netAcceleration =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z) -
        9.80665;

    // Detect directional reversal spikes exceeding 13.5 m/s^2
    if (netAcceleration.abs() >= 13.5) {
      _shakeTimestamps.add(now);

      // Keep only peaks within 1200ms sliding window
      _shakeTimestamps.removeWhere(
        (t) => now.difference(t).inMilliseconds > 1200,
      );

      // Track 3 clean peaks occurring within a 1200ms sliding window
      if (_shakeTimestamps.length >= 3) {
        _lastTriggerTime = now;
        _shakeTimestamps.clear();

        HapticFeedback.mediumImpact();

        final context = rootNavKey.currentContext;
        if (context != null) {
          triggerReport(context);
        }
      }
    }
  }

  Future<Uint8List?> captureActiveViewport() async {
    try {
      final boundary =
          repaintBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[SentryLens] Screenshot capture error: $e');
      return null;
    }
  }

  Future<Uint8List?> captureScreenshot() => captureActiveViewport();

  Future<BugReportSnapshot> captureSnapshotAndContext([
    BuildContext? context,
  ]) async {
    final screenshot = await captureActiveViewport();

    final musicService = MusicService();
    final song = musicService.currentSong;

    String currentRoute = 'unknown_route';
    if (context != null && context.mounted) {
      final route = ModalRoute.of(context);
      currentRoute =
          route?.settings.name ?? context.widget.runtimeType.toString();
    } else {
      final navCtx = rootNavKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        final route = ModalRoute.of(navCtx);
        currentRoute = route?.settings.name ?? 'root_view';
      }
    }

    String osName = 'Web';
    String osVersion = 'Browser';
    if (!kIsWeb) {
      osName = Platform.operatingSystem;
      osVersion = Platform.operatingSystemVersion;
    }

    final audioState = {
      'hasActiveTrack': song != null,
      'trackId': song?.id.value ?? 'none',
      'title': song?.title ?? 'No Track Playing',
      'artist': song?.author ?? 'Unknown Artist',
      'durationSec': musicService.duration?.inSeconds ?? 0,
      'positionSec': musicService.position.inSeconds,
      'activeDeck': musicService.activeDeckName,
      'streamType': musicService.currentStreamType,
      'playbackState': musicService.playbackStateString,
      'isCrossfading': musicService.isCrossfading,
      'isShuffle': musicService.isShuffle,
      'loopMode': musicService.loopMode.toString(),
      'queueLength': musicService.playlist.length,
      'currentIndex': musicService.currentIndex,
    };

    String appVersionStr = '3.9.12+35';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersionStr = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final deviceTelemetry = {
      'os': osName,
      'osVersion': osVersion,
      'appVersion': appVersionStr,
      'currentRoute': currentRoute,
      'capturedAt': DateTime.now().toIso8601String(),
    };

    final recentLogs = MusicService.clientLogRingBuffer.take(20).toList();

    final diagnostics = {
      'audio_state': audioState,
      'device_telemetry': deviceTelemetry,
      'logs': recentLogs,
    };

    return BugReportSnapshot(
      screenshotBytes: screenshot,
      diagnostics: diagnostics,
    );
  }

  Future<void> triggerReport(BuildContext context) async {
    if (_isModalOpen) return;
    _isModalOpen = true;

    try {
      final screenshot = await captureActiveViewport();

      if (!context.mounted) {
        _isModalOpen = false;
        return;
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => BugReportSheet(screenshotBytes: screenshot),
      );
    } finally {
      _isModalOpen = false;
    }
  }

  Future<void> triggerReportModal(BuildContext context) =>
      triggerReport(context);

  static const String maintainerEmail = 'charanteja.kondakalla030206@gmail.com';

  /// Assembles human-readable, plain-text RFC flight telemetry with zero decorative markdown.
  String _assembleFlightTelemetry({
    required String userDescription,
    required MusicService musicService,
    String appVersion = '3.9.12+35',
  }) {
    final song = musicService.currentSong;
    final osName = kIsWeb ? 'Web' : Platform.operatingSystem;
    final osVersion = kIsWeb ? 'Browser' : Platform.operatingSystemVersion;
    final logs = MusicService.clientLogRingBuffer.take(20).toList();

    final buffer = StringBuffer();
    buffer.writeln('DILSE MUSIC BUG REPORT');
    buffer.writeln('');
    buffer.writeln('USER DESCRIPTION:');
    buffer.writeln(userDescription.trim());
    buffer.writeln('');
    buffer.writeln('DEVICE INFORMATION:');
    buffer.writeln('Platform: $osName $osVersion');
    buffer.writeln('App Version: $appVersion');
    buffer.writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('AUDIO PIPELINE:');
    buffer.writeln('Track: ${song?.title ?? "None"}');
    buffer.writeln('Artist: ${song?.author ?? "Unknown"}');
    buffer.writeln('Active Deck: ${musicService.activeDeckName}');
    buffer.writeln('Container: ${musicService.currentStreamType}');
    buffer.writeln('Playing: ${musicService.isPlaying}');
    buffer.writeln('Position: ${musicService.position.inMilliseconds} ms');
    buffer.writeln(
      'Duration: ${musicService.duration?.inMilliseconds ?? 0} ms',
    );
    buffer.writeln('');
    buffer.writeln('RECENT LOGS:');
    if (logs.isEmpty) {
      buffer.writeln('No recent log entries in buffer.');
    } else {
      for (final log in logs) {
        buffer.writeln(log);
      }
    }

    return buffer.toString();
  }

  /// Writes enabled screenshots and visual attachments to ephemeral storage for email sharing.
  Future<List<String>> _stageAttachmentsOnDisk(
    List<Uint8List> attachments,
  ) async {
    if (kIsWeb || attachments.isEmpty) return const [];
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final List<String> stagedPaths = [];

      for (int i = 0; i < attachments.length; i++) {
        final filename = i == 0
            ? 'sentry_viewport_$timestamp.png'
            : 'sentry_attachment_${i}_$timestamp.png';
        final file = File('${tempDir.path}/$filename');
        await file.writeAsBytes(attachments[i], flush: true);
        stagedPaths.add(file.path);
      }
      return stagedPaths;
    } catch (e) {
      debugPrint('[SentryLens] Attachment disk staging error: $e');
      return const [];
    }
  }

  /// Sovereign, client-native diagnostics relay directly to Charan Teja's inbox.
  Future<bool> sendDirectReport({
    required String userDescription,
    List<Uint8List> attachments = const [],
    Uint8List? screenshotBytes,
    Map<String, dynamic>? diagnostics,
  }) async {
    final effectiveAttachments = List<Uint8List>.from(attachments);
    if (effectiveAttachments.isEmpty &&
        screenshotBytes != null &&
        screenshotBytes.isNotEmpty) {
      effectiveAttachments.add(screenshotBytes);
    }

    final words = userDescription
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 8) {
      debugPrint('[SentryLens] Validation failed: Minimum 8-10 words required');
      return false;
    }

    String appVer = '3.9.12+35';
    try {
      final info = await PackageInfo.fromPlatform();
      appVer = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final musicService = MusicService();
    final body = _assembleFlightTelemetry(
      userDescription: userDescription,
      musicService: musicService,
      appVersion: appVer,
    );

    final firstLine = userDescription.trim().split('\n').first;
    final subject =
        'DilSe Bug Report: ${firstLine.length > 50 ? "${firstLine.substring(0, 47)}..." : firstLine}';

    // 1. Web Pipeline: Build & download ZIP archive with viewport + user attachments + diagnostics.txt
    if (kIsWeb) {
      String webBody = body;
      if (effectiveAttachments.isNotEmpty) {
        try {
          final zipBytes = await compute(
            _packEvidenceZipSync,
            _EvidenceZipPayload(
              images: effectiveAttachments,
              diagnostics: body,
            ),
          );
          downloadBlobWeb(zipBytes, 'dilse_bug_report_evidence.zip');
          webBody =
              '$body\n\nNOTE: Visual evidence has been downloaded as \'dilse_bug_report_evidence.zip\'. Please attach it to this email.';
        } catch (e) {
          debugPrint('[SentryLens] Web evidence archive bundling error: $e');
        }
      }

      final mailtoUri = Uri(
        scheme: 'mailto',
        path: maintainerEmail,
        queryParameters: {'subject': subject, 'body': webBody},
      );

      bool launched = false;
      try {
        launched = await launchUrl(
          mailtoUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        debugPrint('[SentryLens] Web mailto launcher failed: $e');
      }

      // Direct fallback targeting Gmail web composer if mailto protocol is unhandled
      if (!launched) {
        try {
          final gmailUri = Uri.https('mail.google.com', '/mail/', {
            'view': 'cm',
            'fs': '1',
            'to': maintainerEmail,
            'su': subject,
            'body': webBody,
          });
          launched = await launchUrl(
            gmailUri,
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint('[SentryLens] Webmail Gmail fallback launcher failed: $e');
        }
      }
      return launched;
    }

    // 2. Native Path Preparation (Android & iOS)
    final List<String> attachmentPaths = await _stageAttachmentsOnDisk(
      effectiveAttachments,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final Email email = Email(
          body: body,
          subject: subject,
          recipients: [maintainerEmail],
          attachmentPaths: attachmentPaths,
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        return true;
      } catch (e) {
        debugPrint(
          '[SentryLens] Native email intent threw, falling back to RFC mailto: $e',
        );
      }
    }

    // 3. Native Desktop / Exception Failover: Clean Uri with queryParameters (never manual string interpolation)
    try {
      final mailtoUri = Uri(
        scheme: 'mailto',
        path: maintainerEmail,
        queryParameters: {'subject': subject, 'body': body},
      );

      final launched = await launchUrl(
        mailtoUri,
        mode: LaunchMode.externalApplication,
      );
      return launched;
    } catch (e) {
      debugPrint('[SentryLens] Fallback mailto launcher failed: $e');
      return false;
    }
  }

  /// Backward-compatible alias for sendDirectReport.
  Future<bool> submitBugReport({
    required String userDescription,
    List<Uint8List> attachments = const [],
    Uint8List? screenshotBytes,
    Map<String, dynamic>? diagnostics,
  }) => sendDirectReport(
    userDescription: userDescription,
    attachments: attachments,
    screenshotBytes: screenshotBytes,
    diagnostics: diagnostics,
  );
}
