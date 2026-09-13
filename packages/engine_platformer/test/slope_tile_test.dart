import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSlopeCircleAabb', () {
    test('ascendingRight: floor is low on the left edge, high on the right', () {
      // floor at x=0 (t=0) == bottom == 40 -- start with the foot
      // (y+radius) already at/past that height, or resolveSlopeCircleAabb
      // (which only checks the current position, no integration of its
      // own) has nothing to catch.
      final leftPos = Position(0, 36);
      final leftVel = Velocity(0, 1);
      final caughtLeft = resolveSlopeCircleAabb(
        pos: leftPos,
        vel: leftVel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: true,
      );
      expect(caughtLeft, isTrue);
      expect(leftPos.y, 35);

      final rightPos = Position(40, 5);
      final rightVel = Velocity(0, 1);
      final caughtRight = resolveSlopeCircleAabb(
        pos: rightPos,
        vel: rightVel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: true,
      );
      expect(caughtRight, isTrue);
      // floor at x=40 (t=1) == top == 0; resting circle center = 0-5=-5.
      expect(rightPos.y, -5);
    });

    test('ascendingLeft is the mirror: high on the left, low on the right', () {
      final leftPos = Position(0, -5);
      final leftVel = Velocity(0, 1);
      resolveSlopeCircleAabb(
        pos: leftPos,
        vel: leftVel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: false,
      );
      // floor at x=0 (t=0) == top == 0; resting circle center = 0-5=-5.
      expect(leftPos.y, -5);

      final rightPos = Position(40, 35);
      final rightVel = Velocity(0, 1);
      resolveSlopeCircleAabb(
        pos: rightPos,
        vel: rightVel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: false,
      );
      // floor at x=40 (t=1) == bottom == 40; resting circle center = 40-5=35.
      expect(rightPos.y, 35);
    });

    test('does not catch while jumping upward through the slope', () {
      final pos = Position(20, 5);
      final vel = Velocity(0, -50);
      final caught = resolveSlopeCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: true,
      );
      expect(caught, isFalse);
    });

    test('does not catch when the foot has not reached the ramp surface yet', () {
      final pos = Position(0, -100); // way above the ramp
      final vel = Velocity(0, 1);
      final caught = resolveSlopeCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: true,
      );
      expect(caught, isFalse);
    });

    test('does not catch outside the tile\'s horizontal span', () {
      final pos = Position(100, 5);
      final vel = Velocity(0, 1);
      final caught = resolveSlopeCircleAabb(
        pos: pos,
        vel: vel,
        radius: 5,
        left: 0,
        right: 40,
        top: 0,
        bottom: 40,
        ascendingRight: true,
      );
      expect(caught, isFalse);
    });
  });

  group('TileCollisionSystem with a slope tile', () {
    World buildWorld() {
      final world = World(width: 1000, height: 1000);
      registerCoreComponents(world);
      registerPlatformerComponents(world);
      world.addSystem(MovementSystem());
      world.addSystem(TileCollisionSystem());
      return world;
    }

    test('walking across an ascendingRight tile raises the entity smoothly', () {
      final world = buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 1,
              rows: 1,
              tileWidth: 40,
              tileHeight: 40,
              tiles: [1],
              slopeUpRightTileIds: {1},
            ),
          );

      final id = world.spawn();
      // Resting near the tile's left edge: t=(2-0)/40=0.05, floor =
      // 40+(0-40)*0.05 = 38, so a radius-10 circle rests with its
      // center at y=28.
      world.storeOf<Position>().set(id, Position(2, 28));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Collider>().set(id, Collider(10));
      world.storeOf<PlatformerController>().set(id, PlatformerController());

      world.step(0.016);
      final controller = world.storeOf<PlatformerController>().get(id)!;
      expect(controller.grounded, isTrue);

      // Move to the tile's right edge (higher ground -- smaller y) and
      // resolve again from the old (lower) height; the ramp should pull
      // it up, not block it.
      final pos = world.storeOf<Position>().get(id)!;
      pos.x = 38;
      pos.y = 28; // still at the old, now-too-low height
      world.step(0.016);

      expect(pos.y, lessThan(28), reason: 'floor is higher near the tile\'s right edge');
      expect(controller.grounded, isTrue);
    });
  });
}
