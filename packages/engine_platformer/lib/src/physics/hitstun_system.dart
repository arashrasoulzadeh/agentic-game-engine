import 'package:engine_core/engine_core.dart';

import 'platformer_controller.dart';

/// Counts `PlatformerController.hitstunSeconds` down each tick.
/// Deliberately does nothing else — same "one job, called from
/// wherever actually applies it" split as `HealthSystem` counting down
/// `Health.invincibleSeconds`: this system doesn't decide *when*
/// hitstun starts (`damageEntity`'s `hitstunSeconds` parameter does),
/// only that it ends on schedule.
class HitstunSystem implements System {
  @override
  String get name => 'hitstun';

  @override
  void update(World world, double dt) {
    final controllers = world.storeOf<PlatformerController>();
    for (var i = 0; i < controllers.length; i++) {
      final controller = controllers.denseAt(i);
      if (controller.hitstunSeconds > 0) {
        controller.hitstunSeconds = (controller.hitstunSeconds - dt).clamp(0, double.infinity);
      }
    }
  }
}
