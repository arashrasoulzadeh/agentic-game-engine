import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test(
    'project.open opens a project, reports its info and enables project operations',
    () async {
      final s = await Scratch.create(open: false);
      expect(await s.failure('project.info'), ErrorCode.notFound);
      final info = await s.map('project.open', {'path': s.dir.path});
      expect(info['name'], 'ops_demo');
      expect(info['version'], '1.2.3');
      expect(info['flutterProject'], isTrue);
      expect((info['engine']! as Map)['engine_core'], 'main');
      expect(info['counts'], {
        'levels': 3,
        'graphs': 1,
        'prefabs': 0,
        'codeFiles': 1,
      });
      expect((await s.map('project.info'))['name'], 'ops_demo');
    },
  );

  test('project.open refuses folders that are not projects', () async {
    final s = await Scratch.create(open: false);
    final empty = Directory.systemTemp.createTempSync('not_a_project');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(
      await s.failure('project.open', {'path': empty.path}),
      ErrorCode.notFound,
    );
    expect(
      await s.failure('project.open', {'path': '${s.dir.path}/nope'}),
      ErrorCode.notFound,
    );
  });

  test('a server bound to one project refuses to open or switch', () async {
    final s = await Scratch.create();
    final fixed = OpContext(project: s.ctx.project, allowProjectOpen: false);
    final r = await s.registry.call('project.open', {
      'path': s.dir.path,
    }, fixed);
    expect(r.error!.code, ErrorCode.forbidden);
    final noSwitch = OpContext(
      project: s.ctx.project,
      allowProjectSwitch: false,
    );
    expect(
      (await s.registry.call('project.open', {
        'path': s.dir.path,
      }, noSwitch)).error!.code,
      ErrorCode.forbidden,
    );
  });

  test('a fixed server cannot get around the lock by closing first', () async {
    final s = await Scratch.create();
    final noSwitch = OpContext(
      project: s.ctx.project,
      allowProjectSwitch: false,
    );
    expect(
      (await s.registry.call('project.close', {}, noSwitch)).error!.code,
      ErrorCode.forbidden,
    );
    expect(noSwitch.project, isNotNull);
  });

  test('allowOpen restricts which folders project.open accepts', () async {
    final s = await Scratch.create(open: false);
    final inside = OpContext(
      allowOpen: ['${s.dir.resolveSymbolicLinksSync()}*'],
    );
    expect(
      (await s.registry.call('project.open', {'path': s.dir.path}, inside)).ok,
      isTrue,
    );
    final elsewhere = OpContext(allowOpen: ['/nonexistent/*']);
    final r = await s.registry.call('project.open', {
      'path': s.dir.path,
    }, elsewhere);
    expect(r.error!.code, ErrorCode.forbidden);
    expect(elsewhere.project, isNull);
  });

  test('project.close forgets the project', () async {
    final s = await Scratch.create();
    expect((await s.map('project.close'))['closed'], isTrue);
    expect(await s.failure('project.info'), ErrorCode.notFound);
  });

  test(
    'project.tree lists files, filters by kind and truncates with a warning',
    () async {
      final s = await Scratch.create();
      final all = await s.map('project.tree');
      final paths = [
        for (final e in (all['entries']! as List)) (e as Map)['path'],
      ];
      expect(
        paths,
        containsAll([
          'pubspec.yaml',
          'lib/main.dart',
          'assets/levels/level1.json',
          'graphs/graph1.json',
        ]),
      );
      final levels = await s.map('project.tree', {'filter': 'level'});
      expect([
        for (final e in (levels['entries']! as List)) (e as Map)['path'],
      ], everyElement(contains('assets/levels/')));
      final r = await s.call('project.tree', {'limit': 2});
      expect((r.data! as Map)['truncated'], isTrue);
      expect(r.warnings.single, contains('showing 2 of'));
      expect(
        await s.failure('project.tree', {'filter': 'bogus'}),
        ErrorCode.invalidParams,
      );
    },
  );

  test(
    'project.search finds text with file, line and column, and honours the limit',
    () async {
      final s = await Scratch.create();
      final r = await s.map('project.search', {'query': 'hero'});
      final m = (r['matches']! as List).single as Map;
      expect(m['path'], 'lib/main.dart');
      expect(m['line'], 0);
      expect(m['text'], contains('Hero'));
      expect(
        ((await s.map('project.search', {'query': 'player'}))['matches']!
            as List),
        isNotEmpty,
      );
      expect(
        ((await s.map('project.search', {'query': 'zzz-nothing'}))['matches']!
            as List),
        isEmpty,
      );
      expect(
        ((await s.map('project.search', {
          'query': 'position',
          'limit': 1,
        }))['truncated']),
        isTrue,
      );
    },
  );

  test(
    'project.validate reports each level and ok is false when any has errors',
    () async {
      final s = await Scratch.create();
      final r = await s.map('project.validate');
      expect(r['ok'], isFalse);
      final byPath = {
        for (final l in (r['levels']! as List)) (l as Map)['path']: l,
      };
      expect(byPath['assets/levels/level1.json']!['ok'], isTrue);
      expect(byPath['assets/levels/level1.json']!['entities'], 3);
      expect(byPath['assets/levels/broken.json']!['ok'], isFalse);
      expect(
        (byPath['assets/levels/broken.json']!['errors'] as List).single,
        contains('x.position'),
      );
      expect(r['errors'], 1);
      File('${s.dir.path}/assets/levels/broken.json').deleteSync();
      expect((await s.map('project.validate'))['ok'], isTrue);
    },
  );

  test(
    'project.validate treats invalid JSON as an error and skips the play-test snapshot',
    () async {
      final s = await Scratch.create();
      s.write('assets/levels/broken.json', '{nope');
      s.write('assets/levels/playtest.level.json', '{not even json');
      final r = await s.map('project.validate');
      final paths = [
        for (final l in (r['levels']! as List)) (l as Map)['path'],
      ];
      expect(paths, isNot(contains('assets/levels/playtest.level.json')));
      final broken = (r['levels']! as List).cast<Map>().firstWhere(
        (l) => l['path'] == 'assets/levels/broken.json',
      );
      expect((broken['errors'] as List).single, contains('not valid JSON'));
    },
  );

  test(
    'project.git_status works without git and in a real repository',
    () async {
      final s = await Scratch.create();
      final none = await s.map('project.git_status');
      expect(none['changes'], isA<Map>());
      final git = await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: s.dir.path);
      if (git.exitCode != 0) return; // no git on this machine
      final r = await s.map('project.git_status');
      expect((r['changes']! as Map).values, everyElement('?'));
      expect(r['available'], isTrue);
    },
  );

  test('a read-only server still serves every project read', () async {
    final s = await Scratch.create(readOnly: true);
    for (final op in ['project.info', 'project.tree', 'project.validate']) {
      expect((await s.call(op)).ok, isTrue, reason: op);
    }
  });

  test(
    'project.read_file serves text, refuses binary, the token, escapes and big files',
    () async {
      final s = await Scratch.create();
      final r = await s.map('project.read_file', {'path': 'lib/main.dart'});
      expect(r['text'], 'class Hero {}\n');
      expect(
        await s.failure('project.read_file', {'path': 'lib/none.dart'}),
        ErrorCode.notFound,
      );
      expect(
        await s.failure('project.read_file', {'path': '../etc/passwd'}),
        ErrorCode.invalidParams,
      );
      File('${s.dir.path}/blob.bin').writeAsBytesSync([0xff, 0xfe, 0x00, 0x80]);
      expect(
        await s.failure('project.read_file', {'path': 'blob.bin'}),
        ErrorCode.forbidden,
      );
      s.write('.studio/api-token', 'secret');
      expect(
        await s.failure('project.read_file', {'path': '.studio/api-token'}),
        ErrorCode.forbidden,
      );
      s.write('big.txt', 'x' * (1024 * 1024 + 1));
      expect(
        await s.failure('project.read_file', {'path': 'big.txt'}),
        ErrorCode.tooLarge,
      );
    },
  );
}
