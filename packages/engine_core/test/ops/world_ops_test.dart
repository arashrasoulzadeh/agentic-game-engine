import 'package:engine_core/engine_core.dart' show World;
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const moving = {
  'entities': [
    {
      'name': 'ball',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'velocity': {'x': 60.0, 'y': 0.0},
      },
    },
    {
      'name': 'still',
      'components': {
        'position': {'x': 5.0, 'y': 5.0},
      },
    },
  ],
};

void main() {
  test(
    'build, step, snapshot: movement advances the moving entity only',
    () async {
      final s = await Scratch.create();
      final built = await s.map('world.build', {'json': moving});
      expect(built['entities'], 2);
      expect(built['systems'], ['movement', 'collision']);
      final id = built['worldId']! as String;

      final stepped = await s.map('world.step', {'worldId': id, 'ticks': 60});
      expect(stepped['tick'], 60);

      final snap = await s.map('world.snapshot', {'worldId': id});
      final byId = {
        for (final e in snap['entities']! as List)
          (e as Map)['id']: e['components'] as Map,
      };
      final ball = byId[(built['named']! as Map)['ball']]!['position'] as Map;
      expect(ball['x'], closeTo(60.0, 0.5), reason: '60 px/s for one second');
      final still = byId[(built['named']! as Map)['still']]!['position'] as Map;
      expect(still['x'], 5.0);
    },
  );

  test('build from a project level; worlds touch no files', () async {
    final s = await Scratch.create();
    final before = s.read('assets/levels/level1.json');
    final id =
        (await s.map('world.build', {
              'path': 'assets/levels/level1.json',
            }))['worldId']!
            as String;
    await s.data('world.step', {'worldId': id, 'ticks': 10});
    expect(s.read('assets/levels/level1.json'), before);
  });

  test('query by component and field, patch, discard', () async {
    final s = await Scratch.create();
    final built = await s.map('world.build', {'json': moving});
    final id = built['worldId']! as String;
    final q =
        await s.data('world.query', {
              'worldId': id,
              'component': 'position',
              'where': {'x': 5.0},
            })
            as List;
    expect(q, hasLength(1));
    final entityId = (q.single as Map)['id'];
    await s.data('world.patch', {
      'worldId': id,
      'patch': {
        'entities': [
          {
            'id': entityId,
            'components': {
              'position': {'x': 99.0, 'y': 5.0},
            },
          },
        ],
      },
    });
    expect(
      ((await s.data('world.query', {
            'worldId': id,
            'component': 'position',
            'where': {'x': 99.0},
          }))
          as List),
      hasLength(1),
    );
    expect(
      await s.failure('world.patch', {
        'worldId': id,
        'patch': {'entities': 5},
      }),
      ErrorCode.validationFailed,
    );
    await s.data('world.discard', {'worldId': id});
    expect(await s.failure('world.step', {'worldId': id}), ErrorCode.notFound);
    expect(
      await s.failure('world.discard', {'worldId': id}),
      ErrorCode.notFound,
    );
  });

  test('bad systems, the world cap and expiry', () async {
    final s = await Scratch.create();
    expect(
      await s.failure('world.build', {
        'json': moving,
        'systems': ['nope'],
      }),
      ErrorCode.invalidParams,
    );
    for (var i = 0; i < 4; i++) {
      await s.data('world.build', {'json': moving});
    }
    expect(
      await s.failure('world.build', {'json': moving}),
      ErrorCode.rateLimited,
    );

    var now = DateTime(2026, 1, 1);
    final sandbox = WorldSandbox(ttl: const Duration(minutes: 10));
    final world = (await Scratch.create())
        .ctx
        .sandbox; // unused; ensures the context exposes a sandbox
    expect(world.count, 0);
    final id = sandbox.add(_world(), now)!;
    expect(sandbox.get(id, now), isNotNull);
    now = now.add(const Duration(minutes: 11));
    expect(sandbox.get(id, now), isNull, reason: 'idle worlds expire');
  });

  test('worlds are allowed on a read-only server', () async {
    final s = await Scratch.create(readOnly: true);
    expect((await s.call('world.build', {'json': moving})).ok, isTrue);
  });
}

World _world() => World(width: 10, height: 10);
