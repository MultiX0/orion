import '../../../../core/result.dart';
import '../../domain/join_status.dart';

/// Every error on the Bluetooth path says what happened and what to do.
String failureCopy(Failure failure) {
  if (failure is! BluetoothFailure) {
    return failure.message.isEmpty ? 'Something went wrong.' : failure.message;
  }
  return switch (failure.problem) {
    BluetoothProblem.off => 'Bluetooth is off. Turn it on, then look again.',
    BluetoothProblem.denied =>
      'Orion needs Bluetooth permission to find the board. Allow it in the '
          'phone settings, then look again.',
    BluetoothProblem.unsupported =>
      'This device has no Bluetooth for setup. Pair by address instead.',
    BluetoothProblem.lostBoard =>
      'The board went out of reach. Bring the phone closer and try again.',
    BluetoothProblem.wrongCode =>
      'That code does not match. Check the six digits on the board.',
    BluetoothProblem.protocol =>
      'The board answered in a way this app does not know. Restart setup on '
          'the board and try again.',
  };
}

/// Title, next step and the button that takes it, for a failed join.
({String title, String emphasis, String body, String action}) joinFailureCopy(
  JoinFailure reason,
) => switch (reason) {
  JoinFailure.wrongPassword => (
    title: 'The network said no.',
    emphasis: 'no',
    body: 'The password was turned down. Check it and type it again.',
    action: 'Try another password',
  ),
  JoinFailure.networkNotFound => (
    title: 'The board cannot hear it.',
    emphasis: 'hear',
    body:
        'Orion only reaches 2.4 GHz networks, and this one did not answer. '
        'Choose one from its list.',
    action: 'Choose again',
  ),
  JoinFailure.lostBoard => (
    title: 'The board went quiet.',
    emphasis: 'quiet',
    body:
        'The Bluetooth link dropped. Bring the phone closer. If the code is '
        'gone from its screen, start setup on the board again.',
    action: 'Try again',
  ),
  JoinFailure.timedOut => (
    title: 'The board never settled.',
    emphasis: 'settled',
    body:
        'It kept trying without an answer from the network. Try once more, '
        'closer to the router if you can.',
    action: 'Try again',
  ),
};
