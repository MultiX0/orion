import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../use_fakes.dart';
import 'audio_player.dart';
import 'audioplayers_player.dart';

part 'audio_providers.g.dart';

/// One player for the whole app. Tests and the fake build run without the
/// plugin, so they get the null player and nothing tries to open a device.
@Riverpod(keepAlive: true)
AudioPlayer audioPlayer(Ref ref) {
  if (ref.watch(useFakesProvider)) return const NullAudioPlayer();
  final player = AudioPlayersPlayer();
  ref.onDispose(player.dispose);
  return player;
}
