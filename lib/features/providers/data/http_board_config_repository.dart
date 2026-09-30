import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../device/domain/device_config.dart';
import '../../onboarding/domain/provisioning_repository.dart';
import '../domain/board_config_repository.dart';
import 'version1_config.dart';

/// Sends the stages to the board: over the encrypted setup session when it
/// is open, so keys never cross the LAN in the clear during onboarding,
/// else over the LAN with the token.
class HttpBoardConfigRepository implements BoardConfigRepository {
  HttpBoardConfigRepository({
    required this.api,
    required this.secrets,
    required this.bluetooth,
  });

  final DeviceApi api;
  final SecretStore secrets;
  final ProvisioningRepository bluetooth;

  static const _testPath = '${ApiPaths.config}/test';
  static const busyError = 'busy';

  @override
  Future<Result<int>> configVersion() async {
    if (bluetooth.canSendConfig) return const Ok(2);
    final info = await api.getJson(ApiPaths.info);
    return info.map((json) {
      final version = json['config_version'];
      return version is int ? version : 1;
    });
  }

  @override
  Future<Result<DeviceConfig>> current() async {
    await _token();
    final got = await api.getJson(ApiPaths.config);
    return got.map(DeviceConfig.fromJson);
  }

  @override
  Future<Result<ConfigRoute>> send(DeviceConfig patch) async {
    if (bluetooth.canSendConfig) {
      final sent = await bluetooth.sendConfig(patch.toJson());
      return sent.map((_) => ConfigRoute.bluetooth);
    }
    final version = await configVersion();
    if (version case Err(:final failure)) return Err(failure);
    await _token();
    final v1 = version.valueOrNull == 1;
    final body = v1 ? toVersion1(patch) : patch.toJson();
    final posted = await api.postJson(ApiPaths.config, body: body);
    return posted.map((_) => v1 ? ConfigRoute.lanVersion1 : ConfigRoute.lan);
  }

  @override
  Future<Result<StageTestResult>> test(String stage) async {
    await _token();
    final result = await api.postJson(_testPath, body: {'stage': stage});
    return switch (result) {
      Ok(:final value) when value['ok'] is bool => Ok(
        StageTestResult(
          ok: value['ok'] as bool,
          ms: value['ms'] is int ? value['ms'] as int : null,
          error: value['error'] is String ? value['error'] as String : null,
          message: value['message'] is String
              ? value['message'] as String
              : null,
        ),
      ),
      Ok() => const Err(ParseFailure('The test answer has no "ok"')),
      // 409 busy: the board is in a turn. Not a failure, a wait.
      Err(failure: DeviceFailure(code: 'busy')) => const Ok(
        StageTestResult(ok: false, error: busyError),
      ),
      Err(:final failure) => Err(failure),
    };
  }

  Future<void> _token() async =>
      api.token = await secrets.read(SecretKeys.pairingToken);
}

/// Agrees with everything a moment later. Keys "bad" and "nocredit" fail
/// the way the mock board does.
class FakeBoardConfigRepository implements BoardConfigRepository {
  DeviceConfig stored = const DeviceConfig();

  @override
  Future<Result<int>> configVersion() async => const Ok(2);

  @override
  Future<Result<DeviceConfig>> current() async => Ok(stored);

  @override
  Future<Result<ConfigRoute>> send(DeviceConfig patch) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    stored = stored.copyWith(
      llm: patch.llm ?? stored.llm,
      stt: patch.stt ?? stored.stt,
      tts: patch.tts ?? stored.tts,
    );
    return const Ok(ConfigRoute.lan);
  }

  @override
  Future<Result<StageTestResult>> test(String stage) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final key = switch (stage) {
      'llm' => stored.llm?.apiKey,
      'stt' => stored.stt?.apiKey,
      _ => stored.tts?.apiKey,
    };
    if (key == 'busy') {
      return const Ok(StageTestResult(ok: false, error: 'busy'));
    }
    if (key == 'bad') {
      return const Ok(StageTestResult(ok: false, error: 'http_401'));
    }
    if (stage == 'stt' && key == 'nocredit') {
      return const Ok(StageTestResult(ok: false, error: 'http_402'));
    }
    return const Ok(StageTestResult(ok: true, ms: 412));
  }
}
