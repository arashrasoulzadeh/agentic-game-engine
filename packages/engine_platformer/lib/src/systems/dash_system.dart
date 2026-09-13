import 'package:engine_core/engine_core.dart';

import '../components/platformer_controller.dart';

/// Consumes `PlatformerController.dashRequested`: a fixed-duration
/// horizontal speed burst in the entity's last-faced direction
/// (`facingSign`, maintained by `PlatformerInputSystem`). Disabled by
/// default (`dashSpeed == 0`) — opt in per entity by setting `dashSpeed`
/// on its `PlatformerController`.
///
/// While `dashTimeRemaining > 0`, this system overrides `Velocity.x`
/// every tick (so normal horizontal input has no effect mid-dash — the
/// point of a dash) and counts the timer down; once it reaches `0`,
/// normal input-driven movement resumes on its own the next tick
/// (`PlatformerInputSystem` sets `Velocity.x` again as usual). Doesn't
/// touch `Velocity.y` — an "air dash" here is horizontal-only; a game
/// wanting a vertical or diagonal dash can read `dashRequested` itself
/// instead of using this system.
///
/// One dash per ground contact by default: `dashRequested` while
/// `dashUsed` is already true (and the entity isn't currently mid-dash)
/// is ignored. `dashUsed` resets when `JumpSystem` sees `grounded`
/// become true, mirroring `airJumpsUsed`'s reset — a game wanting
/// unlimited air dashes can reset `dashUsed` itself from its own code.
///
/// Must run after `PlatformerInputSystem` (which sets `dashRequested`/
/// `facingSign` and would otherwise overwrite this tick's dash velocity
/// with normal movement input) and can run anywhere relative to
/// `JumpSystem`/`PlatformerSystem` — it only ever touches `Velocity.x`,
/// which nothing else this tick depends on having settled yet (see
/// `PlatformerSystem`'s doc comment on why `MovementSystem` integrating
/// a velocity set at any point *this* tick is fine).
class DashSystem implements System {
  @override
  String get name => 'dash';

  @override
  void update(World world, double dt) {
    final controllers = world.storeOf<PlatformerController>();
    final velocities = world.storeOf<Velocity>();

    for (var i = 0; i < controllers.length; i++) {
      final entity = controllers.entityAt(i);
      final controller = controllers.denseAt(i);
      final vel = velocities.get(entity);
      if (vel == null || controller.dashSpeed <= 0) {
        controller.dashRequested = false;
        continue;
      }

      if (controller.dashTimeRemaining > 0) {
        controller.dashTimeRemaining -= dt;
        vel.x = controller.dashSpeed * controller.facingSign;
      } else if (controller.dashRequested && !controller.dashUsed) {
        controller.dashTimeRemaining = controller.dashDurationSeconds;
        controller.dashUsed = true;
        vel.x = controller.dashSpeed * controller.facingSign;
      }

      controller.dashRequested = false;
    }
  }
}
