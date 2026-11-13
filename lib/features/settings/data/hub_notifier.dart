import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/result.dart';
import '../../device/data/device_providers.dart';
import '../domain/hub_status.dart';

part 'hub_notifier.g.dart';

/// The board's Orion Hub client. The board scans and pairs on its own task,
/// so after an action this polls every two seconds while the board is busy,
/// and for a few seconds after in case the board had not started yet. The
/// approval code and the result show up without a refresh.
@Riverpod(name: 'hubStatusProvider')
class HubNotifier extends _$HubNotifier {
  Timer? _poll;
  DateTime _watchUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<HubStatus> build() async {
    ref.onDispose(() => _poll?.cancel());
    final status = await _read();
    _schedule(status);
    return status;
  }

  Future<HubStatus> _read() async {
    final api = ref.read(deviceApiProvider);
    return HubStatus.fromBoard((await api.getJson(ApiPaths.hub)).getOrThrow());
  }

  void _schedule(HubStatus status) {
    _poll?.cancel();
    if (!status.busy && DateTime.now().isAfter(_watchUntil)) return;
    _poll = Timer(const Duration(seconds: 2), () async {
      if (!ref.mounted) return;
      try {
        final next = await _read();
        if (!ref.mounted) return;
        state = AsyncData(next);
        _schedule(next);
      } on Object {
        // The board dropped off for a moment: try again on the next tick.
        if (ref.mounted) _schedule(status);
      }
    });
  }

  Future<Result<void>> scan() => _act({'action': 'scan'}, 'scanning');

  /// [url] null pairs with the first hub the board found.
  Future<Result<void>> connect([String? url]) =>
      _act({'action': 'connect', 'url': ?url}, 'pairing');

  Future<Result<void>> forget() => _act({'action': 'forget'}, null);

  Future<Result<void>> _act(Map<String, dynamic> body, String? showing) async {
    final result = await ref
        .read(deviceApiProvider)
        .postJson(ApiPaths.hub, body: body);
    if (result case Err(:final failure)) return Err(failure);
    final current = state.value;
    if (current != null && showing != null) {
      state = AsyncData(current.copyWith(state: showing));
    }
    _watchUntil = DateTime.now().add(const Duration(seconds: 8));
    _schedule(state.value ?? const HubStatus(state: 'none'));
    return const Ok(null);
  }
}
