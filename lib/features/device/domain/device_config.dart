import 'package:freezed_annotation/freezed_annotation.dart';

import '../../providers/domain/fish_config.dart';
import 'llm_config.dart';
import 'stage_config.dart';
import 'pc_config.dart';

part 'device_config.freezed.dart';
part 'device_config.g.dart';

/// GET and POST /api/config. Nullable fields mean "leave as is" on POST.
/// Secrets come back masked, for example "sk-...4f2a".
@freezed
abstract class DeviceConfig with _$DeviceConfig {
  const factory DeviceConfig({
    String? deviceName,
    int? volume,
    bool? wakeWordEnabled,
    String? language,

    /// A POSIX TZ string, "<+03>-3". The board's clock and the time the
    /// model is told follow it.
    String? timeZone,
    LlmConfig? llm,

    /// Config version 2: speech to text and text to speech, each with its
    /// own provider.
    SttConfig? stt,
    TtsConfig? tts,

    /// Config version 1 only. A version 2 board still accepts it in a POST.
    FishConfig? fish,
    PcConfig? pc,
  }) = _DeviceConfig;

  factory DeviceConfig.fromJson(Map<String, dynamic> json) =>
      _$DeviceConfigFromJson(json);
}
