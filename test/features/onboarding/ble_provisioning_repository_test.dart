import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/result.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/secret_store.dart';
import 'package:orion/features/onboarding/data/ble/ble_provisioning_repository.dart';
import 'package:orion/features/onboarding/data/ble/fake_provisioning_link.dart';
import 'package:orion/features/onboarding/data/ble/unsupported_link.dart';
import 'package:orion/features/onboarding/domain/join_status.dart';
import 'package:orion/features/onboarding/domain/nearby_board.dart';

const _board = NearbyBoard(id: 'AA:BB', name: 'Orion-a1b2', rssi: -58);

void main() {
  late FakeProvisioningLink link;
  late InMemorySecretStore secrets;
  late BleProvisioningRepository repo;

  setUp(() {
    link = FakeProvisioningLink(step: Duration.zero, pollsBeforeResult: 1);
    secrets = InMemorySecretStore();
    repo = BleProvisioningRepository(
      link: link,
      secrets: secrets,
      statusEvery: Duration.zero,
    );
  });

  Future<List<JoinStatus>> join(String ssid, String password) async {
    expect(
      (await repo.sendCredentials(ssid: ssid, password: password)).isOk,
      isTrue,
    );
    return repo.watchStatus().toList();
  }

  test('boards come back deduped and strongest first', () async {
    final lists = await repo.findBoards().take(2).toList();
    expect(lists.last.map((b) => b.name), ['Orion-a1b2', 'Orion-c3d4']);
    expect(lists.last.first.suffix, 'a1b2');
  });

  test('a code that is not six digits never reaches the board', () async {
    final result = await repo.connect(_board, code: '12ab');
    final failure = result.failureOrNull as BluetoothFailure;
    expect(failure.problem, BluetoothProblem.wrongCode);
    expect(link.isOpen, isFalse);
  });

  test('the wrong code is refused and the right one opens the link', () async {
    final wrong = await repo.connect(_board, code: '654321');
    expect(
      (wrong.failureOrNull as BluetoothFailure).problem,
      BluetoothProblem.wrongCode,
    );
    expect((await repo.connect(_board, code: '123456')).isOk, isTrue);
    expect(link.isOpen, isTrue);
  });

  test('networks arrive tidied from the board scan', () async {
    await repo.connect(_board, code: '123456');
    final networks = (await repo.scanNetworks()).valueOrNull!;
    expect(networks.first.ssid, 'Hearth');
    expect(networks.where((n) => n.ssid == 'Hearth'), hasLength(1));
    expect(networks.any((n) => n.ssid.isEmpty), isFalse);
  });

  test(
    'pair sends a fresh token and stores it only once the board says ok',
    () async {
      await repo.connect(_board, code: '123456');
      expect(await secrets.read(SecretKeys.pairingToken), isNull);
      final id = await repo.pair(deviceName: '  ');
      expect(id.valueOrNull, 'orion-a1b2');
      final sent = link.lastPair!;
      expect(sent.appToken, hasLength(32));
      expect(sent.deviceName, 'Orion');
      expect(await secrets.read(SecretKeys.pairingToken), sent.appToken);
    },
  );

  test('pairing again keeps the token already on file', () async {
    await secrets.write(SecretKeys.pairingToken, 'kept-token');
    await repo.connect(_board, code: '123456');
    await repo.pair(deviceName: 'Desk');
    expect(link.lastPair!.appToken, 'kept-token');
    expect(link.lastPair!.deviceName, 'Desk');
  });

  test('a good password ends connected with the board address', () async {
    await repo.connect(_board, code: '123456');
    final statuses = await join('Hearth', 'correct horse');
    expect(statuses.first, const JoinStatus.connecting());
    expect(statuses.last, const JoinStatus.connected(ip: '192.168.1.40'));
  });

  test('a wrong password fails, and the same session can retry', () async {
    await repo.connect(_board, code: '123456');
    final first = await join('Hearth', 'wrongpass');
    expect(first.last, const JoinStatus.failed(JoinFailure.wrongPassword));
    final second = await join('Hearth', 'right one');
    expect(second.last, isA<JoinConnected>());
  });

  test(
    'a name the board never heard is not found; the hidden one joins',
    () async {
      await repo.connect(_board, code: '123456');
      final missing = await join('Andromeda', 'pw');
      expect(
        missing.last,
        const JoinStatus.failed(JoinFailure.networkNotFound),
      );
      final hidden = await join('Observatory', 'pw');
      expect(hidden.last, isA<JoinConnected>());
    },
  );

  test('a link that drops mid join reads as a lost board', () async {
    await repo.connect(_board, code: '123456');
    link.dropOnNextStatus = true;
    final statuses = await join('Hearth', 'pw');
    expect(statuses.last, const JoinStatus.failed(JoinFailure.lostBoard));
    final again = await repo.scanNetworks();
    expect(
      (again.failureOrNull as BluetoothFailure).problem,
      BluetoothProblem.lostBoard,
    );
  });

  test('a board that never settles times out', () async {
    final slow = BleProvisioningRepository(
      link: FakeProvisioningLink(step: Duration.zero, pollsBeforeResult: 1000),
      secrets: secrets,
      statusEvery: const Duration(milliseconds: 5),
      joinTimeout: const Duration(milliseconds: 60),
    );
    await slow.connect(_board, code: '123456');
    await slow.sendCredentials(ssid: 'Hearth', password: 'pw');
    final statuses = await slow.watchStatus().toList();
    expect(statuses.last, const JoinStatus.failed(JoinFailure.timedOut));
  });

  test('without Bluetooth every call is an unsupported failure', () async {
    final none = BleProvisioningRepository(
      link: UnsupportedLink(),
      secrets: secrets,
    );
    expect(none.isSupported, isFalse);
    expect(
      (await none.connect(_board, code: '123456')).failureOrNull,
      isA<BluetoothFailure>(),
    );
    await expectLater(none.findBoards(), emitsError(isA<BluetoothFailure>()));
  });
}
