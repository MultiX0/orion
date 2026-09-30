import 'dart:math';

const _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// The 32 character secret the board expects as X-Orion-Token.
String newAppToken([Random? random]) {
  final source = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 32; i++)
      _alphabet.codeUnitAt(source.nextInt(_alphabet.length)),
  ]);
}
