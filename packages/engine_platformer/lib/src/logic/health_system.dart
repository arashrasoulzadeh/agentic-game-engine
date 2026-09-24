import 'package:engine_core/engine_core.dart';

import 'health.dart';

/// Counts down `Health.invincibleSeconds`, `Health.guardBreakTimer`,
/// and regenerates `Health.stability` each tick. Deliberately does
/// nothing else — damage/death/respawn are helpers
/// (`combat_helpers.dart`) a game calls from its own collision
/// listeners, not hidden inside a system, so *when* and *why* an entity
/// takes damage stays visible in game code instead of buried here.
class HealthSystem implements System {
  @override
  String get name => 'health';

  @override
  void update(World world, double dt) {
    final healths = world.storeOf<Health>();
    for (var i = 0; i < healths.length; i++) {
      final health = healths.denseAt(i);

      // Check if guard was broken at the start of this tick (before counting down)
      final wasGuardBroken = health.isGuardBroken;

      // Count down invincibility frames
      if (health.invincibleSeconds > 0) {
        health.invincibleSeconds = (health.invincibleSeconds - dt).clamp(0, double.infinity);
      }

      // Count down guard break stun
      if (health.guardBreakTimer > 0) {
        health.guardBreakTimer = (health.guardBreakTimer - dt).clamp(0, double.infinity);
      }

      // Regenerate stability when not guarding and not guard broken
      // Use wasGuardBroken to prevent regen during the tick guard break ends
      if (!health.isGuarding && !wasGuardBroken && health.stability < health.effectiveMaxStability) {
        health.stability = (health.stability + health.stabilityRegenPerSecond * dt)
            .clamp(0, health.effectiveMaxStability);
      }
    }
  }
}