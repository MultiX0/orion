import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../device/data/device_providers.dart';
import '../data/camera_providers.dart';
import '../domain/camera_frame.dart';

part 'camera_ui_notifier.freezed.dart';
part 'camera_ui_notifier.g.dart';

@freezed
abstract class CameraUiState with _$CameraUiState {
  const factory CameraUiState({
    @Default(false) bool isAskOpen,
    @Default(false) bool isAsking,
    @Default(false) bool isCapturing,
    @Default(false) bool isSaving,
    CameraFrame? snapshot,

    /// Where the last snapshot went. A screen shows it in a toast.
    String? savedPath,

    /// The turn started by "Ask about this", so the reply can be shown.
    String? askTurnId,
    String? error,
  }) = _CameraUiState;
}

/// Shutter, save, "ask about this" and the reply bubble. The ask call goes
/// straight to DeviceClient.
@riverpod
class CameraUi extends _$CameraUi {
  @override
  CameraUiState build() => const CameraUiState();

  void toggleAsk() =>
      state = state.copyWith(isAskOpen: !state.isAskOpen, error: null);

  Future<void> capture() async {
    state = state.copyWith(isCapturing: true, error: null, savedPath: null);
    final result = await ref.read(cameraSourceProvider).capture();
    state = switch (result) {
      Ok(:final value) => state.copyWith(isCapturing: false, snapshot: value),
      Err(:final failure) => state.copyWith(
        isCapturing: false,
        error: failure.message,
      ),
    };
  }

  Future<void> save() async {
    final frame = state.snapshot;
    if (frame == null) return;
    state = state.copyWith(isSaving: true, error: null, savedPath: null);
    final result = await ref.read(cameraSourceProvider).saveSnapshot(frame);
    state = switch (result) {
      Ok(:final value) => state.copyWith(isSaving: false, savedPath: value),
      Err(failure: UnsupportedFailure()) => state.copyWith(
        isSaving: false,
        error: 'Saving to disk arrives with the next build.',
      ),
      Err(:final failure) => state.copyWith(
        isSaving: false,
        error: failure.message,
      ),
    };
  }

  Future<void> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty) return;
    state = state.copyWith(isAsking: true, error: null, askTurnId: null);
    final result = await ref
        .read(deviceClientProvider)
        .askWithSnapshot(question);
    state = switch (result) {
      Ok(:final value) => state.copyWith(
        isAsking: false,
        isAskOpen: false,
        askTurnId: value,
      ),
      Err(:final failure) => state.copyWith(
        isAsking: false,
        error: failure.message,
      ),
    };
  }

  void dismissReply() => state = state.copyWith(askTurnId: null);
}
