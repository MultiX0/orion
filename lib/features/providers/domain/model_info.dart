import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_info.freezed.dart';
part 'model_info.g.dart';

/// One entry from a provider's model list. Nulls mean the provider did not say.
@freezed
abstract class ModelInfo with _$ModelInfo {
  const factory ModelInfo({
    /// Exactly what goes into the "model" field of a request.
    required String id,
    String? displayName,
    int? contextLength,
    bool? supportsVision,
    bool? supportsTools,

    /// A text generation model. False for embeddings, speech, images.
    bool? supportsChat,

    /// Turns audio into text, for the listening stage.
    bool? supportsSpeechToText,

    /// Turns text into audio, for the speaking stage.
    bool? supportsTextToSpeech,
  }) = _ModelInfo;

  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      _$ModelInfoFromJson(json);
}
