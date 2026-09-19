import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  test('projectiles, HUD links and water survive the component registry', () {
    final world = buildWorld();
    final id = spawnProjectile(world, x: 1, y: 2, vx: 3, vy: 4,
        damage: 5, atlasId: 'weapons', spriteRegion: 'arrow');
    world.storeOf<HealthHudLink>().set(id, HealthHudLink(42));
    world.storeOf<WaterZone>().set(id, WaterZone(20, 30));
    world.storeOf<Weapon>().set(id, Weapon());
    final data = world.components.serializeEntity(id);
    final copy = world.spawn();
    world.components.applyToEntity(copy, data);
    expect(world.components.serializeEntity(copy), data);
    expect(world.storeOf<HealthHudLink>().get(copy)!.source, 42);
    expect(world.storeOf<Sprite>().get(copy)!.region, 'arrow');
    expect(world.storeOf<Projectile>().get(copy)!.damage, 5);
  });

  test('path following without a position stops horizontal drift only', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Velocity>().set(id, Velocity(50, 17));
    final behavior = PathFollowBehavior([PathPoint(100, 100)]);
    behavior.decide(WorldView(world), id).apply(world);
    expect(world.storeOf<Velocity>().get(id)!.x, 0);
    expect(world.storeOf<Velocity>().get(id)!.y, 17);
    expect(behavior.currentTarget!.x, 100);
  });

  test('a wall on the left records contact and clamps falling speed', () {
    final controller = PlatformerController(wallSlideMaxFallSpeed: 25);
    final velocity = Velocity(-10, 90);
    applyCollisionSideToController(side: CollisionSide.right,
        controller: controller, vel: velocity);
    expect(controller.touchingWallLeft, isTrue);
    expect(controller.touchingWallRight, isFalse);
    expect(velocity.y, 25);
    expect(velocity.x, -10);
    applyCollisionSideToController(side: CollisionSide.left,
        controller: controller, vel: velocity);
    expect(controller.touchingWallRight, isTrue);
  });

  test('downward ladder input overrides vertical movement and clears grounding', () {
    final world = buildWorld();
    final id = world.spawn();
    final controller = PlatformerController(climbSpeed: 60, grounded: true)
      ..onLadder = true;
    world.storeOf<PlatformerController>().set(id, controller);
    world.storeOf<Velocity>().set(id, Velocity(4, -100));
    world.storeOf<InputState>().set(id, InputState({'down'}));
    LadderSystem(id).update(world, 0.1);
    expect(world.storeOf<Velocity>().get(id)!.y, 60);
    expect(world.storeOf<Velocity>().get(id)!.x, 4);
    expect(controller.grounded, isFalse);
  });

  test('dash input requests a dash on the player controller', () {
    final world = buildWorld();
    final id = world.spawn();
    final controller = PlatformerController();
    world.storeOf<PlatformerController>().set(id, controller);
    world.storeOf<Velocity>().set(id, Velocity(0, 0));
    world.storeOf<InputState>().set(id, InputState({'dash'}));
    PlatformerInputSystem(id).update(world, 0.1);
    expect(controller.dashRequested, isTrue);
    expect(controller.jumpRequested, isFalse);
    expect(BossPhaseSystem(id, []).name, 'bossPhase');
  });

  test('moving interrupts the completed jump recovery phase', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: true));
    world.storeOf<Velocity>().set(id, Velocity(100, 0));
    world.storeOf<JumpAnimationSet>().set(id, JumpAnimationSet.fromRegions(
      start: ['start'], rising: ['rising'], peak: ['peak'],
      falling: ['falling'], landing: ['landing'], completed: ['completed'],
    ));
    final phase = JumpAnimationPhaseState(phase: 'completed');
    world.storeOf<JumpAnimationPhaseState>().set(id, phase);
    JumpAnimationSystem().update(world, 0.01);
    expect(phase.phase, isNull);
    world.storeOf<Velocity>().get(id)!.x = 0;
    phase.phase = 'completed';
    phase.elapsed = 0;
    JumpAnimationSystem().update(world, 0.01);
    expect(phase.phase, 'completed');
    phase.elapsed = 100;
    JumpAnimationSystem().update(world, 0.01);
    expect(phase.phase, isNull);
  });
}
