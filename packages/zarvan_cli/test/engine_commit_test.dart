import 'dart:io';

import 'package:zarvan_cli/src/engine_commit.dart';
import 'package:test/test.dart';

const _gitLock = '''
packages:
  zarvan_core:
    dependency: "direct main"
    description:
      path: packages/zarvan_core
      ref: main
      resolved-ref: 0123456789abcdef0123456789abcdef01234567
      url: "https://github.com/arashrasoulzadeh/zarvan.git"
    source: git
    version: "0.1.0"
''';

const _pathLock = '''
packages:
  zarvan_core:
    dependency: "direct main"
    description:
      path: "../../packages/zarvan_core"
      relative: true
    source: path
    version: "0.1.0"
''';

void main() {
  test('a git dependency yields the first 7 chars of resolved-ref', () {
    expect(engineCommitFromLock(_gitLock), '0123456');
  });

  test('a path dependency or empty lock has no commit in the lock', () {
    expect(engineCommitFromLock(_pathLock), isNull);
    expect(engineCommitFromLock('packages: {}'), isNull);
  });

  group('resolveEngineCommit', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('commit'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a git lock without calling git', () {
      File('${dir.path}/pubspec.lock').writeAsStringSync(_gitLock);
      expect(
        resolveEngineCommit(dir.path, describe: (_) => fail('no git needed')),
        '0123456',
      );
    });

    test('asks git describe in the engine checkout for a path dependency', () {
      File('${dir.path}/pubspec.lock').writeAsStringSync(_pathLock);
      String? asked;
      final commit = resolveEngineCommit(
        dir.path,
        describe: (d) {
          asked = d;
          return 'v0.1.0-4-gabc1234';
        },
      );
      expect(commit, 'v0.1.0-4-gabc1234');
      expect(asked, endsWith('packages/zarvan_core'));
    });

    test('is null without a pubspec.lock', () {
      expect(resolveEngineCommit(dir.path, describe: (_) => 'x'), isNull);
    });
  });
}
