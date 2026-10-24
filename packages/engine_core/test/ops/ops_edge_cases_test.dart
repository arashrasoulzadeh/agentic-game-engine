import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';
const g = 'graphs/g.json';

void main() {
  group('level writes', () {
    test('set_layer writes zIndex on an existing component', () async {
      final s = await Scratch.create();
      final r = await s.map('level.set_layer', {
        'path': lv,
        'entity': 'ground',
        'component': 'tileMap',
        'z': 3,
      });
      expect(
        ((r['entity']! as Map)['components'] as Map)['tileMap']['zIndex'],
        3,
      );
    });

    test('add_entity without an index reports where it landed', () async {
      final s = await Scratch.create();
      final r = await s.map('level.add_entity', {'path': lv, 'name': 'gem'});
      expect(r['index'], 3);
    });

    test('remove_component on a missing component is not_found', () async {
      final s = await Scratch.create();
      expect(
        await s.failure('level.remove_component', {
          'path': lv,
          'entity': 'player',
          'component': 'velocity',
        }),
        ErrorCode.notFound,
      );
    });

    test(
      'export_canonical names missing files and skips levels that do not load',
      () async {
        final s = await Scratch.create();
        expect(
          await s.failure('level.export_canonical', {
            'paths': ['assets/levels/none.json'],
          }),
          ErrorCode.notFound,
        );
        s.write('assets/levels/shape.json', '{"entities": 5}');
        final r = await s.map('level.export_canonical', {
          'paths': ['assets/levels/shape.json'],
        });
        expect(r['skipped'], ['assets/levels/shape.json']);
      },
    );

    test(
      'a lock held by someone else blocks every write to that level',
      () async {
        final s = await Scratch.create();
        s.write(
          '$lv.lock',
          jsonEncode({
            'owner': 'someone-else',
            'acquiredAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        final r = await s.call('level.move_entity', {
          'path': lv,
          'name': 'player',
          'x': 1,
          'y': 1,
        });
        expect(r.error!.code, ErrorCode.locked);
        expect(r.error!.details!['owner'], 'someone-else');
        expect(
          jsonDecode(s.read(lv))['entities'][1]['components']['position']['x'],
          24.0,
        );
      },
    );

    test('undoing a created level deletes the file again', () async {
      final s = await Scratch.create();
      await s.data('level.create', {'path': 'assets/levels/tmp.json'});
      expect(s.exists('assets/levels/tmp.json'), isTrue);
      await s.data('undo.undo');
      expect(s.exists('assets/levels/tmp.json'), isFalse);
    });
  });

  group('graphs', () {
    test(
      'validate lists issues with node ids; list shows unreadable files',
      () async {
        final s = await Scratch.create();
        await s.data('graph.create', {'path': g});
        await s.data('graph.add_node', {'path': g, 'kind': 'say'});
        await s.data('graph.add_node', {'path': g, 'kind': 'say'});
        final v = await s.map('graph.validate', {'path': g});
        expect(v['ok'], isFalse);
        final issue = (v['issues']! as List).cast<Map>().firstWhere(
          (i) => i['nodeId'] == 'say1',
        );
        expect(issue['kind'], isNotEmpty);
        expect(issue['message'], isNotEmpty);
        s.write('graphs/junk.json', '{"graph": 5}');
        final list = (await s.data('graph.list') as List).cast<Map>();
        expect(
          list.firstWhere((e) => e['path'] == 'graphs/junk.json'),
          contains('error'),
        );
      },
    );

    test('choice nodes expose one output port per choice id', () async {
      final s = await Scratch.create();
      await s.data('graph.create', {'path': g});
      await s.data('graph.add_node', {
        'path': g,
        'kind': 'choice',
        'id': 'ask',
        'params': {
          'choices': [
            {'id': 'yes', 'textKey': 'y'},
            {'id': 'no', 'textKey': 'n'},
          ],
        },
      });
      await s.data('graph.add_node', {'path': g, 'kind': 'say', 'id': 'ok'});
      await s.data('graph.connect', {
        'path': g,
        'from': 'ask',
        'fromPort': 'yes',
        'to': 'ok',
        'toPort': 'in',
      });
      expect(
        await s.failure('graph.connect', {
          'path': g,
          'from': 'ask',
          'fromPort': 'maybe',
          'to': 'ok',
          'toPort': 'in',
        }),
        ErrorCode.invalidParams,
      );
    });

    test('removing an unknown node is not_found', () async {
      final s = await Scratch.create();
      await s.data('graph.create', {'path': g});
      expect(
        await s.failure('graph.remove_node', {'path': g, 'id': 'ghost'}),
        ErrorCode.notFound,
      );
    });

    test(
      'auto ids skip taken ones and an unknown input port is invalid_params',
      () async {
        final s = await Scratch.create();
        await s.data('graph.create', {'path': g});
        await s.data('graph.add_node', {
          'path': g,
          'kind': 'say',
          'id': 'say1',
        });
        final n = await s.map('graph.add_node', {'path': g, 'kind': 'say'});
        expect((n['node']! as Map)['id'], 'say2');
        expect(
          await s.failure('graph.connect', {
            'path': g,
            'from': 'say1',
            'fromPort': 'out',
            'to': 'say2',
            'toPort': 'nope',
          }),
          ErrorCode.invalidParams,
        );
      },
    );

    test('state machines compile with the given id', () async {
      final s = await Scratch.create();
      await s.data('graph.create', {
        'path': 'graphs/sm.json',
        'type': 'stateMachine',
      });
      await s.data('graph.add_node', {
        'path': 'graphs/sm.json',
        'kind': 'state',
        'id': 'idle',
        'params': {'name': 'idle'},
      });
      final r = await s.map('graph.compile', {
        'path': 'graphs/sm.json',
        'id': 'door',
      });
      expect(jsonEncode(r['compiled']), contains('door'));
    });
  });

  group('worlds', () {
    test('levels that do not load, bad patches and entity filters', () async {
      final s = await Scratch.create();
      expect(
        await s.failure('world.build', {
          'json': {
            'entities': [
              {
                'components': {
                  'velocity': {'x': 'fast'},
                },
              },
            ],
          },
        }),
        ErrorCode.validationFailed,
      );
      final built = await s.map('world.build', {
        'json': {
          'entities': [
            {
              'components': {
                'position': {'x': 1.0, 'y': 1.0},
              },
            },
            {
              'components': {
                'position': {'x': 2.0, 'y': 2.0},
              },
            },
          ],
        },
        'systems': ['particles', 'tween', 'tileAnimation', 'pushable'],
      });
      final id = built['worldId']! as String;
      final all = await s.map('world.snapshot', {'worldId': id});
      final first = ((all['entities']! as List).first as Map)['id'];
      final only = await s.map('world.snapshot', {
        'worldId': id,
        'entities': [first],
      });
      expect(only['entities'], hasLength(1));
      expect(
        await s.failure('world.patch', {
          'worldId': id,
          'patch': {
            'entities': [
              {
                'id': first,
                'components': {
                  'position': {'x': 'bad'},
                },
              },
            ],
          },
        }),
        ErrorCode.validationFailed,
      );
    });
  });

  group('interchange', () {
    test(
      'export reports what Tiled cannot hold and refuses an unloadable tileMap',
      () async {
        final s = await Scratch.create();
        final data = jsonDecode(s.read(lv)) as Map<String, dynamic>;
        final ground = (data['entities'] as List).first as Map;
        ((ground['components'] as Map)['tileMap'] as Map)['ladderTileIds'] = [
          2,
        ];
        s.write(lv, jsonEncode(data));
        expect(
          (await s.map('level.export_tmx', {'path': lv}))['lost'],
          contains('ladders'),
        );
        ((ground['components'] as Map)['tileMap'] as Map)['tiles'] = 'nope';
        s.write('assets/levels/bad.json', jsonEncode(data));
        expect(
          await s.failure('level.export_tmx', {
            'path': 'assets/levels/bad.json',
          }),
          isIn([ErrorCode.validationFailed, ErrorCode.notFound]),
        );
      },
    );

    test('import of malformed XML is validation_failed', () async {
      final s = await Scratch.create();
      s.write('assets/levels/x.tmx', '<map');
      expect(
        await s.failure('level.import_tmx', {'tmx': 'assets/levels/x.tmx'}),
        ErrorCode.validationFailed,
      );
    });

    test('an unreadable prefab is validation_failed', () async {
      final s = await Scratch.create();
      s.write('prefabs/broken.json', '{nope');
      expect(
        await s.failure('prefab.read', {'name': 'broken'}),
        ErrorCode.validationFailed,
      );
    });
  });

  group('project operations', () {
    test('playable fails when the spawn sits inside a solid tile', () async {
      final s = await Scratch.create();
      await s.data('level.move_entity', {
        'path': lv,
        'name': 'player',
        'x': 24,
        'y': 24,
      });
      final r = await s.map('level.lint', {'path': lv, 'playable': true});
      expect(r['ok'], isFalse);
      expect((r['problems'] as List).single, contains('solid tile'));
    });

    test(
      'idle files that are not JSON objects, or no source at all, are reported',
      () async {
        final s = await Scratch.create();
        expect(await s.failure('idle.validate', {}), ErrorCode.invalidParams);
        s.write('assets/idle_game.json', '[1]');
        expect(
          await s.failure('idle.validate', {'path': 'assets/idle_game.json'}),
          ErrorCode.validationFailed,
        );
        final problems =
            ((await s.map('project.problems'))['problems']! as List)
                .cast<Map>();
        expect(
          problems.where((p) => p['file'] == 'assets/idle_game.json'),
          isNotEmpty,
        );
      },
    );

    test(
      'Flutter-only operations answer unsupported instead of doing anything',
      () async {
        final s = await Scratch.create();
        expect(
          await s.failure('project.create', {'name': 'x'}),
          ErrorCode.unsupported,
        );
        expect(await s.failure('project.upgrade'), ErrorCode.unsupported);
        expect(await s.failure('release.build'), ErrorCode.unsupported);
      },
    );

    test('read_file refuses text containing NUL', () async {
      final s = await Scratch.create();
      s.write('nul.txt', 'a\u0000b');
      expect(
        await s.failure('project.read_file', {'path': 'nul.txt'}),
        ErrorCode.forbidden,
      );
    });
  });
}
