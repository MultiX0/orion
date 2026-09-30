import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/result.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../device/domain/device.dart';
import '../../../providers/data/stage_setup.dart';
import '../../data/bluetooth_providers.dart';
import '../../domain/board_network.dart';
import '../../domain/join_status.dart';
import '../../domain/nearby_board.dart';
import '../../domain/provisioning_repository.dart';

part 'bluetooth_setup.freezed.dart';
part 'bluetooth_setup.g.dart';

/// The stations of the Bluetooth path, in order.
enum SetupStage { nearby, code, config, networks, password, joining, done }

@freezed
abstract class BluetoothSetupState with _$BluetoothSetupState {
  const factory BluetoothSetupState({
    @Default(SetupStage.nearby) SetupStage stage,
    NearbyBoard? board,
    @Default(false) bool busy,

    /// The last thing that went wrong outside the join itself.
    Failure? error,
    @Default(<BoardNetwork>[]) List<BoardNetwork> networks,
    @Default(false) bool networksLoaded,

    /// The chosen network. Null with [hidden] until the user types one.
    String? ssid,
    @Default(true) bool secured,
    @Default(false) bool hidden,

    /// The board's live report while it joins.
    JoinStatus? join,

    /// Joined; now looking for it on the LAN.
    @Default(false) bool handingOver,
    Device? device,
    @Default(false) bool foundOnLan,
  }) = _BluetoothSetupState;
}

/// Boards in setup mode nearby. Auto-disposes, so leaving the list stops
/// the scan and frees the radio for the connection.
@riverpod
Stream<List<NearbyBoard>> nearbyBoards(Ref ref) =>
    ref.watch(provisioningRepositoryProvider).findBoards();

/// Walks one board from nearby to on the network. The code and password
/// stay in memory only, for a retry after the link drops.
@riverpod
class BluetoothSetup extends _$BluetoothSetup {
  StreamSubscription<JoinStatus>? _watch;
  String? _code;
  String _password = '';
  bool _paired = false;
  String? _deviceId;

  @override
  BluetoothSetupState build() {
    final repo = ref.watch(provisioningRepositoryProvider);
    ref.onDispose(() {
      _watch?.cancel();
      unawaited(repo.disconnect());
    });
    return const BluetoothSetupState();
  }

  void pickBoard(NearbyBoard board) =>
      state = BluetoothSetupState(stage: SetupStage.code, board: board);

  Future<void> submitCode(String code) async {
    final board = state.board;
    if (board == null || state.busy) return;
    state = state.copyWith(busy: true, error: null);
    final result = await _repo.connect(board, code: code);
    if (!ref.mounted) return;
    switch (result) {
      case Err(:final failure):
        state = state.copyWith(busy: false, error: failure);
      case Ok():
        _code = code.trim();
        _paired = false;
        // Pair now, so orion-config can follow on the same session.
        final name = ref.read(pairedDeviceProvider)?.name ?? 'Orion';
        final paired = await _repo.pair(deviceName: name);
        if (!ref.mounted) return;
        if (paired case Err(:final failure)) {
          state = state.copyWith(busy: false, error: failure);
          return;
        }
        _deviceId = paired.valueOrNull;
        _paired = true;
        state = state.copyWith(busy: false, stage: SetupStage.config);
    }
  }

  /// Brain and voice over the encrypted session, then the networks.
  Future<void> sendConfig() async {
    final sent = await ref.read(stageSetupProvider.notifier).send();
    if (!ref.mounted || sent.isErr) return;
    await toNetworks();
  }

  Future<void> toNetworks() async {
    state = state.copyWith(stage: SetupStage.networks, error: null);
    await loadNetworks();
  }

  Future<void> loadNetworks() async {
    state = state.copyWith(busy: true, error: null);
    final result = await _repo.scanNetworks();
    if (!ref.mounted) return;
    state = switch (result) {
      Ok(:final value) => state.copyWith(
        busy: false,
        networks: value,
        networksLoaded: true,
      ),
      Err(:final failure) => state.copyWith(busy: false, error: failure),
    };
  }

  void chooseNetwork(BoardNetwork network) => state = state.copyWith(
    stage: SetupStage.password,
    ssid: network.ssid,
    secured: network.secured,
    hidden: false,
    error: null,
  );

  void chooseHidden() => state = state.copyWith(
    stage: SetupStage.password,
    ssid: null,
    secured: true,
    hidden: true,
    error: null,
  );

  /// Pair if this session has not yet, send the network, then follow the
  /// board's report. The password is kept only for a retry.
  Future<void> join({required String ssid, required String password}) async {
    if (state.busy) return;
    if (ssid.trim().isEmpty) {
      state = state.copyWith(
        error: const DeviceFailure('bad_ssid', 'Type the network name first.'),
      );
      return;
    }
    _password = password;
    state = state.copyWith(
      stage: SetupStage.joining,
      ssid: ssid.trim(),
      join: const JoinStatus.connecting(),
      busy: true,
      error: null,
    );
    if (!_paired) {
      final name = ref.read(pairedDeviceProvider)?.name ?? 'Orion';
      final paired = await _repo.pair(deviceName: name);
      if (!ref.mounted) return;
      if (paired case Err(:final failure)) return _stopWith(failure);
      _deviceId = paired.valueOrNull;
      _paired = true;
    }
    final sent = await _repo.sendCredentials(ssid: ssid, password: password);
    if (!ref.mounted) return;
    if (sent case Err(:final failure)) return _stopWith(failure);
    await _watch?.cancel();
    _watch = _repo.watchStatus().listen(_onStatus);
  }

  /// The way back from a failed join depends on what failed.
  Future<void> retry() async {
    final last = state.join;
    if (last is JoinFailed && last.reason == JoinFailure.wrongPassword) {
      state = state.copyWith(stage: SetupStage.password, join: null);
      return;
    }
    if (last is JoinFailed && last.reason == JoinFailure.networkNotFound) {
      state = state.copyWith(stage: SetupStage.networks, join: null);
      await loadNetworks();
      return;
    }
    // Lost the board, timed out, or a failure before the join: open the
    // link again with the same code and run the same network once more.
    final board = state.board;
    final code = _code;
    final ssid = state.ssid;
    if (board == null || code == null || ssid == null) return;
    state = state.copyWith(busy: true, error: null, join: null);
    final reopened = await _repo.connect(board, code: code);
    if (!ref.mounted) return;
    if (reopened case Err(:final failure)) return _stopWith(failure);
    _paired = false;
    state = state.copyWith(busy: false);
    await join(ssid: ssid, password: _password);
  }

  /// One station back. Leaving the code step closes the link.
  void back() {
    switch (state.stage) {
      case SetupStage.nearby:
      case SetupStage.done:
        return;
      case SetupStage.code:
      case SetupStage.config:
      case SetupStage.networks:
        unawaited(_repo.disconnect());
        state = const BluetoothSetupState();
      case SetupStage.password:
        state = state.copyWith(stage: SetupStage.networks, error: null);
      case SetupStage.joining:
        _watch?.cancel();
        state = state.copyWith(
          stage: SetupStage.password,
          join: null,
          busy: false,
        );
    }
  }

  void _stopWith(Failure failure) {
    final lost =
        failure is BluetoothFailure &&
        failure.problem == BluetoothProblem.lostBoard;
    state = state.copyWith(
      busy: false,
      join: lost ? const JoinStatus.failed(JoinFailure.lostBoard) : null,
      error: lost ? null : failure,
    );
  }

  Future<void> _onStatus(JoinStatus status) async {
    state = state.copyWith(join: status);
    if (status is JoinFailed) {
      state = state.copyWith(busy: false);
      return;
    }
    if (status is! JoinConnected) return;
    state = state.copyWith(handingOver: true);
    // The board leaves setup mode on success; the link has done its job.
    await _repo.disconnect();
    final found = await ref
        .read(lanHandoverProvider)
        .find(
          deviceId: _deviceId ?? 'orion-${state.board?.suffix ?? 'board'}',
          ip: status.ip,
          name: ref.read(pairedDeviceProvider)?.name ?? 'Orion',
        );
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      handingOver: false,
      stage: SetupStage.done,
      device: found.device,
      foundOnLan: found.found,
    );
  }

  ProvisioningRepository get _repo => ref.read(provisioningRepositoryProvider);
}
