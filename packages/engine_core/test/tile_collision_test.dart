import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(GravitySystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(TileCollisionSystem());
  world.addSystem(JumpSystem());
  return world;
}

/// A 4x2 grid of 16x16 tiles: an all-solid floor as row 1, empty row 0,
/// except column 2 of row 0 is a one-way platform (tile id 2).
TileMap _testMap() => TileMap(
      cols: 4,
      rows: 2,
      tileWidth: 16,
      tileHeight: 16,
      tiles: [
        0, 0, 2, 0, //
        1, 1, 1, 1, //
      ],
      solidTileIds: {1},
      oneWayTileIds: {2},
    );

void main() {
  test('TileMap.tileAt is bounds-checked and returns 0 outside the grid', () {
    final map = _testMap();
    expect(map.tileAt(0, 1), 1);
    expect(map.tileAt(2, 0), 2);
    expect(map.tileAt(-1, 0), 0);
    expect(map.tileAt(99, 99), 0);
  });

  test('TileMap constructor rejects a tiles list of the wrong length', () {
    expect(
      () => TileMap(cols: 2, rows: 2, tileWidth: 16, tileHeight: 16, tiles: [1, 2]),
      throwsArgumentError,
    );
  });

  test('TileMap round-trips through toJson/fromJson', () {
    final map = _testMap();
    final restored = TileMap.fromJson(map.toJson());
    expect(restored.cols, map.cols);
    expect(restored.tiles, map.tiles);
    expect(restored.solidTileIds, map.solidTileIds);
    expect(restored.oneWayTileIds, map.oneWayTileIds);
  });

  test('solid tile catches a falling entity from above', () {
    final world = _buildWorld();
    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(mapEntity, _testMap());

    final player = world.spawn();
    // Row 1 (solid floor) top edge is at y=16. Start just above it,
    // falling.
    world.storeOf<Position>().set(player, Position(8, 11));
    world.storeOf<Velocity>().set(player, Velocity(0, 50));
    world.storeOf<Collider>().set(player, Collider(5));
    world.storeOf<PlatformerController>().set(player, PlatformerController());

    world.step(0.1);

    final controller = world.storeOf<PlatformerController>().get(player)!;
    expect(controller.grounded, isTrue);
    expect(world.storeOf<Velocity>().get(player)!.y, 0);
  });

  test('one-way tile does not block movement from below', () {
    final world = _buildWorld();
    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(mapEntity, _testMap());

    final player = world.spawn();
    // One-way tile is column 2, row 0: world rect x[32,48] y[0,16].
    // Start below it moving up fast.
    world.storeOf<Position>().set(player, Position(40, 30));
    world.storeOf<Velocity>().set(player, Velocity(0, -200));
    world.storeOf<Collider>().set(player, Collider(5));
    world.storeOf<PlatformerController>().set(player, PlatformerController());

    world.step(0.05);

    expect(world.storeOf<Velocity>().get(player)!.y, -200);
  });

  test(
      'jump fires off tile-only ground contact within the same tick '
      '(regression: jump used to be checked before tile grounding was resolved)',
      () {
    final world = _buildWorld();
    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(mapEntity, _testMap());

    final player = world.spawn();
    // Resting on the solid floor (top at y=16), overlapping slightly as
    // a real frame of gravity would leave it, with no PlatformBody
    // involved at all -- grounding here can only come from
    // TileCollisionSystem.
    world.storeOf<Position>().set(player, Position(8, 12));
    world.storeOf<Velocity>().set(player, Velocity(0, 0));
    world.storeOf<Collider>().set(player, Collider(5));
    world.storeOf<PlatformerController>().set(
          player,
          PlatformerController(jumpSpeed: 250, jumpRequested: true),
        );

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(player)!.y, -250);
  });
}
