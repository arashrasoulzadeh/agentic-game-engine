import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

/// A 10x10, 20px-tile grid: a solid wall filling column 5, rows 5-9,
/// with open space everywhere else -- the wall's top edge sits at the
/// row 4/5 boundary (world y = 100).
TileMap _wallMap() => TileMap(
      cols: 10,
      rows: 10,
      tileWidth: 20,
      tileHeight: 20,
      tiles: [
        for (var row = 0; row < 10; row++)
          for (var col = 0; col < 10; col++) (col == 5 && row >= 5) ? 1 : 0,
      ],
      solidTileIds: {1},
    );

EntityId _spawnMap(World world) {
  final mapEntity = world.spawn();
  world.storeOf<Position>().set(mapEntity, Position(0, 0));
  world.storeOf<TileMap>().set(mapEntity, _wallMap());
  return mapEntity;
}

/// Places an entity right at the wall's top-right corner: touching the
/// wall on its right (`touchingWallRight`), airborne, aligned with the
/// row containing the wall's top edge (row 5) -- exactly the position
/// `LedgeGrabSystem` should recognize as grabbable.
EntityId _spawnAtLedge(World world, {bool ledgeGrabEnabled = true}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(94, 105));
  world.storeOf<Velocity>().set(id, Velocity(0, 40));
  world.storeOf<Collider>().set(id, Collider(5));
  world.storeOf<InputState>().set(id, InputState());
  world.storeOf<PlatformerController>().set(
        id,
        PlatformerController(
          ledgeGrabEnabled: ledgeGrabEnabled,
          grounded: false,
          touchingWallRight: true,
        ),
      );
  return id;
}

void main() {
  group('LedgeGrabSystem', () {
    test('ledgeGrabEnabled false (default) is a no-op even at a grabbable ledge', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world, ledgeGrabEnabled: false);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isFalse);
      expect(world.storeOf<Velocity>().get(id)!.y, 40, reason: 'vel left untouched');
    });

    test('grabs the ledge: freezes velocity and snaps to the wall-top row', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);

      final controller = world.storeOf<PlatformerController>().get(id)!;
      expect(controller.ledgeGrabbing, isTrue);
      expect(controller.grounded, isFalse);
      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 0);
      expect(vel.y, 0);
      // ledgeTopY (100) + radius (5).
      expect(world.storeOf<Position>().get(id)!.y, 105);
      // Mantle target precomputed at grab time.
      expect(controller.ledgeMantleTargetX, 94 + 1 * (20 * 0.6));
      expect(controller.ledgeMantleTargetY, 100 - 5);
    });

    test('does not grab while grounded', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      world.storeOf<PlatformerController>().get(id)!.grounded = true;
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isFalse);
    });

    test('does not grab without headroom above the wall (a tall solid face, not an edge)',
        () {
      final world = _buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 10,
              rows: 10,
              tileWidth: 20,
              tileHeight: 20,
              // Column 5 solid for every row -- no open edge anywhere.
              tiles: [for (var i = 0; i < 100; i++) (i % 10 == 5) ? 1 : 0],
              solidTileIds: {1},
            ),
          );
      final id = _spawnAtLedge(world);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isFalse);
    });

    test('does not grab without headroom above the entity itself', () {
      final world = _buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      final tiles = [
        for (var row = 0; row < 10; row++)
          for (var col = 0; col < 10; col++)
            (col == 5 && row >= 5) || (col == 4 && row == 4) ? 1 : 0,
      ];
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(cols: 10, rows: 10, tileWidth: 20, tileHeight: 20, tiles: tiles,
                solidTileIds: {1}),
          );
      final id = _spawnAtLedge(world);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isFalse);
    });

    test('mantling on up input teleports to the precomputed target and stands grounded',
        () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      final input = world.storeOf<InputState>().get(id)!;
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016); // grab
      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isTrue);

      input.pressedActions.add('up');
      world.step(0.016); // mantle

      final controller = world.storeOf<PlatformerController>().get(id)!;
      expect(controller.ledgeGrabbing, isFalse);
      expect(controller.grounded, isTrue);
      final pos = world.storeOf<Position>().get(id)!;
      expect(pos.x, 94 + 1 * (20 * 0.6));
      expect(pos.y, 100 - 5);
      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 0);
      expect(vel.y, 0);
    });

    test('mantling on jump input works the same as up', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      final input = world.storeOf<InputState>().get(id)!;
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016);
      input.pressedActions.add('jump');
      world.step(0.016);

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isFalse);
      expect(world.storeOf<PlatformerController>().get(id)!.grounded, isTrue);
    });

    test('dropping on down input releases the grab without repositioning', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      final input = world.storeOf<InputState>().get(id)!;
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016); // grab
      final grabbedPos = world.storeOf<Position>().get(id)!;
      expect(grabbedPos.y, 105);

      input.pressedActions.add('down');
      world.storeOf<Velocity>().get(id)!.y = 77; // simulate gravity resuming next tick
      world.step(0.016); // drop

      final controller = world.storeOf<PlatformerController>().get(id)!;
      expect(controller.ledgeGrabbing, isFalse);
      expect(world.storeOf<Position>().get(id)!.y, 105, reason: 'no teleport on drop');
      expect(world.storeOf<Velocity>().get(id)!.y, 77,
          reason: 'drop leaves velocity alone -- LedgeGrabSystem does not re-freeze it');
    });

    test('while hanging, holding neither mantle nor drop input freezes velocity every tick',
        () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016); // grab
      world.storeOf<Velocity>().get(id)!.y = 999; // something else tried to move it
      world.step(0.016); // still hanging

      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isTrue);
      expect(world.storeOf<Velocity>().get(id)!.y, 0);
    });

    test('hitstun releases an active grab instead of leaving it frozen', () {
      final world = _buildWorld();
      _spawnMap(world);
      final id = _spawnAtLedge(world);
      world.addSystem(LedgeGrabSystem(id));

      world.step(0.016); // grab
      expect(world.storeOf<PlatformerController>().get(id)!.ledgeGrabbing, isTrue);

      world.storeOf<PlatformerController>().get(id)!.hitstunSeconds = 0.5;
      world.storeOf<Velocity>().get(id)!.y = 250; // a knockback impulse
      world.step(0.016);

      final controller = world.storeOf<PlatformerController>().get(id)!;
      expect(controller.ledgeGrabbing, isFalse);
      expect(world.storeOf<Velocity>().get(id)!.y, 250,
          reason: 'not overridden back to 0 once the grab is released');
    });
  });
}
