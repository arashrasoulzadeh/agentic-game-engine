import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  // Large enough that even the double-jump group's big dt=1.0 steps
  // (needed to clear the floor's collider radius between jumps) never
  // reach MovementSystem's world-bounds bounce, which would otherwise
  // flip velocity sign and masquerade as a JumpSystem bug.
  final world = World(width: 100000, height: 100000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(JumpSystem());
  return world;
}

EntityId _spawnController(World world, PlatformerController controller,
    {required double x, required double y}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(10));
  world.storeOf<PlatformerController>().set(id, controller);
  return id;
}

/// A flat floor at world y=510 (top edge at y=500) plus an entity
/// resting on it. `PlatformerSystem` resets `grounded`/wall-touch flags
/// every tick and only sets them from an actually-resolved collision —
/// hand-setting `controller.grounded = true` gets silently wiped before
/// `JumpSystem` ever sees it, so every "grounded" scenario below uses a
/// real floor instead.
EntityId _spawnOnFloor(World world, PlatformerController controller) {
  // Floor sits far from y=0 -- MovementSystem bounces off the world's
  // lower bound, which the double-jump group's large dt=1.0 steps
  // (needed to clear the floor's collider radius between jumps) would
  // otherwise reach and flip velocity sign, masquerading as a
  // JumpSystem bug.
  final floor = world.spawn();
  world.storeOf<Position>().set(floor, Position(500, 5110));
  world.storeOf<PlatformBody>().set(floor, PlatformBody(200, 20));
  return _spawnController(world, controller, x: 500, y: 5099); // top(5100) - 1
}

/// Moves [id] far from the floor so it's no longer overlapping (and
/// thus no longer grounded) on the next tick — the test's way of
/// simulating "just left the ground" without touching the controller's
/// state directly.
void _liftOffFloor(World world, EntityId id) {
  world.storeOf<Position>().get(id)!.y -= 500;
}

void main() {
  group('backward compatibility (all feel-mechanics off by default)', () {
    test('a jump fires while grounded and requested the same tick', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300);
      final id = _spawnOnFloor(world, controller);

      controller.jumpRequested = true;
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, -300);
    });

    test('a jump does not fire the tick after leaving the ground (no coyote time)', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300);
      final id = _spawnOnFloor(world, controller);
      world.step(0.016); // settles, grounded
      _liftOffFloor(world, id);

      controller.jumpRequested = true;
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 0);
    });
  });

  group('coyote time', () {
    test('a jump still fires shortly after leaving the ground', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, coyoteTimeSeconds: 0.1);
      final id = _spawnOnFloor(world, controller);
      world.step(0.016); // grounded, timeSinceGrounded resets to 0
      _liftOffFloor(world, id);
      world.step(0.05); // airborne; timeSinceGrounded == 0.05, still <= 0.1

      controller.jumpRequested = true;
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, -300);
    });

    test('a jump does not fire once the coyote window has passed', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, coyoteTimeSeconds: 0.1);
      final id = _spawnOnFloor(world, controller);
      world.step(0.016);
      _liftOffFloor(world, id);
      world.step(0.2); // airborne past the 0.1s coyote window

      controller.jumpRequested = true;
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 0);
    });
  });

  group('jump buffering', () {
    test('a jump pressed slightly before landing fires on landing', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, jumpBufferSeconds: 0.1);
      // Starts well above the floor -- not grounded.
      final id = _spawnController(world, controller, x: 500, y: 100);
      final floor = world.spawn();
      world.storeOf<Position>().set(floor, Position(500, 510));
      world.storeOf<PlatformBody>().set(floor, PlatformBody(200, 20));

      controller.jumpRequested = true;
      world.step(0.016); // still airborne; buffered, no jump yet
      expect(world.storeOf<Velocity>().get(id)!.y, 0);

      controller.jumpRequested = false;
      world.storeOf<Position>().get(id)!.y = 499; // "lands" on the floor this tick
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, -300);
    });
  });

  group('double jump', () {
    // A large dt (as in moving_platform_test.dart) so each jump's
    // velocity actually carries the entity clear of the floor's
    // collider radius before the next tick's resolution runs --
    // otherwise a small dt leaves it still just barely overlapping,
    // and PlatformerSystem re-resolves it as grounded again instantly.
    const dt = 1.0;

    test('an extra air jump fires while airborne, up to maxAirJumps', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, maxAirJumps: 1);
      final id = _spawnOnFloor(world, controller);
      final vel = world.storeOf<Velocity>().get(id)!;

      controller.jumpRequested = true;
      world.step(dt); // ground jump
      expect(vel.y, -300);

      controller.jumpRequested = true;
      world.step(dt); // air jump #1 (allowed)
      expect(vel.y, -300);

      controller.jumpRequested = true;
      world.step(dt); // air jump #2 (not allowed -- maxAirJumps: 1)
      expect(vel.y, -300, reason: 'no second air jump; velocity unchanged (no gravity in this test world)');
    });

    test('air jumps reset once grounded again', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, maxAirJumps: 1);
      final id = _spawnOnFloor(world, controller);
      final vel = world.storeOf<Velocity>().get(id)!;

      controller.jumpRequested = true;
      world.step(dt); // ground jump
      controller.jumpRequested = true;
      world.step(dt); // air jump #1 -- airJumpsUsed now 1
      controller.jumpRequested = true;
      world.step(dt); // no air jump left -- velocity unaffected
      expect(vel.y, -300);

      // Land again: reset position/velocity directly onto the floor.
      final pos = world.storeOf<Position>().get(id)!;
      pos.y = 5099; // top(5100) - 1, matching _spawnOnFloor's floor
      vel.y = 0;
      world.step(dt); // grounded -- resets airJumpsUsed

      controller.jumpRequested = true;
      world.step(dt); // ground jump again (fresh contact)
      controller.jumpRequested = true;
      world.step(dt); // air jump available again
      expect(vel.y, -300, reason: 'air jump available again after a fresh ground contact');
    });
  });

  group('wall jump', () {
    // A narrow, tall wall to the entity's left -- same reasoning as
    // _spawnOnFloor: the wall-touch flag has to come from an actual
    // resolved side-collision, not be hand-set.
    EntityId spawnWallTouching(World world, PlatformerController controller) {
      final wall = world.spawn();
      world.storeOf<Position>().set(wall, Position(480, 500));
      world.storeOf<PlatformBody>().set(wall, PlatformBody(40, 200));
      return _spawnController(world, controller, x: 505, y: 500);
    }

    test('a jump while touching a wall and airborne pushes away from it', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300, wallJumpPushSpeed: 200);
      final id = spawnWallTouching(world, controller);

      controller.jumpRequested = true;
      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.y, -300);
      expect(vel.x, 200, reason: 'pushed right, away from the wall on the left');
      expect(controller.touchingWallLeft, isTrue);
    });

    test('wall jump does not fire when wallJumpPushSpeed is 0 (default)', () {
      final world = _buildWorld();
      final controller = PlatformerController(jumpSpeed: 300);
      final id = spawnWallTouching(world, controller);

      controller.jumpRequested = true;
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 0);
    });
  });

  group('wall slide', () {
    test('falling speed is clamped while touching a wall', () {
      final world = _buildWorld();
      final controller = PlatformerController(wallSlideMaxFallSpeed: 50);
      final wall = world.spawn();
      world.storeOf<Position>().set(wall, Position(480, 500));
      world.storeOf<PlatformBody>().set(wall, PlatformBody(40, 200));
      final id = _spawnController(world, controller, x: 505, y: 500);
      world.storeOf<Velocity>().get(id)!.y = 400; // falling fast

      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 50);
    });

    test('falling speed is unaffected when wallSlideMaxFallSpeed is unset (default)', () {
      final world = _buildWorld();
      final controller = PlatformerController();
      final wall = world.spawn();
      world.storeOf<Position>().set(wall, Position(480, 500));
      world.storeOf<PlatformBody>().set(wall, PlatformBody(40, 200));
      final id = _spawnController(world, controller, x: 505, y: 500);
      world.storeOf<Velocity>().get(id)!.y = 400;

      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 400);
    });
  });
}
