import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';

part 'key_on_file.g.dart';

/// Whether a provider key sits in the keychain. Only the fact, never the
/// key. Invalidate after storing one.
@riverpod
Future<bool> providerKeyOnFile(Ref ref, String providerId) async {
  final key = await ref
      .watch(secretStoreProvider)
      .read(SecretKeys.providerApiKey(providerId));
  return key != null && key.isNotEmpty;
}

@riverpod
Future<bool> fishKeyOnFile(Ref ref) async {
  final key = await ref.watch(secretStoreProvider).read(SecretKeys.fishApiKey);
  return key != null && key.isNotEmpty;
}
