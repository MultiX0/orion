import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/result.dart';

void main() {
  test('ok exposes its value', () {
    const result = Result.ok(3);
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, 3);
    expect(result.failureOrNull, isNull);
    expect(result.when(ok: (v) => v * 2, err: (_) => -1), 6);
  });

  test('err exposes its failure and maps through', () {
    const Result<int> result = Result.err(
      NetworkFailure('down', statusCode: 503),
    );
    expect(result.isErr, isTrue);
    expect(result.valueOrNull, isNull);
    expect(result.map((v) => v + 1).failureOrNull, isA<NetworkFailure>());
    expect(() => result.getOrThrow(), throwsA(isA<NetworkFailure>()));
  });
}
