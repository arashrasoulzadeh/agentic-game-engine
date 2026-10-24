import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:test/test.dart';

void main() {
  test('the version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: $engineApiVersion'));
  });

  test('the executable reports its version', () async {
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/engine_api.dart',
      '--version',
    ]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('engine_api $engineApiVersion'));
  });
}
