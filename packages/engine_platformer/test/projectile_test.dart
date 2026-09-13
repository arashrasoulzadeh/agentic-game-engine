import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(CollisionSystem());
  world.addSystem(ProjectileSystem());
  return world;
}

void main() {
  test('Projectile round-trips through toJson/fromJson', () {
    final decoded = Projectile.fromJson(
      Projectile(damage: 10, lifetimeSeconds: 2, owner: 5).toJson(),
    );
    expect(decoded.damage, 10);
    expect(decoded.lifetimeSeconds, 2);
    expect(decoded.owner, 5);
  });

  test('spawnProjectile creates a moving entity with Position/Velocity/Collider/Projectile', () {
    final world = _buildWorld();
    final id = spawnProjectile(world, x: 0, y: 0, vx: 100, vy: 0, damage: 10);

    expect(world.storeOf<Position>().get(id), isNotNull);
    expect(world.storeOf<Velocity>().get(id)!.x, 100);
    expect(world.storeOf<Collider>().get(id), isNotNull);
    expect(world.storeOf<Projectile>().get(id)!.damage, 10);

    world.step(0.1);
    expect(world.storeOf<Position>().get(id)!.x, 10); // moved via ordinary MovementSystem
  });

  test('ProjectileSystem destroys a projectile once its lifetime elapses', () {
    final world = _buildWorld();
    final id = spawnProjectile(world, x: 0, y: 0, vx: 0, vy: 0, damage: 10, lifetimeSeconds: 0.05);

    world.step(0.03);
    expect(world.entities.isAlive(id), isTrue);

    world.step(0.03); // elapsed now 0.06 >= 0.05
    expect(world.entities.isAlive(id), isFalse);
  });

  group('installProjectileDamage', () {
    test('a projectile hitting something with Health deals damage and is destroyed', () {
      final world = _buildWorld();
      installProjectileDamage(world);

      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 0));
      world.storeOf<Velocity>().set(target, Velocity(0, 0));
      world.storeOf<Collider>().set(target, Collider(10));
      world.storeOf<Health>().set(target, Health(current: 50, max: 50));

      final projectile = spawnProjectile(world, x: 95, y: 0, vx: 0, vy: 0, damage: 15);

      world.step(0.016);

      expect(world.storeOf<Health>().get(target)!.current, 35);
      expect(world.entities.isAlive(projectile), isFalse);
    });

    test('a projectile never damages its own owner', () {
      final world = _buildWorld();
      installProjectileDamage(world);

      final owner = world.spawn();
      world.storeOf<Position>().set(owner, Position(100, 0));
      world.storeOf<Velocity>().set(owner, Velocity(0, 0));
      world.storeOf<Collider>().set(owner, Collider(10));
      world.storeOf<Health>().set(owner, Health(current: 50, max: 50));

      final projectile = spawnProjectile(
        world,
        x: 95,
        y: 0,
        vx: 0,
        vy: 0,
        damage: 15,
        owner: owner,
      );

      world.step(0.016);

      expect(world.storeOf<Health>().get(owner)!.current, 50, reason: 'unaffected by its own projectile');
      expect(world.entities.isAlive(projectile), isTrue, reason: 'not destroyed -- it never hit a valid target');
    });

    test('a projectile hitting something with no Health passes through harmlessly', () {
      final world = _buildWorld();
      installProjectileDamage(world);

      final prop = world.spawn();
      world.storeOf<Position>().set(prop, Position(100, 0));
      world.storeOf<Velocity>().set(prop, Velocity(0, 0));
      world.storeOf<Collider>().set(prop, Collider(10));
      // No Health on `prop`.

      final projectile = spawnProjectile(world, x: 95, y: 0, vx: 0, vy: 0, damage: 15);

      world.step(0.016);

      expect(world.entities.isAlive(projectile), isTrue);
    });

    test('a second projectile fired after the first still deals damage (one shared subscription)', () {
      final world = _buildWorld();
      installProjectileDamage(world);

      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 0));
      world.storeOf<Velocity>().set(target, Velocity(0, 0));
      world.storeOf<Collider>().set(target, Collider(10));
      world.storeOf<Health>().set(target, Health(current: 100, max: 100));

      spawnProjectile(world, x: -500, y: 0, vx: 0, vy: 0, damage: 1); // fired first, misses
      final second = spawnProjectile(world, x: 95, y: 0, vx: 0, vy: 0, damage: 20);

      world.step(0.016);

      expect(world.storeOf<Health>().get(target)!.current, 80);
      expect(world.entities.isAlive(second), isFalse);
    });
  });
}
