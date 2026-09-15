import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(GravitySystem(gravity: 1000));
  return world;
}

EntityId _spawn(World world, Gravity gravity, {double vy = 0}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(0, 0));
  world.storeOf<Velocity>().set(id, Velocity(0, vy));
  world.storeOf<Gravity>().set(id, gravity);
  return id;
}

void main() {
  test('Gravity defaults fallMultiplier to 1 -- no asymmetry, unchanged prior behavior', () {
    expect(Gravity().fallMultiplier, 1);
  });

  test('fallMultiplier round-trips through toJson/fromJson', () {
    final gravity = Gravity(scale: 0.8, fallMultiplier: 1.6);
    final restored = Gravity.fromJson(gravity.toJson());
    expect(restored.scale, 0.8);
    expect(restored.fallMultiplier, 1.6);
  });

  test('fallMultiplier 1 (default) accelerates identically whether rising or falling', () {
    final world = _buildWorld();
    final rising = _spawn(world, Gravity(), vy: -100);
    final falling = _spawn(world, Gravity(), vy: 100);

    world.step(0.1);

    final risingDelta = world.storeOf<Velocity>().get(rising)!.y - (-100);
    final fallingDelta = world.storeOf<Velocity>().get(falling)!.y - 100;
    expect(risingDelta, fallingDelta);
  });

  test('fallMultiplier > 1 only speeds up acceleration while already falling (vel.y > 0)', () {
    final world = _buildWorld();
    final rising = _spawn(world, Gravity(fallMultiplier: 2), vy: -100);
    final falling = _spawn(world, Gravity(fallMultiplier: 2), vy: 100);

    world.step(0.1);

    // Rising: plain gravity (1000 * 0.1 = 100) applied on top of -100.
    expect(world.storeOf<Velocity>().get(rising)!.y, -100 + 100);
    // Falling: fallMultiplier doubles it (1000 * 2 * 0.1 = 200) on top of 100.
    expect(world.storeOf<Velocity>().get(falling)!.y, 100 + 200);
  });

  test('fallMultiplier combines multiplicatively with scale', () {
    final world = _buildWorld();
    final id = _spawn(world, Gravity(scale: 0.5, fallMultiplier: 2), vy: 50);

    world.step(0.1);

    // 1000 * 0.5 * 2 * 0.1 = 100, on top of the initial 50.
    expect(world.storeOf<Velocity>().get(id)!.y, 50 + 100);
  });

  test('a grounded entity is skipped regardless of fallMultiplier', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(0, 0));
    world.storeOf<Velocity>().set(id, Velocity(0, 100));
    world.storeOf<Gravity>().set(id, Gravity(fallMultiplier: 3));
    world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: true));

    world.step(0.1);

    expect(world.storeOf<Velocity>().get(id)!.y, 100);
  });
}
