import 'dart:typed_data';

import '../../../core/result.dart';
import 'fish_config.dart';

/// Fish Audio: voice preview and pushing the fish block to the board.
abstract class FishRepository {
  /// Returns mp3 bytes for the given line, spoken with the configured voice.
  Future<Result<Uint8List>> previewVoice(
    FishConfig config, {
    String text = "Hi, I'm Orion.",
  });

  Future<Result<void>> pushToDevice(FishConfig config);

  /// GET /model?self=true&page_size=1. 401 is a bad key.
  Future<Result<void>> validateKey(String apiKey);

  /// GET /wallet/self/api-credit: the API credit in dollars. This is what
  /// speech to text spends; the free TTS model does not touch it.
  Future<Result<double>> apiCredit(String apiKey);
}
