import 'dart:typed_data';

/// Plays one clip at a time: a Fish preview from bytes, or a voice sample
/// from its URL. Starting a clip stops the one before it.
abstract class AudioPlayer {
  Future<void> playBytes(Uint8List bytes, {String mimeType = 'audio/mpeg'});
  Future<void> playUrl(String url);
  Future<void> stop();

  /// True while a clip plays, so a button can show it.
  Stream<bool> get isPlaying;

  Future<void> dispose();
}

/// For tests and the fake build, where there is no audio plugin to talk to.
class NullAudioPlayer implements AudioPlayer {
  const NullAudioPlayer();

  @override
  Future<void> playBytes(
    Uint8List bytes, {
    String mimeType = 'audio/mpeg',
  }) async {}

  @override
  Future<void> playUrl(String url) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<bool> get isPlaying => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
