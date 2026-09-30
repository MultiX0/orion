import 'package:freezed_annotation/freezed_annotation.dart';

part 'fish_config.freezed.dart';
part 'fish_config.g.dart';

/// Fish Audio settings, also the fish block of the board config.
@freezed
abstract class FishConfig with _$FishConfig {
  const factory FishConfig({
    String? apiKey,
    String? voiceId,

    /// The free tier of the S2.1 Pro engine. The paid s2.1-pro needs API
    /// credit on the Fish account, which a fresh key does not have.
    @Default('s2.1-pro-free') String ttsModel,
  }) = _FishConfig;

  factory FishConfig.fromJson(Map<String, dynamic> json) =>
      _$FishConfigFromJson(json);

  static const ttsModels = ['s2.1-pro-free', 's2.1-pro', 's2-pro', 's1'];
}
