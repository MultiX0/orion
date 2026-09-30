import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/result.dart';
import 'ble_contract.dart';

/// The orion-config writes for one config. Small ones go whole; larger ones
/// go as `{ "part", "parts", "data" }` slices of the JSON text, cut on
/// characters so a slice never splits a character in two.
List<Uint8List> configWrites(
  Map<String, dynamic> patch, {
  int wholeMax = BleContract.configWholeMax,
  int sliceChars = BleContract.configSliceChars,
}) {
  final text = jsonEncode(patch);
  final whole = utf8.encode(text);
  if (whole.length <= wholeMax) return [Uint8List.fromList(whole)];
  final runes = text.runes.toList();
  final slices = <String>[
    for (var i = 0; i < runes.length; i += sliceChars)
      String.fromCharCodes(
        runes.sublist(
          i,
          i + sliceChars > runes.length ? runes.length : i + sliceChars,
        ),
      ),
  ];
  return [
    for (var i = 0; i < slices.length; i++)
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'part': i + 1,
            'parts': slices.length,
            'data': slices[i],
          }),
        ),
      ),
  ];
}

/// The board's answer to one part that is not the last: `{ ok, part }`.
Result<void> parsePartAck(List<int> bytes, int part) {
  final decoded = _decode(bytes);
  if (decoded case Err(:final failure)) return Err(failure);
  final map = decoded.valueOrNull!;
  final error = _boardError(map);
  if (error != null) return Err(error);
  if (map['ok'] != true || map['part'] != part) {
    return Err(
      BluetoothFailure(
        BluetoothProblem.protocol,
        'orion-config did not take part $part',
      ),
    );
  }
  return const Ok(null);
}

/// The answer to the whole config or its last part: the merged config,
/// masked, or the board's `{ error, message }`.
Result<Map<String, dynamic>> parseConfigAnswer(List<int> bytes) {
  final decoded = _decode(bytes);
  if (decoded case Err(:final failure)) return Err(failure);
  final map = decoded.valueOrNull!;
  final error = _boardError(map);
  return error == null ? Ok(map) : Err(error);
}

Failure? _boardError(Map<String, dynamic> map) {
  final code = map['error'];
  if (code is! String) return null;
  final message = map['message'];
  return DeviceFailure(code, message is String ? message : code);
}

Result<Map<String, dynamic>> _decode(List<int> bytes) {
  if (bytes.isEmpty) {
    return const Err(
      BluetoothFailure(
        BluetoothProblem.protocol,
        'orion-config answered empty',
      ),
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return const Err(ParseFailure('orion-config did not answer with JSON'));
  }
  if (decoded is! Map<String, dynamic>) {
    return const Err(ParseFailure('orion-config answer is not an object'));
  }
  return Ok(decoded);
}
