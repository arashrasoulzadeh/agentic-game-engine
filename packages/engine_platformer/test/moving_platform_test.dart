import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  return world;
}

void main() {
  test('a resting entity is carried along by a horizontally-moving platform', () {
    final world = _buildWorld();
    final platform = world.spawn();
    world.storeOf<Position>().set(platform, Position(500, 100));
    world.storeOf<Velocity>().set(platform, Velocity(50, 0));
    world.storeOf<PlatformBody>().set(platform, PlatformBody(200, 20));

    final rider = world.spawn();
    world.storeOf<Position>().set(rider, Position(500, 89)); // resting just above the platform
    world.storeOf<Velocity>().set(rider, Velocity(0, 0));
    world.storeOf<Collider>().set(rider, Collider(10));
    world.storeOf<PlatformerController>().set(rider, PlatformerController());

    world.step(1.0);

    // Platform moved 50 units right (MovementSystem); the rider, still
    // resting on top, should have moved the same amount horizontally --
    // not been left behind.
    final platformPos = world.storeOf<Position>().get(platform)!;
    final riderPos = world.storeOf<Position>().get(rider)!;
    expect(platformPos.x, 550);
    expect(riderPos.x, 550);
    expect(world.storeOf<PlatformerController>().get(rider)!.grounded, isTrue);
  });

  test('a static platform (no Velocity) never nudges a rider horizontally', () {
    final world = _buildWorld();
    final platform = world.spawn();
    world.storeOf<Position>().set(platform, Position(500, 100));
    world.storeOf<PlatformBody>().set(platform, PlatformBody(200, 20));

    final rider = world.spawn();
    world.storeOf<Position>().set(rider, Position(500, 89));
    world.storeOf<Velocity>().set(rider, Velocity(0, 0));
    world.storeOf<Collider>().set(rider, Collider(10));
    world.storeOf<PlatformerController>().set(rider, PlatformerController());

    world.step(1.0);

    expect(world.storeOf<Position>().get(rider)!.x, 500);
  });

  test('an entity not actually resting on the platform is not carried', () {
    final world = _buildWorld();
    final platform = world.spawn();
    world.storeOf<Position>().set(platform, Position(500, 100));
    world.storeOf<Velocity>().set(platform, Velocity(50, 0));
    world.storeOf<PlatformBody>().set(platform, PlatformBody(200, 20));

    final flying = world.spawn();
    world.storeOf<Position>().set(flying, Position(500, 0)); // far above, not touching
    world.storeOf<Velocity>().set(flying, Velocity(0, 0));
    world.storeOf<Collider>().set(flying, Collider(10));
    world.storeOf<PlatformerController>().set(flying, PlatformerController());

    world.step(1.0);

    expect(world.storeOf<Position>().get(flying)!.x, 500);
    expect(world.storeOf<PlatformerController>().get(flying)!.grounded, isFalse);
  });

  test('a moving one-way platform also carries a rider landing on top of it', () {
    final world = _buildWorld();
    final platform = world.spawn();
    world.storeOf<Position>().set(platform, Position(500, 100));
    world.storeOf<Velocity>().set(platform, Velocity(30, 0));
    world.storeOf<PlatformBody>().set(platform, PlatformBody(200, 20, oneWay: true));

    final rider = world.spawn();
    // Falling onto the platform's top this tick. MovementSystem
    // integrates Position by Velocity*dt before PlatformerSystem runs,
    // so this tick's foot position goes from 78+10=88 (at/above the
    // platform's top, y=90) to (84)+10=94 (past it) -- exactly the
    // "crossed the top this tick" case resolveOneWayCircleAabb catches.
    world.storeOf<Position>().set(rider, Position(500, 78));
    world.storeOf<Velocity>().set(rider, Velocity(0, 6));
    world.storeOf<Collider>().set(rider, Collider(10));
    world.storeOf<PlatformerController>().set(rider, PlatformerController());

    world.step(1.0);

    expect(world.storeOf<Position>().get(rider)!.x, 530);
    expect(world.storeOf<PlatformerController>().get(rider)!.grounded, isTrue);
  });
}
