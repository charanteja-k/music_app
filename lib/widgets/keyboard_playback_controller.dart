import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/music_service.dart';

/// Wraps the widget tree with declarative Web & Desktop keyboard playback controls.
///
/// Binds:
/// - [LogicalKeyboardKey.space] -> Toggle Play/Pause
/// - [LogicalKeyboardKey.arrowRight] -> Seek forward (+10 seconds)
/// - [LogicalKeyboardKey.arrowLeft] -> Seek rewind (-10 seconds)
///
/// Strictly guards against hijacking user text input in [TextField] and [EditableText].
class KeyboardPlaybackController extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPlayPause;
  final ValueChanged<Duration>? onSeekRelative;

  const KeyboardPlaybackController({
    super.key,
    required this.child,
    this.onPlayPause,
    this.onSeekRelative,
  });

  static bool isTextInputActive() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    if (context.widget is EditableText) {
      return true;
    }
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }
    if (context.findAncestorWidgetOfExactType<TextField>() != null) {
      return true;
    }
    return false;
  }

  void _onSpace() {
    if (onPlayPause != null) {
      onPlayPause!();
      return;
    }
    final musicService = MusicService();
    if (musicService.currentSong == null) return;
    musicService.togglePlayPause();
  }

  void _onArrowRight() {
    if (onSeekRelative != null) {
      onSeekRelative!(const Duration(seconds: 10));
      return;
    }
    final musicService = MusicService();
    if (musicService.currentSong == null) return;
    musicService.seekRelative(const Duration(seconds: 10));
  }

  void _onArrowLeft() {
    if (onSeekRelative != null) {
      onSeekRelative!(const Duration(seconds: -10));
      return;
    }
    final musicService = MusicService();
    if (musicService.currentSong == null) return;
    musicService.seekRelative(const Duration(seconds: -10));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isTextInputActive()) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      _onSpace();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _onArrowRight();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _onArrowLeft();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(autofocus: true, onKeyEvent: _handleKeyEvent, child: child);
  }
}
