import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  // AttackSystem reads InputState unconditionally (same as
  // PlatformerInputSystem), so any world using it needs Flutter
  // components registered even for tests that never attach an
  // InputState themselves.
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(ProjectileSystem());
  world.addSystem(AttackSystem());
  return world;
}

EntityId _spawnAttacker(World world, Weapon weapon, {double facingSign = 1}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(100, 100));
  world.storeOf<PlatformerController>().set(id, PlatformerController(facingSign: facingSign));
  world.storeOf<Weapon>().set(id, weapon);
  return id;
}

void main() {
  group('melee', () {
    test('attackRequested spawns a stationary hitbox meleeRange ahead in the facing direction',
        () {
      final world = _buildWorld();
      final weapon = Weapon(kind: WeaponKind.melee, damage: 15, meleeRange: 30, meleeRadius: 10);
      final attacker = _spawnAttacker(world, weapon, facingSign: 1);

      world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
      world.step(0.016);

      final projectiles = world.storeOf<Projectile>();
      expect(projectiles.length, 1);
      final hitboxId = projectiles.entityAt(0);
      expect(projectiles.get(hitboxId)!.damage, 15);
      expect(projectiles.get(hitboxId)!.owner, attacker);

      final pos = world.storeOf<Position>().get(hitboxId)!;
      expect(pos.x, 130); // 100 + meleeRange(30) * facingSign(1)
      expect(pos.y, 100);

      final vel = world.storeOf<Velocity>().get(hitboxId)!;
      expect(vel.x, 0);
      expect(vel.y, 0);
    });

    test('a facingSign of -1 positions the hitbox behind (to the left)', () {
      final world = _buildWorld();
      final weapon = Weapon(kind: WeaponKind.melee, meleeRange: 30);
      final attacker = _spawnAttacker(world, weapon, facingSign: -1);

      world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
      world.step(0.016);

      final projectiles = world.storeOf<Projectile>();
      final pos = world.storeOf<Position>().get(projectiles.entityAt(0))!;
      expect(pos.x, 70); // 100 + 30 * -1
    });

    test('the hitbox disappears after meleeDurationSeconds, not lingering', () {
      final world = _buildWorld();
      final weapon = Weapon(kind: WeaponKind.melee, meleeDurationSeconds: 0.1);
      final attacker = _spawnAttacker(world, weapon);

      world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
      world.step(0.05);
      expect(world.storeOf<Projectile>().length, 1);

      world.step(0.1); // total elapsed 0.15s > 0.1s lifetime
      expect(world.storeOf<Projectile>().length, 0);
    });
  });

  group('ranged', () {
    test('attackRequested spawns a projectile moving at projectileSpeed in the facing direction',
        () {
      final world = _buildWorld();
      final weapon = Weapon(kind: WeaponKind.ranged, damage: 8, projectileSpeed: 500);
      final attacker = _spawnAttacker(world, weapon, facingSign: 1);

      world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
      world.step(0.016);

      final projectiles = world.storeOf<Projectile>();
      expect(projectiles.length, 1);
      final id = projectiles.entityAt(0);
      expect(projectiles.get(id)!.damage, 8);
      expect(world.storeOf<Velocity>().get(id)!.x, 500);
    });

    test('a facingSign of -1 fires the projectile leftward', () {
      final world = _buildWorld();
      final weapon = Weapon(kind: WeaponKind.ranged, projectileSpeed: 500);
      final attacker = _spawnAttacker(world, weapon, facingSign: -1);

      world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
      world.step(0.016);

      final id = world.storeOf<Projectile>().entityAt(0);
      expect(world.storeOf<Velocity>().get(id)!.x, -500);
    });
  });

  group('cooldown', () {
    test('firing again before cooldownSeconds has passed is ignored', () {
      final world = _buildWorld();
      // Ranged, not melee: its projectile default lifetime (2s) easily
      // outlives this test's timeline, so Projectile.length below is a
      // reliable "how many shots landed" count -- a melee hitbox's much
      // shorter default lifetime would expire mid-test and undercount.
      final weapon = Weapon(kind: WeaponKind.ranged, cooldownSeconds: 1.0);
      final attacker = _spawnAttacker(world, weapon);
      final weaponStore = world.storeOf<Weapon>();

      weaponStore.get(attacker)!.attackRequested = true;
      world.step(0.1);
      expect(world.storeOf<Projectile>().length, 1);

      weaponStore.get(attacker)!.attackRequested = true;
      world.step(0.1); // only 0.2s since the first shot, well under 1.0s cooldown
      expect(world.storeOf<Projectile>().length, 1, reason: 'still on cooldown');

      // Advance the rest of the way past the cooldown, then request again.
      world.step(1.0);
      weaponStore.get(attacker)!.attackRequested = true;
      world.step(0.1);
      expect(world.storeOf<Projectile>().length, 2);
    });

    test('the attack action from InputState triggers a fire the same as attackRequested', () {
      final world = _buildWorld();
      final attacker = world.spawn();
      world.storeOf<Position>().set(attacker, Position(0, 0));
      world.storeOf<PlatformerController>().set(attacker, PlatformerController());
      world.storeOf<Weapon>().set(attacker, Weapon());
      final input = InputState();
      world.storeOf<InputState>().set(attacker, input);

      input.pressedActions.add('attack');
      world.step(0.016);

      expect(world.storeOf<Projectile>().length, 1);
    });
  });

  test('an entity with no Position is left alone -- no crash, nothing spawned', () {
    final world = _buildWorld();
    final attacker = world.spawn();
    world.storeOf<Weapon>().set(attacker, Weapon());

    world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
    world.step(0.016);

    expect(world.storeOf<Projectile>().length, 0);
  });

  test('end to end: a melee hit against an enemy with Health actually deals damage', () {
    final world = _buildWorld();
    world.addSystem(CollisionSystem());
    installProjectileDamage(world);

    final weapon = Weapon(kind: WeaponKind.melee, damage: 20, meleeRange: 20, meleeRadius: 15);
    final attacker = _spawnAttacker(world, weapon, facingSign: 1);

    final enemy = world.spawn();
    world.storeOf<Position>().set(enemy, Position(115, 100)); // within the hitbox's radius
    world.storeOf<Collider>().set(enemy, Collider(5));
    world.storeOf<Health>().set(enemy, Health(current: 30, max: 30));

    world.storeOf<Weapon>().get(attacker)!.attackRequested = true;
    world.step(0.016);

    expect(world.storeOf<Health>().get(enemy)!.current, 10);
  });
}
