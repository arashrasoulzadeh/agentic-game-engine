import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  group('LevelHandle', () {
    test('load spawns the entities and tracks their ids, named and unnamed', () {
      final world = _buildWorld();
      final handle = LevelHandle.load(world, {
        'entities': [
          {
            'name': 'player',
            'components': {'position': {'x': 0, 'y': 0}},
          },
          {
            'components': {'position': {'x': 10, 'y': 10}},
          },
        ],
      });

      expect(world.entities.count, 2);
      expect(handle.entityIds, hasLength(2));
      expect(handle.named, {'player': handle.entityIds.firstWhere(
          (id) => world.storeOf<Position>().get(id)!.x == 0)});
    });

    test('reload destroys every entity from the previous load before spawning the new set',
        () {
      final world = _buildWorld();
      LevelHandle.load(world, {
        'entities': [
          {'components': {'position': {'x': 0, 'y': 0}}},
          {'components': {'position': {'x': 1, 'y': 1}}},
          {'components': {'position': {'x': 2, 'y': 2}}},
        ],
      });
      expect(world.entities.count, 3);
      final handle = LevelHandle.load(world, {
        'entities': [
          {'components': {'position': {'x': 0, 'y': 0}}},
          {'components': {'position': {'x': 1, 'y': 1}}},
          {'components': {'position': {'x': 2, 'y': 2}}},
        ],
      });
      // Recreate under a fresh handle so its own tracked ids (not any
      // earlier world state) are what reload() tears down below.
      expect(world.entities.count, 6);

      handle.reload({
        'entities': [
          {'components': {'position': {'x': 99, 'y': 99}}},
        ],
      });

      // Only this handle's 3 tracked entities were torn down; the
      // other, untracked 3 from the first load are untouched, plus the
      // 1 freshly spawned by reload.
      expect(world.entities.count, 4);
      expect(handle.entityIds, hasLength(1));
      final remaining = world.storeOf<Position>().get(handle.entityIds.single)!;
      expect(remaining.x, 99);
    });

    test('reload leaves entities that existed before the level was loaded untouched', () {
      final world = _buildWorld();
      final preExisting = world.spawn();
      world.storeOf<Position>().set(preExisting, Position(500, 500));

      final handle = LevelHandle.load(world, {
        'entities': [
          {'components': {'position': {'x': 0, 'y': 0}}},
        ],
      });

      handle.reload({
        'entities': [
          {'components': {'position': {'x': 1, 'y': 1}}},
          {'components': {'position': {'x': 2, 'y': 2}}},
        ],
      });

      expect(world.entities.isAlive(preExisting), isTrue);
      expect(world.storeOf<Position>().get(preExisting)!.x, 500);
      expect(world.entities.count, 3, reason: 'pre-existing + 2 new from the reload');
    });

    test('reload updates named entities to the new load\'s set, dropping stale names', () {
      final world = _buildWorld();
      final handle = LevelHandle.load(world, {
        'entities': [
          {'name': 'door', 'components': {'position': {'x': 0, 'y': 0}}},
        ],
      });
      expect(handle.named.containsKey('door'), isTrue);

      handle.reload({
        'entities': [
          {'name': 'player', 'components': {'position': {'x': 5, 'y': 5}}},
        ],
      });

      expect(handle.named.containsKey('door'), isFalse);
      expect(handle.named.containsKey('player'), isTrue);
    });

    test('reload with malformed JSON throws and leaves the previous level fully intact',
        () {
      final world = _buildWorld();
      final handle = LevelHandle.load(world, {
        'entities': [
          {'name': 'player', 'components': {'position': {'x': 0, 'y': 0}}},
        ],
      });
      final originalIds = handle.entityIds;

      expect(
        () => handle.reload({'entities': 'not a list'}),
        throwsA(isA<LevelLoadException>()),
      );

      expect(world.entities.count, 1,
          reason: 'a rejected reload must not have torn down the working level');
      expect(handle.entityIds, originalIds);
      expect(world.entities.isAlive(originalIds.single), isTrue);
    });
  });
}
