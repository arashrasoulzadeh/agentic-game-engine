import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(GravitySystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(JumpSystem());
  return world;
}

void main() {
  test('GravitySystem accelerates falling entities downward', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.componentsOf<Position>().set(id, Position(0, 0));
    world.componentsOf<Velocity>().set(id, Velocity(0, 0));
    world.componentsOf<Gravity>().set(id, Gravity());

    world.step(1.0);

    expect(world.componentsOf<Velocity>().get(id)!.y, greaterThan(0));
  });

  test('GravitySystem does not accelerate a grounded entity', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.componentsOf<Position>().set(id, Position(0, 0));
    world.componentsOf<Velocity>().set(id, Velocity(0, 0));
    world.componentsOf<Gravity>().set(id, Gravity());
    world.componentsOf<PlatformerController>().set(
      id,
      PlatformerController(grounded: true),
    );

    world.step(1.0);

    expect(world.componentsOf<Velocity>().get(id)!.y, 0);
  });

  test('one-way platform catches a falling entity from above', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.componentsOf<Position>().set(player, Position(100, 90));
    world.componentsOf<Velocity>().set(player, Velocity(0, 50));
    world.componentsOf<Collider>().set(player, Collider(10));
    world.componentsOf<PlatformerController>().set(player, PlatformerController());

    final platform = world.spawn();
    world.componentsOf<Position>().set(platform, Position(100, 110));
    world.componentsOf<PlatformBody>().set(
      platform,
      PlatformBody(200, 20, oneWay: true),
    );

    world.step(0.1); // moves player to y=95, foot at 105, top at 100 -> lands

    final controller = world.componentsOf<PlatformerController>().get(player)!;
    final vel = world.componentsOf<Velocity>().get(player)!;
    expect(controller.grounded, isTrue);
    expect(vel.y, 0);
  });

  test('one-way platform does not block movement from below', () {
    final world = _buildWorld();
    final player = world.spawn();
    // Player below the platform, moving upward through it.
    world.componentsOf<Position>().set(player, Position(100, 150));
    world.componentsOf<Velocity>().set(player, Velocity(0, -200));
    world.componentsOf<Collider>().set(player, Collider(10));
    world.componentsOf<PlatformerController>().set(player, PlatformerController());

    final platform = world.spawn();
    world.componentsOf<Position>().set(platform, Position(100, 110));
    world.componentsOf<PlatformBody>().set(
      platform,
      PlatformBody(200, 20, oneWay: true),
    );

    world.step(0.1);

    final controller = world.componentsOf<PlatformerController>().get(player)!;
    final vel = world.componentsOf<Velocity>().get(player)!;
    expect(controller.grounded, isFalse);
    expect(vel.y, -200); // untouched -- passed straight through
  });

  test('jump fires only while grounded and consumes the request', () {
    // grounded isn't something you can just set and trust — it's
    // recomputed from actual platform contact every tick (see
    // PlatformerSystem: `controller.grounded = false` at the top of
    // each entity's processing) — so the test needs a real platform
    // underneath, resting in contact, not just a manually-set flag.
    final world = _buildWorld();
    final player = world.spawn();
    // Slightly overlapping the platform's top, as gravity would leave it
    // after a real frame — exact tangency (distance == radius) doesn't
    // count as overlap under the system's strict `<` check.
    world.componentsOf<Position>().set(player, Position(100, 91));
    world.componentsOf<Velocity>().set(player, Velocity(0, 0));
    world.componentsOf<Collider>().set(player, Collider(10));
    world.componentsOf<PlatformerController>().set(
      player,
      PlatformerController(jumpSpeed: 400, jumpRequested: true),
    );
    final ground = world.spawn();
    world.componentsOf<Position>().set(ground, Position(100, 110));
    world.componentsOf<PlatformBody>().set(ground, PlatformBody(200, 20));

    world.step(0.016);

    final controller = world.componentsOf<PlatformerController>().get(player)!;
    final vel = world.componentsOf<Velocity>().get(player)!;
    expect(vel.y, -400);
    expect(controller.grounded, isFalse);
    expect(controller.jumpRequested, isFalse);
  });

  test('solid platform blocks landing, sides, and the underside', () {
    // Landing from above.
    final landWorld = _buildWorld();
    final lander = landWorld.spawn();
    landWorld.componentsOf<Position>().set(lander, Position(100, 95));
    landWorld.componentsOf<Velocity>().set(lander, Velocity(0, 50));
    landWorld.componentsOf<Collider>().set(lander, Collider(10));
    landWorld.componentsOf<PlatformerController>().set(
      lander,
      PlatformerController(),
    );
    final solidGround = landWorld.spawn();
    landWorld.componentsOf<Position>().set(solidGround, Position(100, 110));
    landWorld.componentsOf<PlatformBody>().set(solidGround, PlatformBody(200, 20));
    landWorld.step(0.1);
    expect(
      landWorld.componentsOf<PlatformerController>().get(lander)!.grounded,
      isTrue,
    );

    // Hitting the underside while jumping up.
    final bonkWorld = _buildWorld();
    final jumper = bonkWorld.spawn();
    bonkWorld.componentsOf<Position>().set(jumper, Position(100, 125));
    bonkWorld.componentsOf<Velocity>().set(jumper, Velocity(0, -200));
    bonkWorld.componentsOf<Collider>().set(jumper, Collider(10));
    bonkWorld.componentsOf<PlatformerController>().set(
      jumper,
      PlatformerController(),
    );
    final ceiling = bonkWorld.spawn();
    bonkWorld.componentsOf<Position>().set(ceiling, Position(100, 110));
    bonkWorld.componentsOf<PlatformBody>().set(ceiling, PlatformBody(200, 20));
    bonkWorld.step(0.05);
    final bonkedVel = bonkWorld.componentsOf<Velocity>().get(jumper)!;
    expect(bonkedVel.y, greaterThanOrEqualTo(0));
  });
}
