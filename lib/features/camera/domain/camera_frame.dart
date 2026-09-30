import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'camera_frame.freezed.dart';

/// One JPEG from the board. bytes go straight into Image.memory.
@freezed
abstract class CameraFrame with _$CameraFrame {
  const factory CameraFrame({
    required Uint8List bytes,
    required DateTime receivedAt,
    @Default(0) int sequence,

    /// From the JPEG SOF marker. Null until the parser fills them.
    int? width,
    int? height,
  }) = _CameraFrame;
}
