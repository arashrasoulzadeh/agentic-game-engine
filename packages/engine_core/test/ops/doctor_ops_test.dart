import 'package:engine_core/src/ops/groups/problems_ops.dart'
    show checkEngineDependencies;
import 'package:test/test.dart';

import 'support.dart';

String _pubspec(String deps) =>
    'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n$deps';

const _git = '''
  engine_core:
    git:
      url: https://example.com/e.git
      ref: main
  engine_flutter:
    git:
      url: https://example.com/e.git
      path: packages/engine_flutter
      ref: main
''';

void main() {
  group('checkEngineDependencies', () {
    test('matching git url and ref is ok and says which', () {
      final (status, detail) = checkEngineDependencies(_pubspec(_git));
      expect(status, 'ok');
      expect(detail, contains('2 engine package(s)'));
      expect(detail, contains('https://example.com/e.git @ main'));
    });

    test('different refs is an error naming each package', () {
      final (status, detail) = checkEngineDependencies(
        _pubspec(_git.replaceFirst('ref: main', 'ref: v0.1.0')),
      );
      expect(status, 'error');
      expect(
        detail,
        contains('engine_core: https://example.com/e.git @ v0.1.0'),
      );
      expect(
        detail,
        contains('engine_flutter: https://example.com/e.git @ main'),
      );
    });

    test('different urls is an error', () {
      final (status, _) = checkEngineDependencies(
        _pubspec(
          _git.replaceFirst('example.com/e.git', 'example.com/fork.git'),
        ),
      );
      expect(status, 'error');
    });

    test('a local path dependency warns', () {
      final (status, detail) = checkEngineDependencies(
        _pubspec('  engine_core:\n    path: ../engine_core\n'),
      );
      expect(status, 'warn');
      expect(detail, contains('engine_core'));
      expect(detail, contains('local path'));
    });

    test('a git subdirectory path is not mistaken for a local path', () {
      final (status, _) = checkEngineDependencies(_pubspec(_git));
      expect(status, 'ok');
    });

    test('no engine dependencies warns; hosted versions are ok', () {
      expect(
        checkEngineDependencies(_pubspec('  flutter:\n    sdk: flutter\n')).$1,
        'warn',
      );
      expect(
        checkEngineDependencies(_pubspec('  engine_core: ^1.0.0\n')).$1,
        'ok',
      );
    });

    test('dev dependencies count; dependency_overrides are ignored', () {
      final text =
          '${_pubspec(_git)}dependency_overrides:\n  engine_core:\n    path: ../x\n';
      expect(checkEngineDependencies(text).$1, 'ok');
    });
  });

  group('project.doctor', () {
    test('reports content errors, layout and dependency status', () async {
      final s = await Scratch.create();
      final r = await s.map('project.doctor');
      final checks = {
        for (final c in (r['checks']! as List).cast<Map>())
          c['name']: c['status'],
      };
      expect(checks, {
        'content': 'error',
        'layout': 'ok',
        'dependencies': 'ok',
      });
      expect(r['ok'], isFalse, reason: 'broken.json is a content error');
    });

    test('a clean project is ok', () async {
      final s = await Scratch.create();
      s.write('assets/levels/broken.json', '{"entities": []}');
      s.write(
        'graphs/graph1.json',
        '{"graph": {"nodes": [{"id": "a", "kind": "say"}], "edges": [], "entryNodeId": "a"}}',
      );
      final r = await s.map('project.doctor');
      expect(r['ok'], isTrue, reason: '${r['checks']}');
    });

    test(
      'a wiring mismatch fails the doctor even when content is clean',
      () async {
        final s = await Scratch.create();
        s.write('assets/levels/broken.json', '{"entities": []}');
        s.write(
          'graphs/graph1.json',
          '{"graph": {"nodes": [{"id": "a", "kind": "say"}], "edges": [], "entryNodeId": "a"}}',
        );
        s.write(
          'pubspec.yaml',
          _pubspec(_git.replaceFirst('ref: main', 'ref: v9')),
        );
        final r = await s.map('project.doctor');
        expect(r['ok'], isFalse);
        expect(
          (r['checks']! as List).cast<Map>().singleWhere(
            (c) => c['name'] == 'dependencies',
          )['status'],
          'error',
        );
      },
    );
  });
}
