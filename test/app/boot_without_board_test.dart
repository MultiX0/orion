import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app/app.dart';
import 'package:orion/core/use_fakes.dart';

/// No board, no keychain, no stored settings. The app still has to start and
/// land on onboarding.
void main() {
  testWidgets('boots on the real wiring with nothing on the network', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [useFakesProvider.overrideWithValue(false)],
        child: const OrionApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Find my Orion'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount, then run the clock past the entrance delays flutter_animate
    // schedules with Future.delayed, so no timer is left pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
