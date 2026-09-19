import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('Collider collision groups', () {
    test('Collider constructor accepts collisionGroup and collisionMask', () {
      final collider = Collider(10, collisionGroup: 1, collisionMask: 15);
      expect(collider.collisionGroup, 1);
      expect(collider.collisionMask, 15);
    });

    test('Collider defaults to group 1, mask all (backward compat)', () {
      final collider = Collider(10);
      expect(collider.collisionGroup, 1);
      expect(collider.collisionMask, -1); // -1 = all bits set
    });

    test('round-trips through toJson/fromJson with collision groups', () {
      final collider = Collider(15, collisionGroup: 2, collisionMask: 13);
      final json = collider.toJson();
      final restored = Collider.fromJson(json);

      expect(restored.radius, 15);
      expect(restored.collisionGroup, 2);
      expect(restored.collisionMask, 13);
    });
  });

  group('TileMap collision groups', () {
    test('TileMap.fromJson accepts per-tile collision groups', () {
      final json = {
        'cols': 2,
        'rows': 2,
        'tileWidth': 10,
        'tileHeight': 10,
        'tiles': [1, 0, 0, 1],
        'solidTileIds': [1],
        'collisionGroups': {
          '1': 2, // tile id 1 belongs to group 2
        },
      };
      final map = TileMap.fromJson(json);
      expect(map.collisionGroups[1], 2);
    });

    test('TileMap defaults to group 1 for solid tiles', () {
      final map = TileMap(
        cols: 2,
        rows: 2,
        tileWidth: 10,
        tileHeight: 10,
        tiles: [1, 0, 0, 1],
        solidTileIds: {1},
      );
      expect(map.collisionGroups[1], 1); // default group 1
    });

    test('TileMap.collisionGroupAt returns correct group', () {
      final map = TileMap(
        cols: 3,
        rows: 2,
        tileWidth: 10,
        tileHeight: 10,
        tiles: [1, 2, 0, 0, 3, 0],
        solidTileIds: {1, 2, 3},
        collisionGroups: {1: 1, 2: 2, 3: 4},
      );
      expect(map.collisionGroupAt(0, 0), 1); // tile 1 -> group 1
      expect(map.collisionGroupAt(1, 0), 2); // tile 2 -> group 2
      expect(map.collisionGroupAt(2, 0), 0); // empty tile -> 0
      expect(map.collisionGroupAt(0, 1), 0); // empty -> 0
      expect(map.collisionGroupAt(1, 1), 4); // tile 3 -> group 4
      expect(map.collisionGroupAt(-1, 0), 0); // out of bounds -> 0
    });
  });

  group('CollisionSystem respects collision groups', () {
    test('entities with matching groups collide', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(0, 0));
      world.storeOf<Velocity>().set(a, Velocity(5, 0));
      world.storeOf<Collider>().set(a, Collider(10, collisionGroup: 1, collisionMask: 1));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(5, 0));
      world.storeOf<Velocity>().set(b, Velocity(-3, 2));
      world.storeOf<Collider>().set(b, Collider(10, collisionGroup: 1, collisionMask: 1));

      world.addSystem(CollisionSystem());

      world.step(0);

      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;
      expect(velA.x, -3);
      expect(velA.y, 2);
      expect(velB.x, 5);
      expect(velB.y, 0);
    });

    test('entities with non-matching groups pass through', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(0, 0));
      world.storeOf<Velocity>().set(a, Velocity(5, 0));
      world.storeOf<Collider>().set(a, Collider(10, collisionGroup: 1, collisionMask: 1));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(5, 0));
      world.storeOf<Velocity>().set(b, Velocity(-3, 2));
      world.storeOf<Collider>().set(b, Collider(10, collisionGroup: 2, collisionMask: 2));

      world.addSystem(CollisionSystem());

      world.step(0);

      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;
      expect(velA.x, 5);
      expect(velA.y, 0);
      expect(velB.x, -3);
      expect(velB.y, 2);
    });

    test('entity with mask 0 never collides', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(0, 0));
      world.storeOf<Velocity>().set(a, Velocity(5, 0));
      world.storeOf<Collider>().set(a, Collider(10, collisionGroup: 1, collisionMask: 0));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(5, 0));
      world.storeOf<Velocity>().set(b, Velocity(-3, 2));
      world.storeOf<Collider>().set(b, Collider(10, collisionGroup: 1, collisionMask: 1));

      world.addSystem(CollisionSystem());

      world.step(0);

      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;
      expect(velA.x, 5);
      expect(velA.y, 0);
      expect(velB.x, -3);
      expect(velB.y, 2);
    });
  });
}