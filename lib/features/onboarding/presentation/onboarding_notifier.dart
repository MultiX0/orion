import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/platform/platform_info.dart';

part 'onboarding_notifier.freezed.dart';
part 'onboarding_notifier.g.dart';

/// The six stations of the journey. Hands only exists where the harness
/// can run, so read the order from OnboardingState.steps, not from here.
enum OnboardingStep {
  welcome,
  find,
  pair,
  mind,
  hands,
  ready;

  /// What the constellation calls the step.
  String get label => this == mind ? 'brain and voice' : name;
}

@freezed
abstract class OnboardingState with _$OnboardingState {
  const OnboardingState._();

  const factory OnboardingState({
    @Default(OnboardingStep.welcome) OnboardingStep step,
    @Default(<OnboardingStep>[]) List<OnboardingStep> steps,

    /// Eight seconds of searching with nothing found.
    @Default(false) bool isTimedOut,
  }) = _OnboardingState;

  int get index => steps.indexOf(step);

  /// "01" for welcome, and so on. Zero-padded like the brand's pillars.
  String get ordinal => (index + 1).toString().padLeft(2, '0');

  bool get canGoBack => index > 0 && step != OnboardingStep.ready;

  /// Anything after Pair can be skipped.
  bool get canSkip =>
      index > steps.indexOf(OnboardingStep.pair) &&
      step != OnboardingStep.ready;
}

/// Which step is showing. Discovery itself is discoveredDevicesProvider;
/// pairing is pairingProvider. This only walks the constellation.
@riverpod
class Onboarding extends _$Onboarding {
  Timer? _timeout;

  @override
  OnboardingState build() {
    ref.onDispose(() => _timeout?.cancel());
    final hands = ref.watch(platformInfoProvider).canHostHarness;
    return OnboardingState(
      steps: [
        for (final s in OnboardingStep.values)
          if (s != OnboardingStep.hands || hands) s,
      ],
    );
  }

  void startDiscovery() {
    state = state.copyWith(step: OnboardingStep.find, isTimedOut: false);
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 8), () {
      state = state.copyWith(isTimedOut: true);
    });
  }

  /// The Bluetooth path asks for the keys itself, before the Wi-Fi, so they
  /// travel over the encrypted link. Brain and voice then leaves the
  /// journey, or the user would fill the same page twice.
  void keysAskedDuringPairing() {
    state = state.copyWith(
      steps: [
        for (final s in state.steps)
          if (s != OnboardingStep.mind) s,
      ],
    );
  }

  /// Paired on either path: carry on at whatever follows Pair.
  void afterPairing() {
    final i = state.steps.indexOf(OnboardingStep.pair);
    goTo(state.steps[i + 1]);
  }

  void goTo(OnboardingStep step) {
    _timeout?.cancel();
    state = state.copyWith(step: step);
  }

  void next() {
    final i = state.index;
    if (i + 1 < state.steps.length) goTo(state.steps[i + 1]);
  }

  void back() {
    final i = state.index;
    if (i > 0) goTo(state.steps[i - 1]);
  }
}
