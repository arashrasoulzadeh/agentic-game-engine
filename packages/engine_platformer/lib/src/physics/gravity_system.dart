import 'package:engine_core/engine_core.dart';

import 'gravity.dart';
import 'platformer_controller.dart';

/// Accelerates `Velocity.y` downward for every entity with a `Gravity`
/// component. Skips entities `PlatformerSystem` has already marked
/// grounded this tick — otherwise gravity re-accumulates into the floor
/// every frame and fights the ground snap.
///
/// Applies `Gravity.fallMultiplier` on top of `Gravity.scale` only while
/// already falling (`Velocity.y > 0`) — checked *before* this tick's own
/// acceleration is added, so the exact tick a rising entity's velocity
/// crosses zero still accelerates at the plain (rising) rate for that
/// tick, then switches to the heavier falling rate the next one once
/// `vel.y` has actually gone positive. That one-tick boundary is
/// negligible (`dt` is a fraction of a frame) and avoids the more
/// complex "did it cross zero mid-tick" case entirely.
class GravitySystem implements System {
  final double gravity;

  GravitySystem({this.gravity = 980});

  @override
  String get name => 'gravity';

  @override
  void update(World world, double dt) {
    final gravities = world.storeOf<Gravity>();
    final velocities = world.storeOf<Velocity>();
    final controllers = world.storeOf<PlatformerController>();

    for (var i = 0; i < gravities.length; i++) {
      final entity = gravities.entityAt(i);
      final vel = velocities.get(entity);
      if (vel == null) continue;

      final controller = controllers.get(entity);
      if (controller != null && controller.grounded) continue;

      final g = gravities.denseAt(i);
      final multiplier = vel.y > 0 ? g.fallMultiplier : 1.0;
      vel.y += gravity * g.scale * multiplier * dt;
    }
  }
}
