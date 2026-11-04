import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

(World, PrefabRegistry) _setup() {
  final world = World(width: 200, height: 200, seed: 7);
  registerCoreComponents(world);
  final registry = PrefabRegistry()
    ..register(
      Prefab(
        name: 'coin',
        entities: [
          LevelEntity(
            name: 'coin',
            components: {
              'position': {'x': 0, 'y': 0},
            },
          ),
        ],
      ),
    );
  world.addSystem(SpawnerSystem(registry));
  return (world, registry);
}

EntityId _spawner(World world, Spawner s, {double x = 100, double y = 100}) {
  final id = world.spawn();
  world.componentsOf<Position>().set(id, Position(x, y));
  world.componentsOf<Spawner>().set(id, s);
  return id;
}

int _coins(World world) => world.componentsOf<SpawnedBy>().length;

void main() {
  test('spawns on its period after the delay', () {
    final (world, _) = _setup();
    _spawner(world, Spawner(prefab: 'coin', every: 1, delay: 2));
    for (var i = 0; i < 19; i++) {
      world.step(0.1); // 1.9 s: nothing yet
    }
    expect(_coins(world), 0);
    world.step(0.1); // 2.0 s: the first spawn is due at the delay
    expect(_coins(world), 1);
    for (var i = 0; i < 30; i++) {
      world.step(0.1); // 3 more seconds: spawns at 3, 4, 5
    }
    expect(_coins(world), 4);
  });

  test('count spawns several per tick of the schedule', () {
    final (world, _) = _setup();
    _spawner(world, Spawner(prefab: 'coin', every: 1, count: 3));
    world.step(0.5); // the first spawn is at once
    expect(_coins(world), 3);
    world.step(0.6); // the next is due at 1.0 s
    expect(_coins(world), 6);
  });

  test('maxAlive holds the line and resumes without a burst', () {
    final (world, _) = _setup();
    final id = _spawner(world, Spawner(prefab: 'coin', every: 1, maxAlive: 2));
    for (var i = 0; i < 100; i++) {
      world.step(0.1); // 10 s
    }
    expect(_coins(world), 2);
    final spawnedBy = world.componentsOf<SpawnedBy>();
    world.destroy(spawnedBy.entityAt(0));
    world.step(0.1);
    expect(_coins(world), 2); // refilled to the cap at once...
    world.destroy(world.componentsOf<SpawnedBy>().entityAt(0));
    world.destroy(world.componentsOf<SpawnedBy>().entityAt(0));
    world.step(0.1);
    // ...and nothing is banked from the blocked seconds: the next spawn waits
    // for its own time instead of arriving as a burst.
    expect(_coins(world), 0);
    world.step(1.0);
    expect(_coins(world), 1);
    expect(world.componentsOf<Spawner>().get(id)!.spawned, 4);
  });

  test('total retires the spawner for good', () {
    final (world, _) = _setup();
    final id = _spawner(world, Spawner(prefab: 'coin', every: 0.5, total: 3));
    for (var i = 0; i < 100; i++) {
      world.step(0.1);
    }
    expect(world.componentsOf<Spawner>().get(id)!.spawned, 3);
    expect(world.componentsOf<Spawner>().get(id)!.retired, isTrue);
    expect(_coins(world), 3);
  });

  test('waves spawn bursts at their times, once each', () {
    final (world, _) = _setup();
    _spawner(
      world,
      Spawner(
        prefab: 'coin',
        waves: [
          const SpawnWave(at: 1, count: 2),
          const SpawnWave(at: 3, count: 5),
        ],
      ),
    );
    world.step(0.9);
    expect(_coins(world), 0);
    world.step(0.2);
    expect(_coins(world), 2);
    world.step(1.0);
    expect(_coins(world), 2);
    world.step(1.0);
    expect(_coins(world), 7);
    world.step(5.0);
    expect(_coins(world), 7);
  });

  test('inactive spawners freeze their clock', () {
    final (world, _) = _setup();
    final id = _spawner(
      world,
      Spawner(prefab: 'coin', every: 1, active: false),
    );
    world.step(5);
    expect(_coins(world), 0);
    expect(world.componentsOf<Spawner>().get(id)!.elapsed, 0);
    world.componentsOf<Spawner>().get(id)!.active = true;
    world.step(0.5);
    expect(_coins(world), 1);
  });

  test('radius scatters spawns around the spawner, inside the circle', () {
    final (world, _) = _setup();
    _spawner(world, Spawner(prefab: 'coin', every: 0.1, radius: 30));
    for (var i = 0; i < 50; i++) {
      world.step(0.1);
    }
    final positions = world.componentsOf<Position>();
    final xs = <double>{};
    for (final (_, id) in [
      for (var i = 0; i < world.componentsOf<SpawnedBy>().length; i++)
        (i, world.componentsOf<SpawnedBy>().entityAt(i)),
    ]) {
      final p = positions.get(id)!;
      final d = ((p.x - 100) * (p.x - 100) + (p.y - 100) * (p.y - 100));
      expect(d, lessThanOrEqualTo(30 * 30 + 1e-6));
      xs.add(p.x);
    }
    expect(xs.length, greaterThan(10)); // genuinely scattered
  });

  test('emits Spawned and tags the entity with its spawner', () {
    final (world, _) = _setup();
    final events = <Spawned>[];
    world.events.on<Spawned>(events.add);
    final id = _spawner(world, Spawner(prefab: 'coin', every: 1));
    world.step(0.5);
    expect(events.single.spawner, id);
    expect(events.single.prefab, 'coin');
    expect(
      world.componentsOf<SpawnedBy>().get(events.single.entity)!.spawner,
      id,
    );
  });

  test('spawns are deterministic for a seed', () {
    List<double> run() {
      final (world, _) = _setup();
      _spawner(world, Spawner(prefab: 'coin', every: 0.1, radius: 50));
      for (var i = 0; i < 20; i++) {
        world.step(0.1);
      }
      final s = world.componentsOf<SpawnedBy>();
      return [
        for (var i = 0; i < s.length; i++)
          world.componentsOf<Position>().get(s.entityAt(i))!.x,
      ];
    }

    expect(run(), run());
  });

  test('JSON round-trips including the runtime schedule state', () {
    final s = Spawner(
      prefab: 'coin',
      every: 2,
      maxAlive: 5,
      waves: [const SpawnWave(at: 3, count: 4)],
      elapsed: 1.5,
      spawned: 3,
      cycles: 2,
      waveIndex: 1,
    );
    final back = Spawner.fromJson(s.toJson());
    expect(
      (back.prefab, back.every, back.maxAlive, back.elapsed, back.spawned),
      ('coin', 2, 5, 1.5, 3),
    );
    expect((back.cycles, back.waveIndex, back.waves.single.count), (2, 1, 4));
  });

  test(
    'the components are registered with schemas for the studio and agents',
    () {
      final world = World(width: 1, height: 1);
      registerCoreComponents(world);
      expect(world.components.isRegistered('spawner'), isTrue);
      expect(world.components.isRegistered('spawnedBy'), isTrue);
    },
  );
}
