import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';

import 'active_play.dart';
import 'components.dart';
import 'golden_events.dart';
import 'progression.dart';

/// Registers the idle-genre components on [world] so they take part in `World.toJson()`,
/// `applyPatch()` and level loading like any other component. Call it after
/// `registerCoreComponents`. Safe to call more than once.
///
/// Every component here has a schema (`engine_schema`'s `idle_schemas.dart`); an unregistered
/// component silently cannot be serialized, so a new one must be added in both places.
void registerIdleComponents(World world) {
  if (world.components.isRegistered('generator')) return;
  world.components.register<Generator>(
    'generator',
    (g) => g.toJson(),
    Generator.fromJson,
    schema: generatorSchema,
  );
  world.components.register<Upgrade>(
    'upgrade',
    (u) => u.toJson(),
    Upgrade.fromJson,
    schema: upgradeSchema,
  );
  world.components.register<IdleModifiers>(
    'idleModifiers',
    (m) => m.toJson(),
    IdleModifiers.fromJson,
    schema: idleModifiersSchema,
  );
  world.components.register<IdleStats>(
    'idleStats',
    (s) => s.toJson(),
    IdleStats.fromJson,
    schema: idleStatsSchema,
  );
  world.components.register<PrestigeRule>(
    'prestigeRule',
    (r) => r.toJson(),
    PrestigeRule.fromJson,
    schema: prestigeRuleSchema,
  );
  world.components.register<Achievement>(
    'achievement',
    (a) => a.toJson(),
    Achievement.fromJson,
    schema: achievementSchema,
  );
  world.components.register<Boost>(
    'boost',
    (b) => b.toJson(),
    Boost.fromJson,
    schema: boostSchema,
  );
  world.components.register<GoldenEvents>(
    'goldenEvents',
    (g) => g.toJson(),
    GoldenEvents.fromJson,
    schema: goldenEventsSchema,
  );
}
