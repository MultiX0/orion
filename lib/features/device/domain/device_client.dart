import '../../../core/result.dart';
import '../../conversation/domain/turn.dart';
import 'connection_status.dart';
import 'device_config.dart';
import 'device_info.dart';
import 'device_state.dart';
import 'ws_event.dart';

/// REST plus WebSocket to one paired board. Camera frames live in CameraSource.
abstract class DeviceClient {
  /// Pushed events. Broadcast, so a late listener misses earlier ones.
  Stream<WsEvent> get events;

  Stream<ConnectionStatus> get connection;
  ConnectionStatus get connectionStatus;

  Future<void> connect();
  Future<void> disconnect();

  /// Stops waiting out the backoff and tries the socket again now. For a
  /// Retry button, and for the moment a phone comes back from sleep.
  Future<void> reconnect();

  Future<Result<DeviceInfo>> info();
  Future<Result<DeviceState>> state();
  Future<Result<DeviceConfig>> config();

  /// Sends a partial config. The board merges it and returns the whole thing, masked.
  Future<Result<DeviceConfig>> updateConfig(DeviceConfig patch);

  /// Starts a turn as if the wake word fired. With text the board skips the mic.
  /// Returns the turn id; progress arrives on [events].
  Future<Result<String>> talk({String? text});

  /// Like talk with text, but the board grabs a camera frame first.
  Future<Result<String>> askWithSnapshot(String text);

  /// Speak text through TTS, no LLM.
  Future<Result<void>> say(String text);

  /// Interrupts listening or speaking.
  Future<Result<void>> stop();

  /// The board reboots and the socket drops. Reconnect is automatic.
  Future<Result<void>> restart();

  /// Newest first. Pass the last id as before to page further back.
  Future<Result<List<Turn>>> history({int limit = 20, String? before});
}
