import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/theme/theme.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/device/domain/device.dart';
import 'package:orion/features/onboarding/data/ble/fake_provisioning_link.dart';
import 'package:orion/features/onboarding/data/bluetooth_providers.dart';
import 'package:orion/features/onboarding/data/fake_device_discovery.dart';
import 'package:orion/features/onboarding/data/lan_handover.dart';
import 'package:orion/features/onboarding/presentation/bluetooth/bluetooth_setup_flow.dart';

/// Every station of the Bluetooth path against the scripted board.
void main() {
  Device? done;

  Future<void> pumpFlow(WidgetTester tester) async {
    done = null;
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          provisioningLinkProvider.overrideWithValue(
            FakeProvisioningLink(
              step: const Duration(milliseconds: 50),
              pollsBeforeResult: 1,
            ),
          ),
          lanHandoverProvider.overrideWithValue(
            LanHandover(discovery: FakeDeviceDiscovery()),
          ),
        ],
        child: MaterialApp(
          theme: buildOrionTheme(),
          home: Scaffold(
            body: BluetoothSetupFlow(
              label: '// 03 · Pair',
              reduced: true,
              onDone: (device) => done = device,
            ),
          ),
        ),
      ),
    );
  }

  // Enough fake time for the scripted board plus the entrance motion.
  Future<void> settle(WidgetTester tester, [int seconds = 3]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> reachNetworks(WidgetTester tester) async {
    await pumpFlow(tester);
    await settle(tester, 1);
    expect(find.text('Orion-a1b2'), findsOneWidget);
    expect(find.text('Orion-c3d4'), findsOneWidget);
    await tester.tap(find.text('Orion-a1b2'));
    await settle(tester, 1);
    expect(find.text('Read me the code.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Connect'));
    await settle(tester);
    // Paired: brain and voice could go over Bluetooth now; Later skips.
    expect(find.text('Choose how it thinks and speaks.'), findsOneWidget);
    final later = find.text('Later');
    await tester.dragUntilVisible(
      later,
      find.ancestor(of: later, matching: find.byType(Scrollable)).first,
      const Offset(0, -400),
    );
    await settle(tester, 1);
    await tester.tap(later);
    await settle(tester);
    expect(find.text('Hearth'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('nearby, code, network, password, joined, done', (tester) async {
    await reachNetworks(tester);
    // Strongest first, the duplicate folded, the hidden one left out.
    final hearth = tester.getTopLeft(find.text('Hearth')).dy;
    final guest = tester.getTopLeft(find.text('Kepler Guest')).dy;
    expect(hearth, lessThan(guest));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));

    await tester.tap(find.text('Hearth'));
    await settle(tester, 1);
    expect(find.text('Hand it the key.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.tap(find.text('Join'));
    await settle(tester, 4);

    expect(find.text('Orion is home.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(done?.id, 'orion-mock');
    await unmount(tester);
  });

  testWidgets('a wrong code says so and stays on the code', (tester) async {
    await pumpFlow(tester);
    await settle(tester, 1);
    await tester.tap(find.text('Orion-a1b2'));
    await settle(tester, 1);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Connect'));
    await settle(tester, 1);
    expect(find.textContaining('That code does not match'), findsOneWidget);
    expect(find.text('Read me the code.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a wrong password offers another try', (tester) async {
    await reachNetworks(tester);
    await tester.tap(find.text('Hearth'));
    await settle(tester, 1);
    await tester.enterText(find.byType(TextField), 'wrongpass');
    await tester.tap(find.text('Join'));
    await settle(tester);
    expect(find.text('The network said no.'), findsOneWidget);
    await tester.tap(find.text('Try another password'));
    await settle(tester, 1);
    expect(find.text('Hand it the key.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a hidden network the board never hears is not found', (
    tester,
  ) async {
    await reachNetworks(tester);
    await tester.tap(find.text('Hidden network'));
    await settle(tester, 1);
    expect(find.text('Name the hidden one.'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Andromeda');
    await tester.enterText(fields.last, 'pw');
    await tester.tap(find.text('Join'));
    await settle(tester);
    expect(find.text('The board cannot hear it.'), findsOneWidget);
    await tester.tap(find.text('Choose again'));
    await settle(tester);
    expect(find.text('Choose its network.'), findsOneWidget);
    await unmount(tester);
  });
}
