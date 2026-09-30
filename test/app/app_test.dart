import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app/app.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/home/presentation/home_screen.dart';

/// The fake path: paired from the start, lands on Home with a live board.
void main() {
  testWidgets('boots to Home on fakes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [useFakesProvider.overrideWithValue(true)],
        child: const OrionApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount so the fake board cancels its timers, then run the clock past
    // the entrance delays flutter_animate schedules with Future.delayed.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
