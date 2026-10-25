import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

Map<String, dynamic> level(Scratch s, [String path = lv]) =>
    jsonDecode(s.read(path)) as Map<String, dynamic>;

Map<String, dynamic> entity(Scratch s, String name, {String path = lv}) =>
    (level(s, path)['entities'] as List).cast<Map<String, dynamic>>().firstWhere(
      (e) => e['name'] == name,
    );

void main() {
  test(
    'level.create writes a canonical file and refuses to overwrite',
    () async {
      final s = await Scratch.create();
      final d = await s.map('level.create', {'path': 'assets/levels/new.json'});
      expect(d['entities'], 0);
      expect(level(s, 'assets/levels/new.json'), {'entities': []});
      expect(
        await s.failure('level.create', {'path': 'assets/levels/new.json'}),
        ErrorCode.conflict,
      );
    },
  );

  test(
    'level.add_entity uses schema defaults, overrides and an index',
    () async {
      final s = await Scratch.create();
      final d = await s.map('level.add_entity', {
        'path': lv,
        'name': 'gem',
        'components': ['position'],
        'values': {
          'position': {'x': 5.0},
        },
        'index': 0,
      });
      expect(d['index'], 0);
      final first = (level(s)['entities'] as List).first as Map;
      expect(first['name'], 'gem');
      expect((first['components'] as Map)['position']['x'], 5.0);
      expect(
        await s.failure('level.add_entity', {
          'path': lv,
          'components': ['nope'],
        }),
        ErrorCode.invalidParams,
      );
      expect(
        await s.failure('level.add_entity', {'path': lv, 'index': 99}),
        ErrorCode.invalidParams,
      );
    },
  );

  test('level.remove_entity is destructive: preview, then token', () async {
    final s = await Scratch.create();
    final preview = await s.map('level.remove_entity', {
      'path': lv,
      'name': 'coin_1',
    });
    expect(preview['confirmation'], isA<String>());
    expect(s.read(lv), contains('coin_1'));
    final done = await s.call('level.remove_entity', {
      'path': lv,
      'name': 'coin_1',
      'confirmation': preview['confirmation'],
    });
    expect(done.ok, isTrue, reason: '${done.error}');
    expect(s.read(lv), isNot(contains('coin_1')));
    expect(
      await s.failure('level.remove_entity', {'path': lv, 'name': 'ghost'}),
      ErrorCode.notFound,
    );
  });

  test(
    'move, set_field and set_layer edit the right values and report before/after',
    () async {
      final s = await Scratch.create();
      await s.data('level.move_entity', {
        'path': lv,
        'name': 'player',
        'x': 1.5,
        'y': 2.5,
      });
      expect(entity(s, 'player')['components']['position'], {
        'x': 1.5,
        'y': 2.5,
      });
      final f = await s.map('level.set_field', {
        'path': lv,
        'entity': 'player',
        'component': 'position',
        'field': 'x',
        'value': 9.0,
      });
      expect(f, {'before': 1.5, 'after': 9.0});
      expect(
        await s.failure('level.set_field', {
          'path': lv,
          'entity': 'player',
          'component': 'position',
          'field': 'x',
          'value': 'left',
        }),
        ErrorCode.validationFailed,
        reason:
            'an edit that makes the level invalid is refused and nothing is written',
      );
      expect(entity(s, 'player')['components']['position']['x'], 9.0);
      expect(
        await s.failure('level.set_layer', {
          'path': lv,
          'entity': 'player',
          'component': 'sprite',
          'z': 2,
        }),
        ErrorCode.notFound,
      );
    },
  );

  test('add_component / remove_component round trip', () async {
    final s = await Scratch.create();
    final before = s.read(lv);
    await s.data('level.add_component', {
      'path': lv,
      'entity': 'player',
      'component': 'velocity',
    });
    expect(entity(s, 'player')['components'], contains('velocity'));
    expect(
      await s.failure('level.add_component', {
        'path': lv,
        'entity': 'player',
        'component': 'velocity',
      }),
      ErrorCode.conflict,
    );
    final preview = await s.map('level.remove_component', {
      'path': lv,
      'entity': 'player',
      'component': 'velocity',
    });
    await s.data('level.remove_component', {
      'path': lv,
      'entity': 'player',
      'component': 'velocity',
      'confirmation': preview['confirmation'],
    });
    expect(jsonDecode(s.read(lv)), jsonDecode(before));
  });

  test('paint_tile and fill_region change tiles and validate bounds', () async {
    final s = await Scratch.create();
    await s.data('level.paint_tile', {
      'path': lv,
      'entity': 'ground',
      'col': 0,
      'row': 0,
      'tileId': 1,
    });
    expect(entity(s, 'ground')['components']['tileMap']['tiles'], [
      1,
      0,
      0,
      0,
      1,
      1,
      1,
      1,
    ]);
    final r = await s.map('level.fill_region', {
      'path': lv,
      'entity': 'ground',
      'col': 3,
      'row': 0,
      'tileId': 1,
    });
    expect(r['filled'], 3);
    expect(
      await s.failure('level.paint_tile', {
        'path': lv,
        'entity': 'ground',
        'col': 9,
        'row': 0,
        'tileId': 1,
      }),
      ErrorCode.invalidParams,
    );
    expect(
      await s.failure('level.paint_tile', {
        'path': lv,
        'entity': 'player',
        'col': 0,
        'row': 0,
        'tileId': 1,
      }),
      ErrorCode.invalidParams,
    );
  });

  test('paint_tile flattens a legend-authored tileMap first', () async {
    final s = await Scratch.create();
    s.write(
      'assets/levels/legend.json',
      jsonEncode({
        'entities': [
          {
            'name': 'map',
            'components': {
              'position': {'x': 0, 'y': 0},
              'tileMap': {
                'tileWidth': 10,
                'tileHeight': 10,
                'legend': {'.': 0, '#': 1},
                'rows': ['..', '..'],
              },
            },
          },
        ],
      }),
    );
    await s.data('level.paint_tile', {
      'path': 'assets/levels/legend.json',
      'entity': 'map',
      'col': 0,
      'row': 0,
      'tileId': 1,
    });
    final map = entity(s, 'map', path: 'assets/levels/legend.json')['components']
        ['tileMap'] as Map;
    expect(map.containsKey('legend'), isFalse);
    expect(map['tiles'], [1, 0, 0, 0]);
  });

  test('every write is undoable', () async {
    final s = await Scratch.create();
    final before = s.read(lv);
    await s.data('level.move_entity', {
      'path': lv,
      'name': 'player',
      'x': 0.0,
      'y': 0.0,
    });
    expect(s.read(lv), isNot(before));
    await s.data('undo.undo');
    expect(s.read(lv), before);
  });

  test('level.lock / unlock hold, refuse others and release', () async {
    final s = await Scratch.create();
    final d = await s.map('level.lock', {'path': lv});
    expect(d['owner'], isA<String>());
    expect((await s.map('level.lock_status', {'path': lv}))['locked'], isTrue);
    await s.data('level.lock', {'path': lv});
    await s.data('level.unlock', {'path': lv});
    expect((await s.map('level.lock_status', {'path': lv}))['locked'], isFalse);

    s.write(
      '$lv.lock',
      jsonEncode({
        'owner': 'someone-else',
        'acquiredAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    expect(await s.failure('level.lock', {'path': lv}), ErrorCode.locked);
    expect(await s.failure('level.unlock', {'path': lv}), ErrorCode.locked);
    await s.data('level.unlock', {'path': lv, 'force': true});
    expect(s.exists('$lv.lock'), isFalse);
  });

  test(
    'level.export_canonical rewrites only reformatted levels and skips broken ones',
    () async {
      final s = await Scratch.create();
      s.write(
        'assets/levels/ugly.json',
        '{"entities":[{"name":"a","components":{"position":{"x":1,"y":2}}}]}',
      );
      final d = await s.map('level.export_canonical');
      expect(d['rewritten'], contains('assets/levels/ugly.json'));
      expect(d['rewritten'], isNot(contains('assets/levels/level1.json')));
      expect(d['skipped'], ['assets/levels/broken.json']);
      expect(s.read('assets/levels/ugly.json'), contains('\n  "entities"'));
      expect((await s.map('level.export_canonical'))['rewritten'], isEmpty);
    },
  );

  test(
    'level.merge returns the merge, and writes only when conflict-free',
    () async {
      final s = await Scratch.create();
      Map<String, dynamic> moved(String who, double x) => {
        'entities': [
          {
            'name': 'a',
            'components': {
              'position': {'x': x, 'y': 0.0},
            },
          },
          {
            'name': who,
            'components': {
              'position': {'x': 1.0, 'y': 1.0},
            },
          },
        ],
      };
      final base = {
        'entities': [
          {
            'name': 'a',
            'components': {
              'position': {'x': 0.0, 'y': 0.0},
            },
          },
        ],
      };
      s.write('b.json', jsonEncode(base));
      s.write('o.json', jsonEncode(moved('ours_only', 0.0)));
      s.write('t.json', jsonEncode(moved('theirs_only', 5.0)));
      final args = {'base': 'b.json', 'ours': 'o.json', 'theirs': 't.json'};
      final r = await s.map('level.merge', args);
      expect(r['conflicts'], isEmpty);
      expect(((r['merged']! as Map)['entities'] as List).length, 3);
      await s.data('level.merge', {...args, 'output': 'assets/levels/m.json'});
      expect(s.exists('assets/levels/m.json'), isTrue);

      s.write('t.json', jsonEncode(moved('theirs_only', 5.0)));
      s.write('o.json', jsonEncode(moved('ours_only', 7.0)));
      final c = await s.map('level.merge', args);
      expect((c['conflicts'] as List).single['entity'], 'a');
      expect(
        await s.failure('level.merge', {
          ...args,
          'output': 'assets/levels/m2.json',
        }),
        ErrorCode.conflict,
      );
      expect(s.exists('assets/levels/m2.json'), isFalse);
    },
  );
}
