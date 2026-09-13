import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  test('damageEntity subtracts current health and starts invincibility', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 10, max: 10));

    final applied = damageEntity(world, id, 4, invincibilitySeconds: 1);

    expect(applied, isTrue);
    final health = world.storeOf<Health>().get(id)!;
    expect(health.current, 6);
    expect(health.isInvincible, isTrue);
  });

  test('damageEntity is a no-op while invincible', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 10, max: 10, invincibleSeconds: 0.5));

    final applied = damageEntity(world, id, 4);

    expect(applied, isFalse);
    expect(world.storeOf<Health>().get(id)!.current, 10);
  });

  test('damageEntity is a no-op for an entity with no Health component', () {
    final world = _buildWorld();
    final id = world.spawn();

    expect(() => damageEntity(world, id, 4), returnsNormally);
    expect(damageEntity(world, id, 4), isFalse);
  });

  test('damageEntity emits DeathEvent exactly once when health drops to 0', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 5, max: 10));

    var deaths = 0;
    world.events.on<DeathEvent>((e) {
      if (e.entity == id) deaths++;
    });

    damageEntity(world, id, 10, invincibilitySeconds: 0);
    world.step(0);
    // Already dead -- further damage must not re-emit.
    damageEntity(world, id, 10, invincibilitySeconds: 0);
    world.step(0);

    expect(deaths, 1);
  });

  test('HealthSystem counts invincibleSeconds down and clamps at 0', () {
    final world = _buildWorld();
    world.addSystem(HealthSystem());
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 10, max: 10, invincibleSeconds: 0.3));

    world.step(0.2);
    expect(world.storeOf<Health>().get(id)!.invincibleSeconds, closeTo(0.1, 0.001));

    world.step(0.2);
    expect(world.storeOf<Health>().get(id)!.invincibleSeconds, 0);
  });

  test('healEntity restores current health clamped to max', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 5, max: 10));

    healEntity(world, id, 3);
    expect(world.storeOf<Health>().get(id)!.current, 8);

    healEntity(world, id, 100);
    expect(world.storeOf<Health>().get(id)!.current, 10);
  });

  test('dealDamageOnTouch damages whoever collides with a hazard', () {
    final world = _buildWorld();
    world.addSystem(CollisionSystem());
    final hazard = world.spawn();
    world.storeOf<Position>().set(hazard, Position(0, 0));
    world.storeOf<Collider>().set(hazard, Collider(10));

    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(5, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Health>().set(player, Health(current: 10, max: 10));

    dealDamageOnTouch(world, {hazard}, 3);
    world.step(0);

    expect(world.storeOf<Health>().get(player)!.current, 7);
  });

  group('knockback', () {
    test('damageEntity pushes the entity away from source at knockbackSpeed', () {
      final world = _buildWorld();
      final source = world.spawn();
      world.storeOf<Position>().set(source, Position(0, 0));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 0)); // directly to the right of source
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));

      damageEntity(world, id, 1, source: source, knockbackSpeed: 200);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, closeTo(200, 0.001));
      expect(vel.y, closeTo(0, 0.001));
    });

    test('does nothing when knockbackSpeed is 0 (default)', () {
      final world = _buildWorld();
      final source = world.spawn();
      world.storeOf<Position>().set(source, Position(0, 0));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 0));
      world.storeOf<Velocity>().set(id, Velocity(5, 5));
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));

      damageEntity(world, id, 1, source: source);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 5);
      expect(vel.y, 5);
    });

    test('does nothing when source and entity share the same position', () {
      final world = _buildWorld();
      final source = world.spawn();
      world.storeOf<Position>().set(source, Position(0, 0));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0)); // same spot -- no direction to push
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));

      expect(() => damageEntity(world, id, 1, source: source, knockbackSpeed: 200), returnsNormally);
      expect(world.storeOf<Velocity>().get(id)!.x, 0);
    });

    test('dealDamageOnTouch uses the touched hazard as the knockback source', () {
      final world = _buildWorld();
      world.addSystem(CollisionSystem());
      final hazard = world.spawn();
      world.storeOf<Position>().set(hazard, Position(0, 0));
      world.storeOf<Collider>().set(hazard, Collider(10));

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(5, 0));
      world.storeOf<Collider>().set(player, Collider(10));
      world.storeOf<Velocity>().set(player, Velocity(0, 0));
      world.storeOf<Health>().set(player, Health(current: 10, max: 10));

      dealDamageOnTouch(world, {hazard}, 3, knockbackSpeed: 150);
      world.step(0);

      expect(world.storeOf<Velocity>().get(player)!.x, closeTo(150, 0.001));
    });
  });

  group('hitstun', () {
    test('damageEntity sets PlatformerController.hitstunSeconds when hitstunSeconds is given', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));
      world.storeOf<PlatformerController>().set(id, PlatformerController());

      damageEntity(world, id, 1, hitstunSeconds: 0.3);

      expect(world.storeOf<PlatformerController>().get(id)!.hitstunSeconds, 0.3);
    });

    test('does nothing when hitstunSeconds is 0 (default)', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));
      world.storeOf<PlatformerController>().set(id, PlatformerController());

      damageEntity(world, id, 1);

      expect(world.storeOf<PlatformerController>().get(id)!.hitstunSeconds, 0);
    });

    test('is a no-op for an entity with no PlatformerController', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(current: 10, max: 10));

      expect(() => damageEntity(world, id, 1, hitstunSeconds: 0.3), returnsNormally);
    });

    test('HitstunSystem counts hitstunSeconds down and clamps at 0', () {
      final world = _buildWorld();
      world.addSystem(HitstunSystem());
      final id = world.spawn();
      world.storeOf<PlatformerController>().set(id, PlatformerController(hitstunSeconds: 0.3));

      world.step(0.2);
      expect(world.storeOf<PlatformerController>().get(id)!.hitstunSeconds, closeTo(0.1, 0.001));

      world.step(0.2);
      expect(world.storeOf<PlatformerController>().get(id)!.hitstunSeconds, 0);
    });

    test('PlatformerInputSystem ignores all input while hitstunSeconds > 0', () {
      final world = _buildWorld();
      final input = InputState();
      final id = world.spawn();
      world.storeOf<InputState>().set(id, input);
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<PlatformerController>().set(id, PlatformerController(hitstunSeconds: 0.5));
      world.addSystem(PlatformerInputSystem(id));

      input.pressedActions.add('right');
      input.pressedActions.add('jump');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.x, 0, reason: 'movement input ignored while stunned');
      expect(world.storeOf<PlatformerController>().get(id)!.jumpRequested, isFalse,
          reason: 'jump input ignored while stunned');
    });

    test('PlatformerInputSystem resumes handling input once hitstun expires', () {
      final world = _buildWorld();
      final input = InputState();
      final id = world.spawn();
      world.storeOf<InputState>().set(id, input);
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<PlatformerController>().set(id, PlatformerController(hitstunSeconds: 0));
      world.addSystem(PlatformerInputSystem(id));

      input.pressedActions.add('right');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.x, greaterThan(0));
    });
  });
}
