import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_info.freezed.dart';
part 'device_info.g.dart';

/// GET /api/info.
@freezed
abstract class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    required String deviceId,
    required String name,
    required String fwVersion,
    required String hw,
    required String ip,
    @Default(0) int uptimeS,
    @Default(false) bool hasCamera,

    /// 2 when the board takes the llm, stt and tts blocks. Missing on a
    /// version 1 board, which only knows llm and fish.
    int? configVersion,

    /// Provider kinds per stage, for example stt: [fish, openai_compatible].
    Map<String, List<String>>? providers,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}
