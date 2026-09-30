import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/platform/platform_info.dart';
import '../../providers/domain/provider_repository.dart';
import 'dsh/dsh_config.dart';
import 'dsh/dsh_paths.dart';

part 'dsh_paths_provider.g.dart';

/// Kept out of harness_providers.dart on purpose: the providers layer reads
/// `harnessMirror`, and this file imports nothing from it, so the two
/// features do not end up importing each other.
@Riverpod(keepAlive: true)
DshPaths dshPaths(Ref ref) => DshPaths.underUserHome();

/// Rewrites the dsh config when the user picks a provider. Null off desktop,
/// where `mirrorToHarness` is then a no-op.
@Riverpod(keepAlive: true)
HarnessMirror? harnessMirror(Ref ref) {
  if (!ref.watch(platformInfoProvider).canHostHarness) return null;
  return DshConfigWriter(ref.watch(dshPathsProvider)).write;
}
