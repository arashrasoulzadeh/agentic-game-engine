import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import '../components/health.dart';
import '../components/health_hud_link.dart';

/// Copies `Health.current`/`.max` into every `HudBar` carrying a
/// [HealthHudLink] pointing at that health, each tick — the mechanical
/// half of "put a health bar on screen": a game still spawns the
/// `HudBar` entity itself (screen position, size, colors are its call),
/// this just keeps its `value`/`maxValue` in sync so nothing else has
/// to. A link whose source entity has no `Health` (destroyed, or never
/// had one) is silently skipped rather than erroring, since a HUD bar
/// outliving its source by a tick or two (e.g. the frame an enemy dies)
/// is normal, not a bug.
class HealthHudSystem implements System {
  @override
  String get name => 'healthHud';

  @override
  void update(World world, double dt) {
    final links = world.storeOf<HealthHudLink>();
    final bars = world.storeOf<HudBar>();
    final healths = world.storeOf<Health>();
    for (var i = 0; i < links.length; i++) {
      final entity = links.entityAt(i);
      final bar = bars.get(entity);
      if (bar == null) continue;
      final health = healths.get(links.denseAt(i).source);
      if (health == null) continue;
      bar.value = health.current;
      bar.maxValue = health.max;
    }
  }
}
