import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/theme/theme.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/settings/presentation/lan_wifi_form.dart';

Widget _host(Widget child) => ProviderScope(
  overrides: [useFakesProvider.overrideWithValue(true)],
  child: MaterialApp(
    theme: buildOrionTheme(),
    home: Scaffold(body: child),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('online, the new network goes over the LAN', (tester) async {
    await tester.pumpWidget(_host(const LanWifiForm(bluetooth: true)));
    await _settle(tester);
    expect(find.text('Use Bluetooth instead'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Hearth');
    await tester.enterText(fields.last, 'pw');
    await tester.tap(find.text('Move Orion'));
    await _settle(tester);
    expect(find.text('Orion is moving.'), findsOneWidget);
    expect(find.textContaining('comes back on Hearth'), findsOneWidget);
  });

  testWidgets('out of reach, it explains setup mode', (tester) async {
    await tester.pumpWidget(_host(const SetupModeNote(bluetooth: true)));
    await _settle(tester);
    expect(find.text('Orion cannot hear this device.'), findsOneWidget);
    expect(find.text('Set up over Bluetooth'), findsOneWidget);
  });

  testWidgets('a desktop without Bluetooth points to the phone', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SetupModeNote(bluetooth: false)));
    await _settle(tester);
    expect(find.text('Set up over Bluetooth'), findsNothing);
    expect(find.textContaining('runs on a phone'), findsOneWidget);
  });
}
