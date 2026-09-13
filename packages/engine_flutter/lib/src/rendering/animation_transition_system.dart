import 'package:engine_core/engine_core.dart';

import 'animation_transition.dart';

/// Counts `AnimationTransition.remainingSeconds` down each tick and
/// removes the component once it reaches `0` — same one-job split as
/// `HealthSystem`/`HitstunSystem` counting down their own timers.
class AnimationTransitionSystem implements System {
  @override
  String get name => 'animationTransition';

  @override
  void update(World world, double dt) {
    final transitions = world.storeOf<AnimationTransition>();
    final done = <EntityId>[];
    for (var i = 0; i < transitions.length; i++) {
      final entity = transitions.entityAt(i);
      final transition = transitions.denseAt(i);
      transition.remainingSeconds -= dt;
      if (transition.remainingSeconds <= 0) done.add(entity);
    }
    for (final entity in done) {
      transitions.remove(entity);
    }
  }
}
