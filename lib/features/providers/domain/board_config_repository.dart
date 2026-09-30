import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/result.dart';
import '../../device/domain/device_config.dart';

part 'board_config_repository.freezed.dart';
part 'board_config_repository.g.dart';

/// How a config reached the board.
enum ConfigRoute {
  /// orion-config on the encrypted setup session.
  bluetooth,

  /// POST /api/config with the token, config version 2.
  lan,

  /// POST /api/config to a board without config_version: only the llm and
  /// fish blocks went, and a non-Fish voice stage could not be sent.
  lanVersion1,
}

/// POST /api/config/test. error is `http_<status>`, timeout or unreachable.
@freezed
abstract class StageTestResult with _$StageTestResult {
  const factory StageTestResult({
    required bool ok,
    int? ms,
    String? error,
    String? message,
  }) = _StageTestResult;

  factory StageTestResult.fromJson(Map<String, dynamic> json) =>
      _$StageTestResultFromJson(json);
}

/// The language model, speech to text and text to speech on the board.
abstract class BoardConfigRepository {
  /// 2 for a board that takes llm, stt and tts; 1 for one that does not
  /// say. Over Bluetooth the board is version 2 by definition.
  Future<Result<int>> configVersion();

  /// GET /api/config, keys masked.
  Future<Result<DeviceConfig>> current();

  /// Over Bluetooth while the setup session is open, else over the LAN.
  /// A version 1 board gets the llm and fish blocks instead.
  Future<Result<ConfigRoute>> send(DeviceConfig patch);

  /// The board makes the smallest real request with what it has stored.
  Future<Result<StageTestResult>> test(String stage);
}
