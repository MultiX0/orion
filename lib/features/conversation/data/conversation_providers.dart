import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../device/data/device_providers.dart';
import '../domain/turn.dart';

part 'conversation_providers.g.dart';

/// Finished turns from the board, newest first. Invalidate to refetch.
@riverpod
Future<List<Turn>> turns(Ref ref) async {
  final result = await ref.watch(deviceClientProvider).history();
  return result.getOrThrow();
}
