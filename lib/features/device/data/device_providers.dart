import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/platform/platform_info.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../domain/connection_status.dart';
import '../domain/device_client.dart';
import '../domain/device_config.dart';
import '../domain/device_info.dart';
import '../domain/ws_event.dart';
import '../../harness/data/harness_providers.dart';
import 'fake_device_client.dart';
import 'http_device_client.dart';

part 'device_providers.g.dart';

/// Where the board lives before anything is paired. The mock listens here,
/// so a fresh checkout has something to talk to.
const _fallbackHost = 'localhost:${ApiPaths.mockPort}';

/// One dio and one token for the paired board. Rebuilds when the pairing
/// changes, which also rebuilds the client and the camera.
@Riverpod(keepAlive: true)
DeviceApi deviceApi(Ref ref) {
  final device = ref.watch(pairedDeviceProvider);
  final info = ref.watch(platformInfoProvider);
  final api = DeviceApi(
    host: device?.host ?? _fallbackHost,
    client: info.isDesktop ? 'pc' : (info.isMobile ? 'phone' : null),
    // Rebuilds once the phone's brain is listening, and the socket goes
    // again with it.
    brain: info.isMobile ? ref.watch(phoneBrainProvider).value : null,
  );
  ref.onDispose(api.close);
  return api;
}

@Riverpod(keepAlive: true)
DeviceClient deviceClient(Ref ref) {
  if (ref.watch(useFakesProvider)) {
    final fake = FakeDeviceClient();
    ref.onDispose(fake.dispose);
    unawaited(fake.connect());
    return fake;
  }
  final api = ref.watch(deviceApiProvider);
  final client = HttpDeviceClient(api: api);
  ref.onDispose(client.dispose);
  unawaited(_bootClient(ref, api, client));
  return client;
}

/// The token lives in the keychain, so the socket waits for it. A board that
/// is not there yet just keeps the reconnect loop busy, which is fine.
Future<void> _bootClient(
  Ref ref,
  DeviceApi api,
  HttpDeviceClient client,
) async {
  api.token = await ref.read(secretStoreProvider).read(SecretKeys.pairingToken);
  await client.connect();
}

@Riverpod(keepAlive: true)
Stream<WsEvent> deviceEvents(Ref ref) => ref.watch(deviceClientProvider).events;

@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) async* {
  final client = ref.watch(deviceClientProvider);
  yield client.connectionStatus;
  yield* client.connection;
}

@riverpod
Future<DeviceInfo> deviceInfo(Ref ref) async {
  final result = await ref.watch(deviceClientProvider).info();
  return result.getOrThrow();
}

@riverpod
Future<DeviceConfig> deviceConfig(Ref ref) async {
  final result = await ref.watch(deviceClientProvider).config();
  return result.getOrThrow();
}
