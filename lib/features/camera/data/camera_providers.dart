import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/use_fakes.dart';
import '../../device/data/device_providers.dart';
import '../domain/camera_frame.dart';
import '../domain/camera_source.dart';
import 'fake_camera_source.dart';
import 'http_camera_source.dart';

part 'camera_providers.g.dart';

@Riverpod(keepAlive: true)
CameraSource cameraSource(Ref ref) {
  if (ref.watch(useFakesProvider)) {
    return FakeCameraSource(loadAsset: _loadAsset);
  }
  return HttpCameraSource(ref.watch(deviceApiProvider));
}

/// Live frames. Auto-disposes, so the stream closes when no view watches it.
@riverpod
Stream<CameraFrame> cameraFrames(Ref ref) =>
    ref.watch(cameraSourceProvider).frames();

Future<Uint8List> _loadAsset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
