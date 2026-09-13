import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

TileMap _buildMap() {
  // 5x3 grid, tile=40. Row 1 (y=40..80) has a solid wall at col 2
  // (x=80..120) and a one-way tile at col 4 (x=160..200).
  return TileMap(
    cols: 5,
    rows: 3,
    tileWidth: 40,
    tileHeight: 40,
    tiles: [
      0, 0, 0, 0, 0,
      0, 0, 1, 0, 2,
      0, 0, 0, 0, 0,
    ],
    solidTileIds: {1},
    oneWayTileIds: {2},
  );
}

void main() {
  group('raycastTileMap', () {
    test('returns null when the ray never enters a solid tile', () {
      final map = _buildMap();
      final hit = raycastTileMap(map, Position(0, 0), 0, 20, 200, 20); // row 0, above the wall
      expect(hit, isNull);
    });

    test('hits the first solid tile the ray crosses', () {
      final map = _buildMap();
      // Straight horizontal ray through row 1 (y=60), left to right --
      // should stop at the solid tile spanning x=80..120.
      final hit = raycastTileMap(map, Position(0, 0), 0, 60, 200, 60);

      expect(hit, isNotNull);
      expect(hit!.x, closeTo(80, 1e-9));
      expect(hit.y, closeTo(60, 1e-9));
    });

    test('a diagonal ray still finds the solid tile (no tunneling through the grid)', () {
      final map = _buildMap();
      // From top-left corner of the grid to bottom-right -- passes
      // through the solid tile at col 2, row 1 along the way.
      final hit = raycastTileMap(map, Position(0, 0), 0, 0, 200, 120);

      expect(hit, isNotNull);
      // Somewhere within the solid tile's bounds (x in [80,120], y in [40,80]).
      expect(hit!.x, inInclusiveRange(80, 120));
      expect(hit.y, inInclusiveRange(40, 80));
    });

    test('one-way tiles do not block by default', () {
      final map = _buildMap();
      final hit = raycastTileMap(map, Position(0, 0), 140, 60, 220, 60); // through col 4's one-way tile
      expect(hit, isNull);
    });

    test('blockOneWay: true makes a one-way tile stop the ray', () {
      final map = _buildMap();
      final hit = raycastTileMap(map, Position(0, 0), 140, 60, 220, 60, blockOneWay: true);

      expect(hit, isNotNull);
      expect(hit!.x, closeTo(160, 1e-9));
    });

    test('the TileMap entity\'s own Position (origin) offsets the grid', () {
      final map = _buildMap();
      // Grid now starts at world (1000, 1000) instead of (0, 0) -- the
      // same relative ray (through what would be the solid tile) should
      // still hit it, offset accordingly.
      final origin = Position(1000, 1000);
      final hit = raycastTileMap(map, origin, 1000, 1060, 1200, 1060);

      expect(hit, isNotNull);
      expect(hit!.x, closeTo(1080, 1e-9));
    });

    test('a purely vertical ray is handled (dx == 0)', () {
      final map = TileMap(
        cols: 1,
        rows: 3,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [0, 1, 0],
        solidTileIds: {1},
      );
      final hit = raycastTileMap(map, Position(0, 0), 20, 0, 20, 120);

      expect(hit, isNotNull);
      expect(hit!.y, closeTo(40, 1e-9));
    });
  });

  group('raycastEntities', () {
    World buildWorld() {
      final world = World(width: 1000, height: 1000);
      registerCoreComponents(world);
      return world;
    }

    test('returns null when the ray misses every entity', () {
      final world = buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(500, 500));
      world.storeOf<Collider>().set(id, Collider(10));

      final hit = raycastEntities(world, fromX: 0, fromY: 0, toX: 100, toY: 0);
      expect(hit, isNull);
    });

    test('hits an entity the ray passes through', () {
      final world = buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 0));
      world.storeOf<Collider>().set(id, Collider(10));

      final hit = raycastEntities(world, fromX: 0, fromY: 0, toX: 200, toY: 0);

      expect(hit, isNotNull);
      expect(hit!.entity, id);
      expect(hit.x, closeTo(90, 1e-6)); // enters the circle's near edge
    });

    test('returns the nearest of several entities along the ray', () {
      final world = buildWorld();
      final near = world.spawn();
      world.storeOf<Position>().set(near, Position(100, 0));
      world.storeOf<Collider>().set(near, Collider(10));
      final far = world.spawn();
      world.storeOf<Position>().set(far, Position(300, 0));
      world.storeOf<Collider>().set(far, Collider(10));

      final hit = raycastEntities(world, fromX: 0, fromY: 0, toX: 400, toY: 0);

      expect(hit!.entity, near);
    });

    test('excludes the given entity even if the ray passes through it', () {
      final world = buildWorld();
      final caster = world.spawn();
      world.storeOf<Position>().set(caster, Position(0, 0));
      world.storeOf<Collider>().set(caster, Collider(5));
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 0));
      world.storeOf<Collider>().set(target, Collider(10));

      final hit = raycastEntities(world, fromX: 0, fromY: 0, toX: 200, toY: 0, exclude: caster);

      expect(hit!.entity, target);
    });

    test('a ray that ends before reaching an entity misses it', () {
      final world = buildWorld();
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(300, 0));
      world.storeOf<Collider>().set(id, Collider(10));

      final hit = raycastEntities(world, fromX: 0, fromY: 0, toX: 100, toY: 0);
      expect(hit, isNull);
    });
  });
}
