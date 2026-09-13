import 'package:engine_core/engine_core.dart';

import '../components/health.dart';

/// Counts down `Health.invincibleSeconds` each tick. Deliberately does
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
      if (health.invincibleSeconds > 0) {
        health.invincibleSeconds = (health.invincibleSeconds - dt).clamp(0, double.infinity);
      }
    }
  }
}
