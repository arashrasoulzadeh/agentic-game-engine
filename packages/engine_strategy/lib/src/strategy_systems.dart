import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Registers everything a turn-based strategy game needs, in the one
/// order that's actually correct -- the call this package exists for,
/// mirroring `installPlatformerSystems`.
///
/// Order, and why it matters:
/// 1. `VisionSystem` (only with [fogGrid]) first, so attack orders this
///    tick are checked against up-to-date visibility.
/// 2. `OrderSystem.withNavigator` -- executes queued orders, spending
///    action points and routing around terrain/units.
/// 3. `AITurnSystem` (only with [aiTeams]) -- after orders, so the
///    "nothing left affordable" check sees this tick's results.
/// 4. `TurnSystem` -- auto-ends [autoEndTeams] once they're out of
///    points, *after* orders have had their chance to spend them.
/// 5. `WinConditionSystem` -- judges eliminations after this tick's
///    kills.
/// 6. `GridToWorldSystem` -- syncs `Position` from the final cells so
///    rendering never lags a tick behind.
/// 7. `SelectionMarkerSystem` last, so markers follow the synced
///    `Position`.
///
/// Also calls `installCombat` (attack orders -> damage). Add your own
/// systems before or after; this doesn't own the whole list.
///
/// Pass `fog: true` to enable fog of war; it spawns a `FogOfWar` sized
/// to [navigator] and adds `VisionSystem`. Spawn your units, *then* call
/// `startTurnBasedGame` -- it refills the first team's action points, so
/// units must already exist.
///
/// Returns the fog entity (null without fog).
EntityId? installStrategySystems(
  World world, {
  required GridNavigator navigator,
  required double cellSize,
  Set<String> autoEndTeams = const {},
  Map<String, TurnAI> aiTeams = const {},
  int attackRange = 1,
  int attackCost = 1,
  int defendBonus = 2,
  bool Function(int col, int row)? blocksSight,
  bool fog = false,
  bool selectionMarkers = true,
}) {
  EntityId? fogEntity;
  if (fog) {
    fogEntity = world.spawn();
    world.storeOf<FogOfWar>().set(fogEntity, FogOfWar(navigator.cols, navigator.rows));
    world.addSystem(VisionSystem(blocksSight: blocksSight ?? (_, _) => false));
  }
  world.addSystem(OrderSystem.withNavigator(
    navigator,
    attackCost: attackCost,
    attackRange: attackRange,
    defendBonus: defendBonus,
  ));
  if (aiTeams.isNotEmpty) world.addSystem(AITurnSystem(aiTeams));
  world.addSystem(TurnSystem(autoEndTeams: autoEndTeams));
  world.addSystem(WinConditionSystem());
  world.addSystem(GridToWorldSystem(cellSize));
  if (selectionMarkers) world.addSystem(SelectionMarkerSystem(cellSize));
  installCombat(world);
  return fogEntity;
}
