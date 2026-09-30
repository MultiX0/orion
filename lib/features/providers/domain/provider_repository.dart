import 'dart:typed_data';

import '../../../core/result.dart';
import 'llm_provider.dart';
import 'model_info.dart';

/// Rewrites the dsh config so the agent uses the same brain as the board.
/// Desktop only; null everywhere else.
typedef HarnessMirror =
    Future<Result<void>> Function(LlmProvider provider, String model);

/// Proves a provider works and hands its config to the board and the harness.
/// The app never runs conversations itself.
abstract class ProviderRepository {
  Future<Result<List<ModelInfo>>> listModels(LlmProvider provider);

  /// One short completion. Returns the reply text so the UI can show it.
  Future<Result<String>> testCompletion(LlmProvider provider, String model);

  /// Sends a PNG and a question. The desktop harness uses this so the board
  /// only ever gets a sentence back from `screenshot`, never image bytes.
  Future<Result<String>> describeImage(
    LlmProvider provider,
    String model,
    Uint8List png,
    String prompt,
  );

  /// GET /models with the key. 401 is a bad key, anything else is fine.
  Future<Result<void>> validateKey(LlmProvider provider);

  /// POST /api/config with the llm block.
  Future<Result<void>> pushToDevice(LlmProvider provider, String model);

  /// Desktop only. Rewrites the dsh config so the agent uses the same brain.
  Future<Result<void>> mirrorToHarness(LlmProvider provider, String model);
}
