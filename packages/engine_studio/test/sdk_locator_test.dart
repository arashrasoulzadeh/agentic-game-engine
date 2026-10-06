import 'package:engine_studio/src/lsp/sdk_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers the SDK named by the environment over installed copies', () {
    final found = findDartBinary(
      environment: {'DART_SDK': '/sdk', 'HOME': '/Users/me'},
      home: '/Users/me',
      exists: (path) =>
          path == '/sdk/bin/dart' || path.endsWith('dart-sdk/bin/dart'),
    );
    expect(found, '/sdk/bin/dart');
  });

  test('finds the usual Flutter install even when PATH does not have it', () {
    final found = findDartBinary(
      environment: {'PATH': '/usr/bin:/bin', 'HOME': '/Users/me'},
      home: '/Users/me',
      exists: (path) =>
          path == '/Users/me/develop/flutter/bin/cache/dart-sdk/bin/dart',
    );
    expect(found, '/Users/me/develop/flutter/bin/cache/dart-sdk/bin/dart');
  });

  test('falls back to PATH when no known location exists', () {
    final found = findDartBinary(
      environment: {'PATH': '/odd/bin:/other', 'HOME': '/Users/me'},
      home: '/Users/me',
      exists: (path) => path == '/other/dart',
    );
    expect(found, '/other/dart');
  });

  test('returns null when no Dart is found anywhere', () {
    expect(
      findDartBinary(
        environment: {'PATH': ''},
        home: '/Users/me',
        exists: (_) => false,
      ),
      isNull,
    );
  });
}
