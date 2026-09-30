import 'package:json_annotation/json_annotation.dart';

/// The media keys the harness can press.
@JsonEnum(fieldRename: FieldRename.snake)
enum MediaAction {
  play,
  pause,
  playPause,
  next,
  previous,
  volumeUp,
  volumeDown,
  mute;

  /// Parses what the LLM sends, which is free text more often than not.
  static MediaAction? parse(String raw) {
    final key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return switch (key) {
      'play' => MediaAction.play,
      'pause' => MediaAction.pause,
      'play_pause' || 'toggle' => MediaAction.playPause,
      'next' || 'skip' || 'forward' => MediaAction.next,
      'previous' || 'prev' || 'back' => MediaAction.previous,
      'volume_up' || 'louder' || 'up' => MediaAction.volumeUp,
      'volume_down' || 'quieter' || 'down' => MediaAction.volumeDown,
      'mute' || 'unmute' => MediaAction.mute,
      _ => null,
    };
  }
}
