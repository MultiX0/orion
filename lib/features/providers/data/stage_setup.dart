import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../device/domain/device_config.dart';
import '../domain/board_config_repository.dart';
import '../domain/provider_presets.dart';
import '../domain/voice_presets.dart';
import '../domain/voice_stages.dart';
import 'board_config_providers.dart';
import 'providers_config_notifier.dart';
import 'stage_blocks.dart';

part 'stage_setup.freezed.dart';
part 'stage_setup.g.dart';

/// The three stages of a turn: the language model, speech to text and text
/// to speech.
abstract final class Stage {
  static const llm = 'llm';
  static const stt = 'stt';
  static const tts = 'tts';
  static const all = [llm, stt, tts];
}

@freezed
abstract class StageSendState with _$StageSendState {
  const factory StageSendState({
    @Default(false) bool busy,
    ConfigRoute? route,
    Failure? error,

    /// Nothing was different from what the board already has.
    @Default(false) bool nothingToSend,
  }) = _StageSendState;
}

/// The user's voice picks, persisted without keys.
@Riverpod(keepAlive: true)
VoiceStages voiceStages(Ref ref) => ref.watch(
  appSettingsProvider.select(
    (s) => s.value?.voiceStages ?? const VoiceStages(),
  ),
);

/// Builds the blocks, knows which changed, and sends them.
@Riverpod(keepAlive: true)
class StageSetup extends _$StageSetup {
  /// Key ids the user typed a key for since the last send.
  final _touched = <String>{};

  /// What the board has, per stage, keys left out. Empty until a send or a
  /// read of the board, which makes every block count as changed.
  final _board = <String, Map<String, dynamic>>{};

  @override
  StageSendState build() => const StageSendState();

  Future<void> setStt(StageChoice choice) => ref
      .read(appSettingsProvider.notifier)
      .edit(
        (s) => s.copyWith(
          voiceStages: (s.voiceStages ?? const VoiceStages()).copyWith(
            stt: choice,
          ),
        ),
      );

  Future<void> setTts(StageChoice choice) => ref
      .read(appSettingsProvider.notifier)
      .edit(
        (s) => s.copyWith(
          voiceStages: (s.voiceStages ?? const VoiceStages()).copyWith(
            tts: choice,
          ),
        ),
      );

  /// Stores a key the user typed and marks it for the next send.
  Future<void> storeKey(String keyId, String key) async {
    await ref.read(secretStoreProvider).write(_secretFor(keyId), key);
    _touched.add(keyId);
  }

  Future<bool> hasKey(String keyId) async {
    final key = await ref.read(secretStoreProvider).read(_secretFor(keyId));
    return key != null && key.isNotEmpty;
  }

  /// Settings reads the board first, so saving sends only what changed.
  Future<void> loadFromBoard() async {
    final got = await ref.read(boardConfigRepositoryProvider).current();
    final config = got.valueOrNull;
    if (config == null) return;
    final json = config.toJson();
    for (final stage in Stage.all) {
      final block = json[stage];
      if (block is Map<String, dynamic>) _board[stage] = withoutKey(block);
    }
  }

  /// Sends the blocks that differ from the board, or only [stages].
  Future<Result<ConfigRoute>> send({List<String> stages = Stage.all}) async {
    if (state.busy) return const Err(DeviceFailure('busy', 'Already sending'));
    state = const StageSendState(busy: true);
    final blocks = (await _blocks()).toJson();
    final patch = <String, dynamic>{};
    for (final stage in stages) {
      final block = blocks[stage];
      if (block is! Map<String, dynamic>) continue;
      final changed = differs(withoutKey(block), _board[stage]);
      final keyTouched =
          _touched.contains(_keyIdFor(stage)) && block['api_key'] != null;
      if (changed || keyTouched) patch[stage] = block;
    }
    if (patch.isEmpty) {
      state = const StageSendState(nothingToSend: true);
      return const Ok(ConfigRoute.lan);
    }
    final sent = await ref
        .read(boardConfigRepositoryProvider)
        .send(DeviceConfig.fromJson(patch));
    if (!ref.mounted) return sent;
    switch (sent) {
      case Ok(:final value):
        for (final MapEntry(:key, :value) in patch.entries) {
          _board[key] = withoutKey(value);
          _touched.remove(_keyIdFor(key));
        }
        state = StageSendState(route: value);
      case Err(:final failure):
        state = StageSendState(error: failure);
    }
    return sent;
  }

  Future<DeviceConfig> _blocks() async {
    final providers = ref.read(providersConfigProvider);
    final llm = providers.selected ?? ProviderPresets.deepinfra;
    final stages = ref.read(voiceStagesProvider);
    final secrets = ref.read(secretStoreProvider);
    Future<String?> key(String keyId) => secrets.read(_secretFor(keyId));
    return stageBlocks(
      llm: llm,
      stages: stages,
      fish: providers.fish,
      keys: (
        llm: await key(llm.id),
        stt: await key(VoicePresets.sttById(stages.stt.presetId).keyId),
        tts: await key(VoicePresets.ttsById(stages.tts.presetId).keyId),
      ),
    );
  }

  String _keyIdFor(String stage) {
    final stages = ref.read(voiceStagesProvider);
    return switch (stage) {
      Stage.stt => VoicePresets.sttById(stages.stt.presetId).keyId,
      Stage.tts => VoicePresets.ttsById(stages.tts.presetId).keyId,
      _ => ref.read(providersConfigProvider).selectedId ?? 'deepinfra',
    };
  }

  static String _secretFor(String keyId) => keyId == VoicePresets.fishKeyId
      ? SecretKeys.fishApiKey
      : SecretKeys.providerApiKey(keyId);
}
