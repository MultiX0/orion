import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/platform/platform_info.dart';
import 'package:orion/features/onboarding/presentation/onboarding_notifier.dart';

void main() {
  ProviderContainer journey({required bool hands}) {
    final container = ProviderContainer(
      overrides: [
        platformInfoProvider.overrideWithValue(
          PlatformInfo(
            isMobile: !hands,
            isDesktop: hands,
            canHostHarness: hands,
            hasTouch: !hands,
            osName: hands ? 'windows' : 'android',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Keep the auto-disposing journey alive for the whole test.
    container.listen(onboardingProvider, (_, _) {});
    return container;
  }

  test('the LAN path goes from Pair to Brain and voice', () {
    final c = journey(hands: true);
    final n = c.read(onboardingProvider.notifier);
    n.goTo(OnboardingStep.pair);
    n.afterPairing();
    expect(c.read(onboardingProvider).step, OnboardingStep.mind);
    expect(
      c.read(onboardingProvider).steps.where((s) => s == OnboardingStep.mind),
      hasLength(1),
    );
  });

  test('the Bluetooth path skips Brain and voice, forward and back', () {
    final c = journey(hands: true);
    final n = c.read(onboardingProvider.notifier);
    n.goTo(OnboardingStep.pair);
    n.keysAskedDuringPairing();
    n.afterPairing();
    final state = c.read(onboardingProvider);
    expect(state.step, OnboardingStep.hands);
    expect(state.steps, isNot(contains(OnboardingStep.mind)));
    expect(state.ordinal, '04');
    n.back();
    expect(c.read(onboardingProvider).step, OnboardingStep.pair);
  });

  test('Bluetooth on a phone goes straight from Pair to Ready', () {
    final c = journey(hands: false);
    final n = c.read(onboardingProvider.notifier);
    n.goTo(OnboardingStep.pair);
    n.keysAskedDuringPairing();
    n.afterPairing();
    expect(c.read(onboardingProvider).step, OnboardingStep.ready);
  });
}
