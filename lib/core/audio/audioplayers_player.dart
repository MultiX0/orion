import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;

import 'audio_player.dart';

/// One audioplayers player for the whole app: a Fish preview from bytes, a
/// voice sample from its URL. Starting a clip stops the one before it, so
/// two previews can never talk over each other.
class AudioPlayersPlayer implements AudioPlayer {
  AudioPlayersPlayer({ap.AudioPlayer? player})
    : _player = player ?? ap.AudioPlayer() {
    _states = _player.onPlayerStateChanged.map(
      (state) => state == ap.PlayerState.playing,
    );
  }

  final ap.AudioPlayer _player;
  late final Stream<bool> _states;

  @override
  Stream<bool> get isPlaying => _states;

  @override
  Future<void> playBytes(
    Uint8List bytes, {
    String mimeType = 'audio/mpeg',
  }) async {
    if (bytes.isEmpty) return;
    await stop();
    await _player.play(ap.BytesSource(bytes, mimeType: mimeType));
  }

  @override
  Future<void> playUrl(String url) async {
    if (url.isEmpty) return;
    await stop();
    await _player.play(ap.UrlSource(url));
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } on Object {
      return; // Nothing was playing, or the platform side is already gone.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } on Object {
      return;
    }
  }
}
