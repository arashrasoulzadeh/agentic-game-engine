import 'dart:io';

import 'package:test/test.dart';

/// The engine is released as one unit: every package carries the same version and none is published to
/// pub.dev by accident before the publishing plan in TODO.md is carried out. A new package that forgets
/// either fails here instead of at release time.
void main() {
  final packages = Directory('../')
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/pubspec.yaml').existsSync())
      .toList();

  String? field(Directory d, String key) {
    for (final line in File('${d.path}/pubspec.yaml').readAsLinesSync()) {
      if (line.startsWith('$key:')) {
        return line.substring(key.length + 1).trim().replaceAll("'", '');
      }
    }
    return null;
  }

  test('every package is found', () {
    expect(packages.length, greaterThanOrEqualTo(8));
  });

  test('all packages share one version', () {
    final versions = {for (final d in packages) d.path: field(d, 'version')};
    expect(versions.values.toSet(), hasLength(1), reason: '$versions');
  });

  test('no package can be published by accident', () {
    for (final d in packages) {
      expect(field(d, 'publish_to'), 'none', reason: d.path);
    }
  });

  test(
    'every package a consumer could fetch carries a LICENSE, README and CHANGELOG',
    () {
      // engine_studio is an application, not a dependency.
      for (final d in packages.where(
        (d) => !d.path.endsWith('engine_studio'),
      )) {
        for (final f in ['LICENSE', 'README.md', 'CHANGELOG.md']) {
          expect(
            File('${d.path}/$f').existsSync(),
            isTrue,
            reason: '${d.path} is missing $f',
          );
        }
      }
    },
  );
}
