import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../result.dart';

part 'key_check.freezed.dart';
part 'key_check.g.dart';

/// Where a KeyField stands. saved means the check itself is not available
/// yet, so the key was kept as typed.
enum KeyStatus { idle, checking, ok, bad, saved }

@freezed
abstract class KeyCheckState with _$KeyCheckState {
  const factory KeyCheckState({
    @Default(KeyStatus.idle) KeyStatus status,
    String? message,
  }) = _KeyCheckState;
}

/// Runs one key check per field id. The key itself never enters state;
/// only the verdict does.
@riverpod
class KeyCheck extends _$KeyCheck {
  @override
  KeyCheckState build(String id) => const KeyCheckState();

  void reset() => state = const KeyCheckState();

  Future<void> run(
    String key, {
    required Future<Result<void>> Function(String key) check,
    required Future<void> Function(String key) store,
  }) async {
    if (key.isEmpty) {
      state = const KeyCheckState(
        status: KeyStatus.bad,
        message: 'Paste a key first.',
      );
      return;
    }
    state = const KeyCheckState(status: KeyStatus.checking);
    final result = await check(key);
    switch (result) {
      case Ok():
        await store(key);
        state = const KeyCheckState(status: KeyStatus.ok);
      case Err(failure: UnsupportedFailure()):
        await store(key);
        state = const KeyCheckState(status: KeyStatus.saved);
      case Err(:final failure):
        state = KeyCheckState(status: KeyStatus.bad, message: failure.message);
    }
  }
}
