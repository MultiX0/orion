import 'package:freezed_annotation/freezed_annotation.dart';

part 'fish_config.freezed.dart';
part 'fish_config.g.dart';

/// Fish Audio settings, also the fish block of the board config.
@freezed
abstract class FishConfig with _$FishConfig {
  const factory FishConfig({
    String? apiKey,
    String? voiceId,

    /// Fish Drama 3, paid: it needs API credit on the Fish account.
    /// s2.1-pro is the faster paid one; s2.1-pro-free costs nothing.
    @Default('drama-3') String ttsModel,
  }) = _FishConfig;

  factory FishConfig.fromJson(Map<String, dynamic> json) =>
      _$FishConfigFromJson(json);

  static const ttsModels = [
    'drama-3',
    's2.1-pro',
    's2.1-pro-free',
    's2-pro',
    's1',
  ];
}
