import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/project.dart';
import 'package:orion/core/storage/in_memory_settings_store.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/theme/theme.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/providers/presentation/stages/get_fish_key_button.dart';
import 'package:orion/features/settings/presentation/app_settings_card.dart';

void main() {
  testWidgets('settings name the maker and open the GitHub profile', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          linkOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: buildOrionTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AppSettingsCard()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('made by MultiX0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('about-github')));
    await tester.pump();
    expect(opened, [Uri.parse(OrionProject.url)]);
    expect(OrionProject.url, 'https://github.com/MultiX0');
  });
}
