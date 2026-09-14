import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'jump_animation_set.dart';
import '../physics/platformer_controller.dart';

/// Drives `JumpAnimationSet`'s phase clips from the entity's actual jump
/// mechanics (`Velocity.y` and `PlatformerController.grounded`
/// transitions) instead of a fixed timer — see `JumpAnimationSet`'s doc
/// comment for why a real jump arc needs this instead of one clip played
/// on a clock with no idea how high the jump went.
///
/// A pure no-op for any entity without a `JumpAnimationSet` — existing
/// games using only `MovementAnimationSet.jump` (or nothing at all) are
/// completely unaffected by this system's presence in the pack. Must run
/// *after* `MovementAnimationSystem` (see `installPlatformerSystems`):
/// this system only writes `AnimationState` while airborne, or during
/// the brief `landing`/`completed` hold right after touching down, and
/// leaves it alone entirely once back to plain `grounded` — at that
/// point `MovementAnimationSystem`'s own idle/walk write from earlier
/// the same tick is what should stand.
class JumpAnimationSystem implements System {
  @override
  String get name => 'jumpAnimation';

  @override
  void update(World world, double dt) {
    final sets = world.storeOf<JumpAnimationSet>();
    final phaseStates = world.storeOf<JumpAnimationPhaseState>();
    final controllers = world.storeOf<PlatformerController>();
    final velocities = world.storeOf<Velocity>();
    final animStates = world.storeOf<AnimationState>();

    for (var i = 0; i < sets.length; i++) {
      final entity = sets.entityAt(i);
      final set = sets.denseAt(i);
      final controller = controllers.get(entity);
      final vel = velocities.get(entity);
      if (controller == null || vel == null) continue;

      var phaseState = phaseStates.get(entity);
      if (phaseState == null) {
        phaseState = JumpAnimationPhaseState();
        phaseStates.set(entity, phaseState);
      }

      final nextPhase = _nextPhase(set, phaseState, controller, vel, dt);
      if (nextPhase != phaseState.phase) {
        phaseState.phase = nextPhase;
        phaseState.elapsed = 0;
      } else {
        phaseState.elapsed += dt;
      }

      if (nextPhase == null) continue; // grounded -- MovementAnimationSystem owns it

      final target = _clipFor(set, nextPhase);
      final current = animStates.get(entity);
      if (current == null || current.clip.name != target.name) {
        animStates.set(entity, AnimationState(target));
      }
    }
  }

  /// The phase transition table: airborne picks among
  /// start/rising/peak/falling by [PlatformerController.grounded] and
  /// `Velocity.y`; grounded picks among landing/completed/null (fully
  /// done) by how long the entity has held each since touching down.
  String? _nextPhase(
    JumpAnimationSet set,
    JumpAnimationPhaseState phaseState,
    PlatformerController controller,
    Velocity vel,
    double dt,
  ) {
    final phase = phaseState.phase;
    if (!controller.grounded) {
      if (phase == null || phase == 'landing' || phase == 'completed') {
        // Just left the ground (including a fresh jump fired during a
        // landing/completed hold -- e.g. a buffered jump).
        return 'start';
      }
      if (phase == 'start' && phaseState.elapsed < set.startHoldSeconds) {
        return 'start';
      }
      if (vel.y < -set.peakVelocityThreshold) return 'rising';
      if (vel.y > set.peakVelocityThreshold) return 'falling';
      return 'peak';
    }

    // Grounded.
    if (phase == null) return null;
    final movingNow = vel.x.abs() > set.moveInterruptThreshold;
    if (phase == 'landing') {
      if (movingNow) return null; // player wants to move -- don't sit through the recovery beat
      return phaseState.elapsed < set.landingHoldSeconds ? 'landing' : 'completed';
    }
    if (phase == 'completed') {
      if (movingNow) return null;
      return phaseState.elapsed < set.completedHoldSeconds ? 'completed' : null;
    }
    // Was airborne (start/rising/peak/falling) last tick, just touched down.
    return 'landing';
  }

  AnimationClip _clipFor(JumpAnimationSet set, String phase) {
    switch (phase) {
      case 'start':
        return set.start;
      case 'rising':
        return set.rising;
      case 'peak':
        return set.peak;
      case 'falling':
        return set.falling;
      case 'landing':
        return set.landing;
      case 'completed':
        return set.completed;
      default:
        throw StateError('Unknown JumpAnimationSet phase "$phase"');
    }
  }
}
