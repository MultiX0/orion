import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/result.dart';
import '../data/providers_config_notifier.dart';

part 'voice_ui.freezed.dart';
part 'voice_ui.g.dart';

/// The id the preview clip plays under.
const previewClipId = 'preview';

@freezed
abstract class VoiceUiState with _$VoiceUiState {
  const VoiceUiState._();

  const factory VoiceUiState({
    /// previewClipId while the preview clip plays.
    String? playingId,

    /// Fetching the preview clip from Fish.
    @Default(false) bool isPreviewing,
    String? error,
  }) = _VoiceUiState;

  bool get isPlaying => playingId != null;
}

/// Preview for the voice card. One clip at a time; the orb on the
/// onboarding step speaks while one plays.
@Riverpod(keepAlive: true)
class VoiceUi extends _$VoiceUi {
  Timer? _fallback;

  @override
  VoiceUiState build() {
    ref.onDispose(() => _fallback?.cancel());
    ref.listen(audioPlayingProvider, (_, next) {
      switch (next.value) {
        case true:
          _fallback?.cancel();
        case false:
          _fallback?.cancel();
          state = state.copyWith(playingId: null);
        case null:
          break;
      }
    });
    return const VoiceUiState();
  }

  Future<void> preview() async {
    if (state.playingId == previewClipId) return stop();
    state = state.copyWith(isPreviewing: true, error: null);
    final result = await ref
        .read(providersConfigProvider.notifier)
        .previewVoice();
    switch (result) {
      case Ok(:final value):
        state = state.copyWith(isPreviewing: false, playingId: previewClipId);
        await ref.read(audioPlayerProvider).playBytes(value);
        _armFallback();
      case Err(:final failure):
        state = state.copyWith(isPreviewing: false, error: failure.message);
    }
  }

  Future<void> stop() async {
    _fallback?.cancel();
    state = state.copyWith(playingId: null);
    await ref.read(audioPlayerProvider).stop();
  }

  /// A player that never reports (the null one) would leave
  /// the bars running forever. Three quiet seconds and they rest.
  void _armFallback() {
    _fallback?.cancel();
    _fallback = Timer(const Duration(seconds: 3), () {
      state = state.copyWith(playingId: null);
    });
  }
}

@Riverpod(keepAlive: true)
Stream<bool> audioPlaying(Ref ref) => ref.watch(audioPlayerProvider).isPlaying;
