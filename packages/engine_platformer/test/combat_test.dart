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
  group('guard/block', () {
    test('damageEntity blocks damage when guarding with full reduction', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: true,
        guardDamageReduction: 1.0,
        stability: 100,
        maxStability: 100,
      ));

      final applied = damageEntity(world, id, 4, invincibilitySeconds: 0);
      world.step(0);

      expect(applied, isTrue);
      final health = world.storeOf<Health>().get(id)!;
      expect(health.current, 10); // No health lost
      expect(health.stability, 96); // Stability depleted by 4
    });

    test('damageEntity blocks partial damage when guardDamageReduction < 1.0', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: true,
        guardDamageReduction: 0.5, // 50% reduction
        stability: 100,
        maxStability: 100,
      ));

      damageEntity(world, id, 4, invincibilitySeconds: 0);
      world.step(0);

      final health = world.storeOf<Health>().get(id)!;
      expect(health.current, 8); // 2 damage got through (4 * 0.5)
      expect(health.stability, 98); // 2 stability lost (4 * 0.5)
    });

    test('damageEntity emits BlockedEvent when guarding', () {
      final world = _buildWorld();
      final source = world.spawn();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: true,
        guardDamageReduction: 1.0,
        stability: 100,
        maxStability: 100,
      ));

      BlockedEvent? seen;
      world.events.on<BlockedEvent>((e) => seen = e);

      damageEntity(world, id, 4, source: source, invincibilitySeconds: 0);
      world.step(0);

      expect(seen, isNotNull);
      expect(seen!.entity, id);
      expect(seen!.originalDamage, 4);
      expect(seen!.stabilityLost, 4);
      expect(seen!.source, source);
    });

    test('damageEntity breaks guard when stability depleted', () {
      final world = _buildWorld();
      final source = world.spawn();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: true,
        guardDamageReduction: 1.0,
        stability: 3, // Low stability
        maxStability: 100,
        guardBreakStunSeconds: 1.0,
      ));

      GuardBreakEvent? breakSeen;
      world.events.on<GuardBreakEvent>((e) => breakSeen = e);

      // This hit depletes stability and breaks guard
      damageEntity(world, id, 5, source: source, invincibilitySeconds: 0);
      world.step(0);

      final health = world.storeOf<Health>().get(id)!;
      expect(health.stability, 0);
      expect(health.isGuarding, isFalse); // Guard broken
      expect(health.guardBreakTimer, 1.0); // Stun started
      expect(health.current, 5); // Full 5 damage taken (guard broken)
      expect(breakSeen, isNotNull);
      expect(breakSeen!.entity, id);
      expect(breakSeen!.source, source);
    });

    test('guard break stun prevents guarding until timer expires', () {
      final world = _buildWorld();
      world.addSystem(HealthSystem());
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: false,
        guardDamageReduction: 1.0,
        stability: 0,
        maxStability: 100,
        guardBreakStunSeconds: 0.5,
        guardBreakTimer: 0.5, // Mid stun
      ));

      final health = world.storeOf<Health>().get(id)!;
      expect(health.canGuard, isFalse);

      world.step(0.3);
      final health2 = world.storeOf<Health>().get(id)!;
      expect(health2.canGuard, isFalse); // Still in stun

      world.step(0.3); // Total 0.6 > 0.5
      final health3 = world.storeOf<Health>().get(id)!;
      expect(health3.canGuard, isTrue); // Stun over, can guard again (if stability > 0)
    });

    test('HealthSystem regenerates stability when not guarding and not broken', () {
      final world = _buildWorld();
      world.addSystem(HealthSystem());
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: false,
        stability: 50,
        maxStability: 100,
        stabilityRegenPerSecond: 20,
      ));

      world.step(1.0); // 1 second = 20 regen
      expect(world.storeOf<Health>().get(id)!.stability, closeTo(70, 0.001));

      world.step(2.0); // 2 more seconds = 40 regen, capped at 100
      expect(world.storeOf<Health>().get(id)!.stability, 100);
    });

    test('HealthSystem does not regen stability while guarding', () {
      final world = _buildWorld();
      world.addSystem(HealthSystem());
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: true,
        stability: 50,
        maxStability: 100,
        stabilityRegenPerSecond: 20,
      ));

      world.step(1.0);
      expect(world.storeOf<Health>().get(id)!.stability, 50); // No regen while guarding
    });

    test('HealthSystem does not regen stability while guard broken', () {
      final world = _buildWorld();
      world.addSystem(HealthSystem());
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        isGuarding: false,
        stability: 50,
        maxStability: 100,
        stabilityRegenPerSecond: 20,
        guardBreakTimer: 1.0,
      ));

      world.step(1.0);
      expect(world.storeOf<Health>().get(id)!.stability, 50); // No regen while guard broken
    });

    test('restoreStability restores stability clamped to max', () {
      final world = _buildWorld();
      final id = world.spawn();
      world.storeOf<Health>().set(id, Health(
        current: 10,
        max: 10,
        stability: 50,
        maxStability: 100,
      ));

      restoreStability(world, id, 30);
      expect(world.storeOf<Health>().get(id)!.stability, 80);

      restoreStability(world, id, 100);
      expect(world.storeOf<Health>().get(id)!.stability, 100); // Clamped
    });

    test('Health.toJson/fromJson round-trips guard fields', () {
      final health = Health(
        current: 10,
        max: 20,
        invincibleSeconds: 0.3,
        isGuarding: true,
        guardDamageReduction: 0.75,
        stability: 60,
        maxStability: 120,
        guardBreakStunSeconds: 1.5,
        guardBreakTimer: 0.5,
        stabilityRegenPerSecond: 15,
      );

      final restored = Health.fromJson(health.toJson());

      expect(restored.current, 10);
      expect(restored.max, 20);
      expect(restored.invincibleSeconds, 0.3);
      expect(restored.isGuarding, true);
      expect(restored.guardDamageReduction, 0.75);
      expect(restored.stability, 60);
      expect(restored.maxStability, 120);
      expect(restored.guardBreakStunSeconds, 1.5);
      expect(restored.guardBreakTimer, 0.5);
      expect(restored.stabilityRegenPerSecond, 15);
    });

    test('Health.fromJson defaults guard fields correctly', () {
      final restored = Health.fromJson({'current': 10, 'max': 10});

      expect(restored.isGuarding, false);
      expect(restored.guardDamageReduction, 1.0);
      expect(restored.stability, 0);
      expect(restored.maxStability, 0);
      expect(restored.guardBreakStunSeconds, 1.0);
      expect(restored.guardBreakTimer, 0);
      expect(restored.stabilityRegenPerSecond, 10);
      expect(restored.effectiveMaxStability, 10); // Defaults to max
    });
  });
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

  test('damageEntity emits DamageEvent with the amount and source', () {
    final world = _buildWorld();
    final source = world.spawn();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 10, max: 10));

    DamageEvent? seen;
    world.events.on<DamageEvent>((e) => seen = e);

    damageEntity(world, id, 4, source: source, invincibilitySeconds: 0);
    world.step(0);

    expect(seen, isNotNull);
    expect(seen!.entity, id);
    expect(seen!.amount, 4);
    expect(seen!.source, source);
  });

  test('damageEntity does not emit DamageEvent when the hit is a no-op (invincible)', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 10, max: 10, invincibleSeconds: 0.5));

    var damageEvents = 0;
    world.events.on<DamageEvent>((e) => damageEvents++);

    damageEntity(world, id, 4);
    world.step(0);

    expect(damageEvents, 0);
  });

  test('a killing blow emits both DamageEvent and DeathEvent', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Health>().set(id, Health(current: 5, max: 10));

    var damageEvents = 0;
    var deathEvents = 0;
    world.events.on<DamageEvent>((e) => damageEvents++);
    world.events.on<DeathEvent>((e) => deathEvents++);

    damageEntity(world, id, 10, invincibilitySeconds: 0);
    world.step(0);

    expect(damageEvents, 1);
    expect(deathEvents, 1);
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

  group('parry', () {
    test('damageEntity parries hit when target has active parry window', () {
      final world = _buildWorld();
      final attacker = world.spawn();
      world.storeOf<PlatformerController>().set(attacker, PlatformerController());
      final defender = world.spawn();
      world.storeOf<Health>().set(defender, Health(current: 10, max: 10));
      world.storeOf<Parry>().set(defender, Parry(parryTimer: 0.2, parryStunSeconds: 0.5));

      final applied = damageEntity(world, defender, 5, source: attacker);
      world.step(0);

      expect(applied, isTrue); // Parry counts as "applied" in terms of event handling
      final health = world.storeOf<Health>().get(defender)!;
      expect(health.current, 10); // No damage taken
      expect(world.storeOf<Parry>().get(defender)!.parryTimer, 0); // Parry consumed

      final attackerController = world.storeOf<PlatformerController>().get(attacker)!;
      expect(attackerController.hitstunSeconds, 0.5); // Attacker stunned
    });

    test('damageEntity emits ParrySuccessEvent on successful parry', () {
      final world = _buildWorld();
      final attacker = world.spawn();
      final defender = world.spawn();
      world.storeOf<Health>().set(defender, Health(current: 10, max: 10));
      world.storeOf<Parry>().set(defender, Parry(parryTimer: 0.2));

      ParrySuccessEvent? seen;
      world.events.on<ParrySuccessEvent>((e) => seen = e);

      damageEntity(world, defender, 5, source: attacker);
      world.step(0);

      expect(seen, isNotNull);
      expect(seen!.defender, defender);
      expect(seen!.attacker, attacker);
    });

    test('damageEntity does not parry when parry window expired', () {
      final world = _buildWorld();
      final attacker = world.spawn();
      world.storeOf<PlatformerController>().set(attacker, PlatformerController());
      final defender = world.spawn();
      world.storeOf<Health>().set(defender, Health(current: 10, max: 10));
      world.storeOf<Parry>().set(defender, Parry(parryTimer: 0)); // No active parry

      damageEntity(world, defender, 5, source: attacker, invincibilitySeconds: 0);
      world.step(0);

      final health = world.storeOf<Health>().get(defender)!;
      expect(health.current, 5); // Full damage taken
    });

    test('damageEntity does not parry when no Parry component', () {
      final world = _buildWorld();
      final attacker = world.spawn();
      world.storeOf<PlatformerController>().set(attacker, PlatformerController());
      final defender = world.spawn();
      world.storeOf<Health>().set(defender, Health(current: 10, max: 10));
      // No Parry component

      damageEntity(world, defender, 5, source: attacker, invincibilitySeconds: 0);
      world.step(0);

      final health = world.storeOf<Health>().get(defender)!;
      expect(health.current, 5); // Full damage taken
    });

    test('damageEntity does not parry when source is null', () {
      final world = _buildWorld();
      final defender = world.spawn();
      world.storeOf<Health>().set(defender, Health(current: 10, max: 10));
      world.storeOf<Parry>().set(defender, Parry(parryTimer: 0.2));

      damageEntity(world, defender, 5, invincibilitySeconds: 0); // No source
      world.step(0);

      final health = world.storeOf<Health>().get(defender)!;
      expect(health.current, 5); // Full damage taken (no attacker to stun)
    });

    test('Parry.requestParry starts window and cooldown', () {
      final parry = Parry(parryWindowSeconds: 0.15, parryCooldownSeconds: 0.5);
      expect(parry.canParry, isTrue);

      final result = parry.requestParry();
      expect(result, isTrue);
      expect(parry.isParrying, isTrue);
      expect(parry.parryTimer, 0.15);
      expect(parry.canParry, isFalse);
      expect(parry.parryCooldownTimer, 0.5);
    });

    test('Parry.requestParry fails when on cooldown', () {
      final parry = Parry(parryCooldownTimer: 0.3, parryCooldownSeconds: 0.5);
      expect(parry.canParry, isFalse);

      final result = parry.requestParry();
      expect(result, isFalse);
      expect(parry.parryTimer, 0);
    });

    test('ParrySystem counts down parry timer and cooldown', () {
      final world = _buildWorld();
      world.addSystem(ParrySystem());
      final id = world.spawn();
      world.storeOf<Parry>().set(id, Parry(parryTimer: 0.3, parryCooldownTimer: 0.4));

      world.step(0.2);
      var parry = world.storeOf<Parry>().get(id)!;
      expect(parry.parryTimer, closeTo(0.1, 0.001));
      expect(parry.parryCooldownTimer, closeTo(0.2, 0.001));

      world.step(0.2);
      parry = world.storeOf<Parry>().get(id)!;
      expect(parry.parryTimer, 0);
      expect(parry.parryCooldownTimer, 0);
    });

    test('Parry.toJson/fromJson round-trips', () {
      final parry = Parry(
        parryTimer: 0.1,
        parryCooldownTimer: 0.2,
        parryWindowSeconds: 0.2,
        parryStunSeconds: 0.6,
        parryCooldownSeconds: 0.8,
      );

      final restored = Parry.fromJson(parry.toJson());

      expect(restored.parryTimer, 0.1);
      expect(restored.parryCooldownTimer, 0.2);
      expect(restored.parryWindowSeconds, 0.2);
      expect(restored.parryStunSeconds, 0.6);
      expect(restored.parryCooldownSeconds, 0.8);
    });

    test('Parry.fromJson defaults correctly', () {
      final restored = Parry.fromJson({});

      expect(restored.parryTimer, 0);
      expect(restored.parryCooldownTimer, 0);
      expect(restored.parryWindowSeconds, 0.15);
      expect(restored.parryStunSeconds, 0.5);
      expect(restored.parryCooldownSeconds, 0.5);
    });
  });
}
