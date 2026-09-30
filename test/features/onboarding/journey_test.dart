import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app/app.dart';
import 'package:orion/core/platform/platform_info.dart';
import 'package:orion/core/storage/in_memory_settings_store.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/onboarding/data/ble/fake_provisioning_link.dart';
import 'package:orion/features/onboarding/data/bluetooth_providers.dart';
import 'package:orion/features/onboarding/presentation/onboarding_notifier.dart';

/// The whole journey through the real router, on each path, counting how
/// often the brain and voice page shows up. It must be exactly once.
void main() {
  const desktop = PlatformInfo(
    isMobile: false,
    isDesktop: true,
    canHostHarness: true,
    hasTouch: false,
    osName: 'windows',
    canUseBluetooth: true,
  );
  const phone = PlatformInfo(
    isMobile: true,
    isDesktop: false,
    canHostHarness: false,
    hasTouch: true,
    osName: 'android',
    canUseBluetooth: true,
  );
  const keysTitle = 'Choose how it thinks and speaks.';

  late ProviderContainer container;
  late List<OnboardingStep> visited;
  ProviderSubscription<OnboardingStep>? watching;
  var keysPages = 0;
  var keysShowing = false;

  Future<void> boot(WidgetTester tester, PlatformInfo platform) async {
    keysPages = 0;
    keysShowing = false;
    await tester.binding.setSurfaceSize(const Size(480, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          platformInfoProvider.overrideWithValue(platform),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          provisioningLinkProvider.overrideWithValue(
            FakeProvisioningLink(
              step: const Duration(milliseconds: 50),
              pollsBeforeResult: 1,
            ),
          ),
        ],
        child: const OrionApp(),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(OrionApp)),
    );
  }

  // Pumps fake time and counts each fresh arrival on the keys page.
  Future<void> settle(WidgetTester tester, [int seconds = 2]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final showing = find.text(keysTitle).evaluate().isNotEmpty;
      if (showing && !keysShowing) keysPages++;
      keysShowing = showing;
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
  }

  // Welcome to Find, and start recording the journey's stations.
  Future<void> startJourney(WidgetTester tester) async {
    await settle(tester, 3);
    visited = [container.read(onboardingProvider).step];
    watching = container.listen(onboardingProvider.select((s) => s.step), (
      _,
      next,
    ) {
      if (visited.last != next) visited.add(next);
    });
    await tapText(tester, 'Find my Orion');
    // The fake boards trickle in over a few seconds.
    await settle(tester, 3);
  }

  Future<void> pairOverLan(WidgetTester tester) async {
    await tapText(tester, 'Orion Mock');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tapText(tester, 'Connect');
  }

  Future<void> pairOverBluetooth(WidgetTester tester) async {
    await tapText(tester, 'A new Orion');
    await tapText(tester, 'Orion-a1b2');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tapText(tester, 'Connect');
    expect(find.text(keysTitle), findsOneWidget);
    await tapText(tester, 'Later');
    await tapText(tester, 'Hearth');
    await tester.enterText(find.byType(TextField).last, 'correct horse');
    await tapText(tester, 'Join');
    await settle(tester, 3);
    expect(find.text('Orion is home.'), findsOneWidget);
    await tapText(tester, 'Continue');
  }

  // Everything after Pair: skip the keys if they show, go through Hands if
  // this platform has it, land on Ready and go home.
  Future<void> finishJourney(WidgetTester tester) async {
    if (keysShowing) await tapText(tester, 'Later');
    if (find.text('Hands on this PC?').evaluate().isNotEmpty) {
      await tapText(tester, 'Continue');
    }
    await tapText(tester, 'Go to Orion');
    expect(find.text(keysTitle), findsNothing);
    // Let go, so the journey is disposed like it is in the app.
    watching?.close();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('LAN pairing on a PC asks for the keys once, after Pair', (
    tester,
  ) async {
    await boot(tester, desktop);
    await startJourney(tester);
    await pairOverLan(tester);
    await finishJourney(tester);
    expect(keysPages, 1);
    expect(visited, [
      OnboardingStep.welcome,
      OnboardingStep.find,
      OnboardingStep.mind,
      OnboardingStep.hands,
      OnboardingStep.ready,
    ]);
    await unmount(tester);
  });

  testWidgets('Bluetooth on a PC asks for the keys once, before the Wi-Fi', (
    tester,
  ) async {
    await boot(tester, desktop);
    await startJourney(tester);
    await pairOverBluetooth(tester);
    await finishJourney(tester);
    expect(keysPages, 1);
    expect(visited, [
      OnboardingStep.welcome,
      OnboardingStep.find,
      OnboardingStep.hands,
      OnboardingStep.ready,
    ]);
    await unmount(tester);
  });

  testWidgets('Bluetooth on a phone asks for the keys once', (tester) async {
    await boot(tester, phone);
    await startJourney(tester);
    await pairOverBluetooth(tester);
    await finishJourney(tester);
    expect(keysPages, 1);
    expect(visited, [
      OnboardingStep.welcome,
      OnboardingStep.find,
      OnboardingStep.ready,
    ]);
    await unmount(tester);
  });

  testWidgets('unpair and pair again over the LAN asks for the keys once', (
    tester,
  ) async {
    await boot(tester, desktop);
    await startJourney(tester);
    await pairOverBluetooth(tester);
    await finishJourney(tester);
    expect(keysPages, 1);

    // The board is known now. Forgetting it sends the app back to the
    // start, and the second journey is a fresh one.
    await container.read(appSettingsProvider.notifier).setPairedDevice(null);
    keysPages = 0;
    await startJourney(tester);
    await pairOverLan(tester);
    await finishJourney(tester);
    expect(keysPages, 1);
    expect(visited, [
      OnboardingStep.welcome,
      OnboardingStep.find,
      OnboardingStep.mind,
      OnboardingStep.hands,
      OnboardingStep.ready,
    ]);
    await unmount(tester);
  });
}
