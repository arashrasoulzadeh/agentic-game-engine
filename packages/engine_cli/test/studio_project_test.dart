import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

const _legendLevel = '''
{"entities":[{"name":"map","components":{"position":{"x":0,"y":0},"tileMap":{"tileWidth":10,"tileHeight":10,"legend":{".":0,"#":1},"rows":["..#","###"]}}}]}
''';

const _invalidLevel = '''
{"entities":[{"name":"player","components":{"position":{"x":"left","y":0}}}]}
''';

const _pubspec = '''
name: my_game
dependencies:
  engine_core:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_core
      ref: v0.1.0
''';

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('studio_project');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
  });
  tearDown(() => project.deleteSync(recursive: true));

  File level(String name) => File('${project.path}/assets/levels/$name');

  group('export-levels', () {
    test('rewrites a level in canonical form, keeping its data', () async {
      level('map.json').writeAsStringSync(_legendLevel);
      expect(await runStudio(['export-levels', project.path]), 0);

      final written = level('map.json').readAsStringSync();
      expect(written, contains('\n  "entities"'), reason: 'two-space indent');
      expect(jsonDecode(written), jsonDecode(_legendLevel));
    });

    test('is idempotent: a second run writes identical bytes', () async {
      level('map.json').writeAsStringSync(_legendLevel);
      await runStudio(['export-levels', project.path]);
      final first = level('map.json').readAsStringSync();
      await runStudio(['export-levels', project.path]);
      expect(level('map.json').readAsStringSync(), first);
    });

    test('leaves an invalid level unchanged and exits 1', () async {
      level('bad.json').writeAsStringSync(_invalidLevel);
      expect(await runStudio(['export-levels', project.path]), 1);
      expect(level('bad.json').readAsStringSync(), _invalidLevel);
    });

    test(
      'with --out, writes to that directory and leaves the originals alone',
      () async {
        level('map.json').writeAsStringSync(_legendLevel);
        final out = Directory('${project.path}/canonical')..createSync();
        expect(
          await runStudio(['export-levels', project.path, '--out', out.path]),
          0,
        );
        expect(File('${out.path}/map.json').existsSync(), isTrue);
        expect(level('map.json').readAsStringSync(), _legendLevel);
      },
    );

    test('exits 1 when the project has no levels', () async {
      final empty = Directory.systemTemp.createTempSync('studio_empty');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(await runStudio(['export-levels', empty.path]), 1);
    });
  });

  group('project-manifest', () {
    test(
      'writes name, the engine ref the project pins, and its levels',
      () async {
        File('${project.path}/pubspec.yaml').writeAsStringSync(_pubspec);
        level('map.json').writeAsStringSync(_legendLevel);
        expect(await runStudio(['project-manifest', project.path]), 0);

        final manifest =
            jsonDecode(File('${project.path}/project.json').readAsStringSync())
                as Map<String, dynamic>;
        expect(manifest['name'], 'my_game');
        expect(manifest['engineVersion'], 'v0.1.0');
        expect(manifest['levels'], ['assets/levels/map.json']);
      },
    );

    test('keeps keys the manifest does not own when it updates', () async {
      File('${project.path}/pubspec.yaml').writeAsStringSync(_pubspec);
      File(
        '${project.path}/project.json',
      ).writeAsStringSync('{"notes": "keep me", "name": "old"}');
      await runStudio(['project-manifest', project.path]);

      final manifest =
          jsonDecode(File('${project.path}/project.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['notes'], 'keep me');
      expect(
        manifest['name'],
        'my_game',
        reason: 'name comes from pubspec.yaml',
      );
    });

    test(
      'reports "unknown" when the project does not pin engine_core by git ref',
      () async {
        File(
          '${project.path}/pubspec.yaml',
        ).writeAsStringSync('name: local_game\n');
        await runStudio(['project-manifest', project.path]);
        final manifest =
            jsonDecode(File('${project.path}/project.json').readAsStringSync())
                as Map<String, dynamic>;
        expect(manifest['engineVersion'], 'unknown');
      },
    );

    test('exits 1 when there is no pubspec.yaml', () async {
      expect(await runStudio(['project-manifest', project.path]), 1);
      expect(File('${project.path}/project.json').existsSync(), isFalse);
    });
  });
}
