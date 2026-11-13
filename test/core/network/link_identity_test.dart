import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/link_identity.dart';

void main() {
  test('the version other nodes see is the one in pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = RegExp(r'\d+\.\d+\.\d+').firstMatch(line)?.group(0);
    expect(version, isNotNull);
    expect(appVersion, version);
  });
}
