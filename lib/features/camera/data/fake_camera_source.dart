import 'dart:typed_data';

import '../../../core/network/jpeg_info.dart';
import '../../../core/result.dart';
import '../domain/camera_frame.dart';
import '../domain/camera_source.dart';
import 'snapshot_store.dart';

/// Loops the bundled mock frames at a fixed rate. The loader is injected so
/// this file stays free of Flutter; the provider passes rootBundle.
class FakeCameraSource implements CameraSource {
  FakeCameraSource({
    required this.loadAsset,
    this.fps = 10,
    this.frameCount = 8,
    SnapshotStore? snapshots,
  }) : _snapshots = snapshots ?? const SnapshotStore();

  final Future<Uint8List> Function(String path) loadAsset;
  final SnapshotStore _snapshots;
  final int fps;
  final int frameCount;

  List<Uint8List>? _frames;

  @override
  Stream<CameraFrame> frames() async* {
    final frames = await _load();
    var sequence = 0;
    while (true) {
      await Future<void>.delayed(Duration(milliseconds: 1000 ~/ fps));
      yield _frame(frames[sequence % frames.length], sequence);
      sequence++;
    }
  }

  @override
  Future<Result<String>> saveSnapshot(CameraFrame frame) =>
      _snapshots.write(frame.bytes, at: frame.receivedAt);

  @override
  Future<Result<CameraFrame>> capture() async {
    final frames = await _load();
    return Ok(_frame(frames.first, 0));
  }

  static CameraFrame _frame(Uint8List bytes, int sequence) {
    final size = JpegInfo.size(bytes);
    return CameraFrame(
      bytes: bytes,
      receivedAt: DateTime.now(),
      sequence: sequence,
      width: size?.$1,
      height: size?.$2,
    );
  }

  Future<List<Uint8List>> _load() async {
    final cached = _frames;
    if (cached != null) return cached;
    final loaded = <Uint8List>[];
    for (var i = 1; i <= frameCount; i++) {
      final name = 'frame_${i.toString().padLeft(2, '0')}.jpg';
      loaded.add(await loadAsset('tool/mock_device/frames/$name'));
    }
    return _frames = loaded;
  }
}
