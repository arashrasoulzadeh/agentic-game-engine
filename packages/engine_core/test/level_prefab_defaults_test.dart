import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

PrefabRegistry _registry() => PrefabRegistry()
  ..registerJson({
    'name': 'torch',
    'entities': [
      {
        'name': 'flame',
        'components': {
          'position': {'x': 0.0, 'y': 0.0},
          'collider': {'radius': 2.0},
        },
      },
    ],
  });

void main() {
  _handleTests();
  group('prefabRef', () {
    test('a placeholder is replaced by the prefab at its position', () {
      final world = _world();
      final named = Level.loadInto(world, {
        'entities': [
          {
            'name': 'wallTorch',
            'components': {
              'prefabRef': {'name': 'torch'},
              'position': {'x': 30.0, 'y': 40.0},
            },
          },
        ],
      }, prefabs: _registry());
      expect(world.componentsOf<PrefabRef>().length, 0);
      final id = named['wallTorch']!;
      expect(world.getComponent<Position>(id)!.x, 30);
      expect(world.getComponent<Collider>(id)!.radius, 2);
      expect(world.find('wallTorch'), id);
      expect(world.entities.count, 1);
    });

    test('without a registry the placeholder is left alone', () {
      final world = _world();
      Level.loadInto(world, {
        'entities': [
          {
            'components': {
              'prefabRef': {'name': 'torch'},
            },
          },
        ],
      });
      expect(world.componentsOf<PrefabRef>().length, 1);
    });

    test('an unknown prefab name fails and lists the known ones', () {
      final world = _world();
      expect(
        () => Level.loadInto(world, {
          'entities': [
            {
              'components': {
                'prefabRef': {'name': 'lamp'},
              },
            },
          ],
        }, prefabs: _registry()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Known: torch'),
          ),
        ),
      );
    });

    test('expandRefs only touches the entities it is given', () {
      final world = _world();
      final a = world.spawnWith([PrefabRef('torch'), Position(1, 1)]);
      final b = world.spawnWith([PrefabRef('torch'), Position(2, 2)]);
      final out = _registry().expandRefs(world, only: [a]);
      expect(out.keys, [a]);
      expect(world.entities.isAlive(a), isFalse);
      expect(world.entities.isAlive(b), isTrue);
    });
  });

  group('defaults', () {
    final level = {
      'entities': [
        {
          'name': 'p',
          'components': {
            'position': {'x': 5.0},
          },
        },
      ],
    };

    test('off by default: a missing field still fails', () {
      expect(
        () => Level.loadInto(_world(), level),
        throwsA(isA<ComponentApplyException>()),
      );
    });

    test('on: schema defaults fill what the level leaves out', () {
      final world = _world();
      final named = Level.loadInto(world, level, defaults: true);
      final p = world.getComponent<Position>(named['p']!)!;
      expect([p.x, p.y], [5, 0]);
    });

    test('an authored value always wins over the default', () {
      final world = _world();
      final named = Level.loadInto(world, {
        'entities': [
          {
            'name': 'p',
            'components': {
              'position': {'x': 5.0, 'y': 9.0},
            },
          },
        ],
      }, defaults: true);
      expect(world.getComponent<Position>(named['p']!)!.y, 9);
    });

    test('strict plus defaults accepts the filled component', () {
      final world = _world();
      expect(
        () => Level.loadInto(world, level, strict: true, defaults: true),
        returnsNormally,
      );
    });
  });
}

void _handleTests() {
  group('LevelHandle reload', () {
    Map<String, dynamic> level(String component) => {
      'entities': [
        {
          'name': 'p',
          'components': {
            component: {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    };

    test('strict rejects a typo before tearing the running level down', () {
      final world = _world();
      final handle = LevelHandle.load(world, level('position'), strict: true);
      final before = handle.named['p']!;
      expect(
        () => handle.reload(level('positon')),
        throwsA(isA<LevelLoadException>()),
      );
      expect(world.entities.isAlive(before), isTrue, reason: 'untouched');
      expect(handle.named['p'], before);
    });

    test('without strict the typo silently drops the component (the gap)', () {
      final world = _world();
      final handle = LevelHandle.load(world, level('position'));
      handle.reload(level('positon'));
      expect(world.getComponent<Position>(handle.named['p']!), isNull);
    });

    test('options carry over to reload: defaults fill what an edit omits', () {
      final world = _world();
      final handle = LevelHandle.load(world, level('position'), defaults: true);
      handle.reload({
        'entities': [
          {
            'name': 'p',
            'components': {
              'position': {'x': 9.0},
            },
          },
        ],
      });
      final p = world.getComponent<Position>(handle.named['p']!)!;
      expect([p.x, p.y], [9, 0]);
    });
  });
}
