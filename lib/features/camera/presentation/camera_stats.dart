import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/camera_providers.dart';

part 'camera_stats.freezed.dart';
part 'camera_stats.g.dart';

@freezed
abstract class CameraStatsState with _$CameraStatsState {
  const factory CameraStatsState({
    @Default(0) int fps,
    int? width,
    int? height,
  }) = _CameraStatsState;
}

/// Counts frames and publishes fps once a second, so the overlay never
/// rebuilds per frame. Resolution comes with each frame from the parser
/// and only touches state when it changes.
@riverpod
class CameraStats extends _$CameraStats {
  var _count = 0;

  @override
  CameraStatsState build() {
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(fps: _count);
      _count = 0;
    });
    ref.onDispose(timer.cancel);
    ref.listen(cameraFramesProvider, (_, next) {
      final frame = next.value;
      if (frame == null) return;
      _count++;
      final w = frame.width;
      final h = frame.height;
      if (w != null && h != null && (w != state.width || h != state.height)) {
        state = state.copyWith(width: w, height: h);
      }
    });
    return const CameraStatsState();
  }
}
