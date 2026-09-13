import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'movement_animation_set.dart';
import '../physics/platformer_controller.dart';

/// Picks idle/walk/jump from an entity's `MovementAnimationSet` based on
/// its current `Velocity`/`PlatformerController.grounded`, and swaps
/// `AnimationState`'s clip when the picked clip changes — leaves the
/// actual frame advancement to `AnimationSystem` (this only decides
/// *which* clip should be playing, run before `AnimationSystem` so the
/// swap takes effect the same tick).
class MovementAnimationSystem implements System {
  @override
  String get name => 'movementAnimation';

  @override
  void update(World world, double dt) {
    final sets = world.storeOf<MovementAnimationSet>();
    final velocities = world.storeOf<Velocity>();
    final animStates = world.storeOf<AnimationState>();
    final controllers = world.storeOf<PlatformerController>();

    for (var i = 0; i < sets.length; i++) {
      final entity = sets.entityAt(i);
      final set = sets.denseAt(i);
      final vel = velocities.get(entity);
      if (vel == null) continue;

      final controller = controllers.get(entity);
      final airborne = controller != null && !controller.grounded;

      final target = (airborne && set.jump != null)
          ? set.jump!
          : (vel.x.abs() > set.moveThreshold ? set.walk : set.idle);

      final current = animStates.get(entity);
      if (current == null || current.clip.name != target.name) {
        animStates.set(entity, AnimationState(target));
      }
    }
  }
}
