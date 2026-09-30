import 'package:freezed_annotation/freezed_annotation.dart';

import '../../features/device/domain/device.dart';
import '../../features/providers/domain/fish_config.dart';
import '../../features/providers/domain/llm_provider.dart';
import '../../features/providers/domain/voice_stages.dart';
import '../../features/harness/domain/approval_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// App-side settings. Device settings live on the board, not here.
@freezed
abstract class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    Device? pairedDevice,
    @Default(false) bool reducedMotion,
    @Default(false) bool harnessEnabled,

    /// The board's time zone follows this device's until the user picks one.
    @Default(true) bool timeZoneAuto,

    /// Local copy of the board's pc.approval, for when the board is away.
    @Default(ApprovalMode.ask) ApprovalMode approvalMode,
    String? selectedProviderId,
    @Default(<LlmProvider>[]) List<LlmProvider> providers,
    FishConfig? fish,

    /// Speech to text and text to speech. Null until the user or the board
    /// said anything, which reads as the board's defaults.
    VoiceStages? voiceStages,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  bool get isPaired => pairedDevice != null;
}
