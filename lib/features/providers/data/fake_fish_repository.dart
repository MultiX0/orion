import 'dart:typed_data';

import '../../../core/result.dart';
import '../domain/fish_config.dart';
import '../domain/fish_repository.dart';

/// Pretends to call Fish Audio. Returns empty audio, so nothing plays.
class FakeFishRepository implements FishRepository {
  @override
  Future<Result<Uint8List>> previewVoice(
    FishConfig config, {
    String text = "Hi, I'm Orion.",
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return Ok(Uint8List(0));
  }

  /// Two dollars, so the credit note has something to show.
  @override
  Future<Result<double>> apiCredit(String apiKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (apiKey == 'nocredit') return const Ok(0);
    return const Ok(2);
  }

  @override
  Future<Result<void>> validateKey(String apiKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return apiKey.trim().isEmpty
        ? const Err(ProviderFailure(ProviderFailureKind.badKey, 'Enter a key'))
        : const Ok(null);
  }

  @override
  Future<Result<void>> pushToDevice(FishConfig config) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const Ok(null);
  }
}
