import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  test('Gravity round-trips through toJson/fromJson', () {
    final decoded = Gravity.fromJson(Gravity(scale: 2).toJson());
    expect(decoded.scale, 2);
  });

  test('Gravity.fromJson defaults scale to 1 when absent', () {
    expect(Gravity.fromJson({}).scale, 1);
  });

  test('PlatformerController round-trips through toJson/fromJson', () {
    final decoded = PlatformerController(
      grounded: true,
      jumpSpeed: 250,
      jumpRequested: true,
    ).toJson();
    final restored = PlatformerController.fromJson(decoded);
    expect(restored.grounded, isTrue);
    expect(restored.jumpSpeed, 250);
    expect(restored.jumpRequested, isTrue);
  });

  test('PlatformerController.fromJson defaults when fields are absent', () {
    final restored = PlatformerController.fromJson({});
    expect(restored.grounded, isFalse);
    expect(restored.jumpSpeed, 300);
    expect(restored.jumpRequested, isFalse);
    expect(restored.jumpCutMultiplier, 1.0);
    expect(restored.jumpHeldLastTick, isFalse);
  });

  test('PlatformerController round-trips jumpCutMultiplier/jumpHeldLastTick', () {
    final restored = PlatformerController.fromJson(
      PlatformerController(jumpCutMultiplier: 0.5, jumpHeldLastTick: true).toJson(),
    );
    expect(restored.jumpCutMultiplier, 0.5);
    expect(restored.jumpHeldLastTick, isTrue);
  });

  test('PlatformerController round-trips hitstunSeconds', () {
    final restored = PlatformerController.fromJson(
      PlatformerController(hitstunSeconds: 0.4).toJson(),
    );
    expect(restored.hitstunSeconds, 0.4);
    expect(PlatformerController.fromJson({}).hitstunSeconds, 0);
  });

  test('PlatformBody round-trips through toJson/fromJson', () {
    final restored = PlatformBody.fromJson(PlatformBody(50, 10, oneWay: true).toJson());
    expect(restored.width, 50);
    expect(restored.height, 10);
    expect(restored.oneWay, isTrue);
  });

  test('PlatformBody.fromJson defaults oneWay to false when absent', () {
    expect(PlatformBody.fromJson({'width': 1, 'height': 2}).oneWay, isFalse);
  });

  test('Health round-trips through toJson/fromJson', () {
    final restored = Health.fromJson(
      Health(current: 4, max: 10, invincibleSeconds: 0.5).toJson(),
    );
    expect(restored.current, 4);
    expect(restored.max, 10);
    expect(restored.invincibleSeconds, 0.5);
  });

  test('Health.fromJson defaults invincibleSeconds to 0 when absent', () {
    expect(Health.fromJson({'current': 1, 'max': 1}).invincibleSeconds, 0);
  });

  test('Checkpoint round-trips through toJson/fromJson', () {
    final restored = Checkpoint.fromJson(Checkpoint('cp1', activated: true).toJson());
    expect(restored.id, 'cp1');
    expect(restored.activated, isTrue);
  });

  test('Checkpoint.fromJson defaults activated to false when absent', () {
    expect(Checkpoint.fromJson({'id': 'cp1'}).activated, isFalse);
  });

  test('LastCheckpoint round-trips through toJson/fromJson', () {
    final restored = LastCheckpoint.fromJson(LastCheckpoint(12, 34).toJson());
    expect(restored.x, 12);
    expect(restored.y, 34);
  });

  test('MovementAnimationSet round-trips through toJson/fromJson, with and without jump', () {
    final withJump = MovementAnimationSet(
      idle: AnimationClip('idle', ['idle_0']),
      walk: AnimationClip('walk', ['walk_0', 'walk_1']),
      jump: AnimationClip('jump', ['jump_0']),
      moveThreshold: 8,
    );
    final restoredWithJump = MovementAnimationSet.fromJson(withJump.toJson());
    expect(restoredWithJump.idle.name, 'idle');
    expect(restoredWithJump.walk.frameRegions, ['walk_0', 'walk_1']);
    expect(restoredWithJump.jump?.name, 'jump');
    expect(restoredWithJump.moveThreshold, 8);

    final withoutJump = MovementAnimationSet(
      idle: AnimationClip('idle', ['idle_0']),
      walk: AnimationClip('walk', ['walk_0']),
    );
    final restoredWithoutJump = MovementAnimationSet.fromJson(withoutJump.toJson());
    expect(restoredWithoutJump.jump, isNull);
    expect(restoredWithoutJump.moveThreshold, 5);
  });

  test('JumpAnimationSet round-trips through toJson/fromJson', () {
    final set = JumpAnimationSet.fromRegions(
      start: ['jump_0'],
      rising: ['jump_1', 'jump_2'],
      peak: ['jump_3'],
      falling: ['jump_4'],
      landing: ['jump_5'],
      completed: ['jump_6'],
    );
    final restored = JumpAnimationSet.fromJson(set.toJson());
    expect(restored.start.frameRegions, ['jump_0']);
    expect(restored.rising.frameRegions, ['jump_1', 'jump_2']);
    expect(restored.peak.frameRegions, ['jump_3']);
    expect(restored.falling.frameRegions, ['jump_4']);
    expect(restored.landing.frameRegions, ['jump_5']);
    expect(restored.completed.frameRegions, ['jump_6']);
  });

  test('JumpAnimationPhaseState round-trips through toJson/fromJson', () {
    final restored = JumpAnimationPhaseState.fromJson(
      JumpAnimationPhaseState(phase: 'falling', elapsed: 0.5).toJson(),
    );
    expect(restored.phase, 'falling');
    expect(restored.elapsed, 0.5);
  });

  test('every registered platformer component serializes through World.toJson', () {
    final world = _buildWorld();

    final gravityEntity = world.spawn();
    world.storeOf<Gravity>().set(gravityEntity, Gravity(scale: 2));

    final platformEntity = world.spawn();
    world.storeOf<PlatformBody>().set(platformEntity, PlatformBody(10, 20));

    final controllerEntity = world.spawn();
    world.storeOf<PlatformerController>().set(controllerEntity, PlatformerController());

    final animSetEntity = world.spawn();
    world.storeOf<MovementAnimationSet>().set(
          animSetEntity,
          MovementAnimationSet(
            idle: AnimationClip('idle', ['idle_0']),
            walk: AnimationClip('walk', ['walk_0']),
          ),
        );

    final healthEntity = world.spawn();
    world.storeOf<Health>().set(healthEntity, Health(current: 5, max: 5));

    final checkpointEntity = world.spawn();
    world.storeOf<Checkpoint>().set(checkpointEntity, Checkpoint('cp1'));

    final lastCheckpointEntity = world.spawn();
    world.storeOf<LastCheckpoint>().set(lastCheckpointEntity, LastCheckpoint(1, 2));

    final inventoryEntity = world.spawn();
    world.storeOf<Inventory>().set(inventoryEntity, Inventory({'coin': 3}));

    final jumpSetEntity = world.spawn();
    world.storeOf<JumpAnimationSet>().set(
          jumpSetEntity,
          JumpAnimationSet.fromRegions(
            start: ['jump_0'],
            rising: ['jump_1'],
            peak: ['jump_2'],
            falling: ['jump_3'],
            landing: ['jump_4'],
            completed: ['jump_5'],
          ),
        );

    final jumpPhaseEntity = world.spawn();
    world.storeOf<JumpAnimationPhaseState>().set(
          jumpPhaseEntity,
          JumpAnimationPhaseState(phase: 'peak', elapsed: 0.1),
        );

    final snapshot = world.toJson();
    final byId = {
      for (final e in snapshot['entities'] as List) (e as Map)['id']: e['components']
    };

    expect(byId[gravityEntity]['gravity']['scale'], 2);
    expect(byId[platformEntity]['platformBody']['width'], 10);
    expect(byId[controllerEntity]['platformerController']['jumpSpeed'], 300);
    expect(byId[animSetEntity]['movementAnimationSet']['idle']['name'], 'idle');
    expect(byId[healthEntity]['health']['current'], 5);
    expect(byId[checkpointEntity]['checkpoint']['id'], 'cp1');
    expect(byId[lastCheckpointEntity]['lastCheckpoint']['x'], 1);
    expect(byId[inventoryEntity]['inventory']['items']['coin'], 3);
    expect(byId[jumpSetEntity]['jumpAnimationSet']['start']['frameRegions'], ['jump_0']);
    expect(byId[jumpPhaseEntity]['jumpAnimationPhaseState']['phase'], 'peak');
  });
}
