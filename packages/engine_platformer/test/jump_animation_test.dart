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

JumpAnimationSet _set({
  double startHoldSeconds = 0.05,
  double landingHoldSeconds = 0.05,
  double completedHoldSeconds = 0.05,
  double peakVelocityThreshold = 40,
  double moveInterruptThreshold = 5,
}) =>
    JumpAnimationSet.fromRegions(
      start: ['jump_0'],
      rising: ['jump_1', 'jump_2'],
      peak: ['jump_3'],
      falling: ['jump_4'],
      landing: ['jump_5'],
      completed: ['jump_6'],
      startHoldSeconds: startHoldSeconds,
      landingHoldSeconds: landingHoldSeconds,
      completedHoldSeconds: completedHoldSeconds,
      peakVelocityThreshold: peakVelocityThreshold,
      moveInterruptThreshold: moveInterruptThreshold,
    );

void main() {
  group('JumpAnimationSet', () {
    test('round-trips through toJson/fromJson', () {
      final set = _set();
      final restored = JumpAnimationSet.fromJson(set.toJson());
      expect(restored.start.frameRegions, ['jump_0']);
      expect(restored.rising.frameRegions, ['jump_1', 'jump_2']);
      expect(restored.peak.frameRegions, ['jump_3']);
      expect(restored.falling.frameRegions, ['jump_4']);
      expect(restored.landing.frameRegions, ['jump_5']);
      expect(restored.completed.frameRegions, ['jump_6']);
      expect(restored.peakVelocityThreshold, set.peakVelocityThreshold);
      expect(restored.startHoldSeconds, set.startHoldSeconds);
      expect(restored.landingHoldSeconds, set.landingHoldSeconds);
      expect(restored.completedHoldSeconds, set.completedHoldSeconds);
      expect(restored.moveInterruptThreshold, set.moveInterruptThreshold);
    });
  });

  group('JumpAnimationPhaseState', () {
    test('round-trips through toJson/fromJson, phase omitted from toJson when null', () {
      final grounded = JumpAnimationPhaseState();
      expect(grounded.toJson().containsKey('phase'), isFalse);

      final airborne = JumpAnimationPhaseState(phase: 'rising', elapsed: 0.2);
      final restored = JumpAnimationPhaseState.fromJson(airborne.toJson());
      expect(restored.phase, 'rising');
      expect(restored.elapsed, 0.2);
    });
  });

  group('JumpAnimationSystem', () {
    test('a no-op for an entity with no JumpAnimationSet at all', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: false));
      world.storeOf<Velocity>().set(id, Velocity(0, -500));

      world.step(0.016); // should not throw, and touches nothing

      expect(world.storeOf<AnimationState>().has(id), isFalse);
    });

    test('leaves AnimationState untouched while grounded and never having jumped', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(id, _set());
      world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: true));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));

      world.step(0.016);

      expect(world.storeOf<AnimationState>().has(id), isFalse);
    });

    test('liftoff shows start, held for startHoldSeconds before velocity picks the next phase',
        () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(id, _set(startHoldSeconds: 0.05));
      final controller = PlatformerController(grounded: false);
      world.storeOf<PlatformerController>().set(id, controller);
      world.storeOf<Velocity>().set(id, Velocity(0, -500)); // fast ascent

      world.step(0.02); // liftoff tick
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_0']);

      world.step(0.02); // well under startHoldSeconds (0.05) -- must still be holding start
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_0']);

      // Keep stepping until the hold actually expires (a handful of 0.02s
      // ticks past 0.05) rather than hand-counting exactly which tick
      // crosses the threshold -- the hold expiring at all, and landing on
      // the velocity-correct phase once it does, is what's under test.
      for (var i = 0; i < 5; i++) {
        world.step(0.02);
      }
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_1', 'jump_2'],
          reason: 'fast upward velocity should read as rising once the start hold expires');
    });

    test('picks peak/falling from Velocity.y once past the start hold', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(id, _set(startHoldSeconds: 0));
      world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: false));
      final vel = Velocity(0, -500);
      world.storeOf<Velocity>().set(id, vel);

      world.step(0.016); // liftoff tick always shows start, regardless of startHoldSeconds
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_0']);
      world.step(0.016); // startHoldSeconds is 0, so this tick re-evaluates by velocity
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_1', 'jump_2']);

      vel.y = 0; // at the apex
      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_3']);

      vel.y = 500; // falling
      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_4']);
    });

    test('landing on touchdown, then completed, then hands back to nothing (null phase)', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(
            id,
            _set(startHoldSeconds: 0, landingHoldSeconds: 0.03, completedHoldSeconds: 0.03),
          );
      final controller = PlatformerController(grounded: false);
      world.storeOf<PlatformerController>().set(id, controller);
      world.storeOf<Velocity>().set(id, Velocity(0, 500)); // falling

      world.step(0.016); // liftoff tick always shows start first
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_0']);
      world.step(0.016); // now past the (zero) start hold -- velocity picks falling
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_4']);

      controller.grounded = true; // touchdown
      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_5'],
          reason: 'landing impact pose on the touchdown tick');

      world.step(0.02); // still under landingHoldSeconds (0.03)
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_5']);

      // Keep stepping until the phase actually reaches 'completed' (see
      // the similar loop above for why this doesn't hand-count exact
      // ticks) -- stop there rather than overshooting past its own hold
      // too, since completedHoldSeconds is short enough to blow through
      // in just a couple more arbitrary steps.
      final phaseState = world.storeOf<JumpAnimationPhaseState>().get(id)!;
      for (var i = 0; i < 5 && phaseState.phase != 'completed'; i++) {
        world.step(0.02);
      }
      expect(phaseState.phase, 'completed');
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_6'],
          reason: 'recovers to the completed/standing pose once the landing hold expires');
    });

    test(
        'pressing movement during the landing/completed hold cuts it short instead of '
        'locking the player out of moving -- reported live as walking looking '
        '"stuck"/unresponsive right after touching down', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(
            id,
            _set(startHoldSeconds: 0, landingHoldSeconds: 1, moveInterruptThreshold: 5),
          );
      final controller = PlatformerController(grounded: false);
      world.storeOf<PlatformerController>().set(id, controller);
      final vel = Velocity(0, 500); // falling
      world.storeOf<Velocity>().set(id, vel);

      world.step(0.016); // liftoff -- 'start'
      world.step(0.016); // now falling

      controller.grounded = true; // touchdown
      world.step(0.016);
      expect(world.storeOf<JumpAnimationPhaseState>().get(id)!.phase, 'landing');

      // Player immediately presses a movement key -- landingHoldSeconds
      // is 1 full second, so without the interrupt this would still be
      // showing 'landing' for a very long time.
      vel.x = 200;
      world.step(0.016);
      expect(world.storeOf<JumpAnimationPhaseState>().get(id)!.phase, isNull,
          reason: 'hands control back to MovementAnimationSystem immediately '
              'rather than waiting out the hold');
    });

    test(
        'no horizontal input during landing/completed does NOT trigger the movement '
        'interrupt -- the hold plays out normally when the player is not trying to move',
        () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(
            id,
            _set(startHoldSeconds: 0, landingHoldSeconds: 1),
          );
      final controller = PlatformerController(grounded: false);
      world.storeOf<PlatformerController>().set(id, controller);
      world.storeOf<Velocity>().set(id, Velocity(0, 500));

      world.step(0.016);
      world.step(0.016);
      controller.grounded = true;
      world.step(0.016);
      expect(world.storeOf<JumpAnimationPhaseState>().get(id)!.phase, 'landing');

      world.step(0.016); // still no horizontal velocity -- hold should continue
      expect(world.storeOf<JumpAnimationPhaseState>().get(id)!.phase, 'landing');
    });

    test(
        'a JumpAnimationSet on an entity that also has MovementAnimationSet overrides the '
        "latter's plain jump/idle/walk selection while airborne", () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<MovementAnimationSet>().set(
            id,
            MovementAnimationSet(
              idle: AnimationClip('idle', ['idle_0']),
              walk: AnimationClip('walk', ['walk_0']),
            ),
          );
      world.storeOf<JumpAnimationSet>().set(id, _set(startHoldSeconds: 0));
      world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: false));
      world.storeOf<Velocity>().set(id, Velocity(0, -500));

      world.step(0.016); // liftoff tick: JumpAnimationSystem should win with 'start'
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_0']);

      world.step(0.016);
      // MovementAnimationSystem alone (no MovementAnimationSet.jump) would
      // have picked 'idle' here (vel.x is 0) -- JumpAnimationSystem running
      // after it must win instead.
      expect(world.storeOf<AnimationState>().get(id)!.clip.frameRegions, ['jump_1', 'jump_2']);
    });

    test('does not reset an already-playing phase clip of the same phase', () {
      final world = _buildWorld();
      world.addSystem(JumpAnimationSystem());
      final id = world.spawn();
      world.storeOf<JumpAnimationSet>().set(id, _set(startHoldSeconds: 0));
      world.storeOf<PlatformerController>().set(id, PlatformerController(grounded: false));
      world.storeOf<Velocity>().set(id, Velocity(0, -500));

      world.step(0.016); // liftoff -- 'start'
      world.step(0.016); // now 'rising' (a real phase change, resets playback once)
      final firstState = world.storeOf<AnimationState>().get(id)!;
      expect(firstState.clip.frameRegions, ['jump_1', 'jump_2']);
      firstState.frameIndex = 1;
      firstState.elapsed = 0.03;

      world.step(0.016); // still rising -- should not have reset playback again
      final secondState = world.storeOf<AnimationState>().get(id)!;
      expect(secondState.frameIndex, 1);
      expect(secondState.elapsed, 0.03,
          reason: 'JumpAnimationSystem should not touch AnimationState at all while the '
              'phase is unchanged -- AnimationSystem (not under test here) is what '
              'normally advances elapsed/frameIndex');
    });
  });
}
