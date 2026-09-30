import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_card.dart';
import '../data/providers_config_notifier.dart';
import 'brain_form.dart';

/// One provider: the same form the onboarding Brain step shows, in a card.
class ProviderDetailScreen extends ConsumerWidget {
  const ProviderDetailScreen({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(
      providersConfigProvider.select(
        (c) => c.providers.where((p) => p.id == providerId).firstOrNull,
      ),
    );
    if (provider == null) {
      return const EmptyState(
        label: '// Unknown',
        title: 'No such provider',
        emphasis: 'provider',
      );
    }
    return SafeArea(
      child: Column(
        children: [
          OrionAppBar(
            label: '// Provider · ${provider.kind.name}',
            title: provider.name,
            showBack: true,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OrionContainer.article,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.xxl + Space.lg,
                  ),
                  children: [
                    OrionCard(
                      hoverable: false,
                      child: BrainForm(providerId: providerId),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
