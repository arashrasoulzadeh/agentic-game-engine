import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'fog_shade.dart';
import 'move_range_highlight.dart';
import 'smooth_motion.dart';

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
/// 7. `SelectionMarkerSystem`, so markers follow the synced `Position`.
/// 8. `FogShadeSystem` (only with [fogShade], which needs `fog: true`), after
///    `VisionSystem` has updated what the team sees.
/// 9. `MoveRangeHighlightSystem` (only with [moveHighlight]) last: it reads the
///    final selection, cells and points.
///
/// Also calls `installCombat` (attack orders -> damage). Add your own
/// systems before or after; this doesn't own the whole list.
///
/// Pass `moveHighlight: (atlasId: 'terrain', region: 'highlight')` to light up
/// the selected unit's reachable cells with that sprite.
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
  ({String atlasId, String region})? moveHighlight,
  ({
    String team,
    String atlasId,
    String unknownRegion,
    String exploredRegion,
    String clearRegion,
  })? fogShade,
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
  if (fogShade != null) {
    if (!fog) throw ArgumentError('fogShade needs fog: true');
    _registerOnce<FogShadeCell>(world, 'fogShadeCell', (c) => c.toJson(), FogShadeCell.fromJson);
    _registerOnce<FogHidden>(world, 'fogHidden', (h) => h.toJson(), FogHidden.fromJson);
    world.addSystem(FogShadeSystem(
      team: fogShade.team,
      cellSize: cellSize,
      atlasId: fogShade.atlasId,
      unknownRegion: fogShade.unknownRegion,
      exploredRegion: fogShade.exploredRegion,
      clearRegion: fogShade.clearRegion,
    ));
  }
  if (moveHighlight != null) {
    _registerOnce<MoveRangeMarker>(world, 'moveRangeMarker', (m) => m.toJson(), MoveRangeMarker.fromJson);
    world.addSystem(MoveRangeHighlightSystem(
      navigator: navigator,
      cellSize: cellSize,
      atlasId: moveHighlight.atlasId,
      region: moveHighlight.region,
    ));
  }
  installCombat(world);
  return fogEntity;
}

/// Registers one of this package's own component types, unless it already is. These
/// are not in `registerFlutterComponents` (they belong to this package), so the
/// install call that needs them registers them; calling it twice is harmless.
void _registerOnce<T>(
  World world,
  String name,
  Map<String, dynamic> Function(T) toJson,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (world.components.all.any((r) => r.name == name)) return;
  world.components.register<T>(name, toJson, fromJson);
}

/// What [installRealtimeStrategySystems] created, for the game to hold on to.
class RealtimeInstall {
  RealtimeInstall({required this.fields, required this.matchRule, this.fog});

  /// Shared flow fields. Call `fields.invalidate()` when terrain changes.
  final FlowFieldCache fields;

  /// Decides the winner; read `matchRule.winner`.
  final LastTeamStandingSystem matchRule;

  /// The `FogOfWar` entity, when fog was enabled.
  final EntityId? fog;
}

/// The real-time counterpart of [installStrategySystems]: no turn clock or action
/// points - units act continuously on their `RealtimeStats` speed and cooldowns.
///
/// Order, and why: `VisionSystem` (with fog) first so visibility is current;
/// `ProductionSystem` (with `production: true`: team `Treasury` income and
/// `Producer` buildings, preceded by `ConstructionSystem` so a building finished this tick
/// already works) so a finished unit exists before the AI looks; `GatherSystem` (with
/// `gathering: true`) and `BuildSystem` (`building: true`) so a worker's next move is queued
/// before orders run;
/// `RealtimeAISystem` (with `aiTeams`) so its orders start this tick;
/// `RealtimeOrderSystem` (movement and combat, sharing one `FlowField` per
/// destination); `LastTeamStandingSystem` after this tick's kills;
/// `SmoothGridToWorldSystem` (or the snapping `GridToWorldSystem` with
/// `smoothMotion: false`) so units glide between cells; then the optional selection
/// markers and fog shade. Combat
/// is applied directly by the order system, so there is no `installCombat` here.
///
/// **Run it on a fixed timestep** (`GameConfig.fixedTimestepSeconds`, e.g.
/// `1 / 20`): the systems are deterministic for identical `dt`, which is what
/// replays, rollback and lockstep multiplayer depend on, and frame-time `dt`
/// would break that. Spawn units with `spawnStrategyUnit(realtime: ...)`, issue
/// orders with `GridTapController(cell, localTeam: ...)` or `submitOrder`.
RealtimeInstall installRealtimeStrategySystems(
  World world, {
  required GridNavigator navigator,
  required double cellSize,
  int attackRange = 1,
  bool autoEngage = true,
  Map<String, TurnAI> aiTeams = const {},
  double aiInterval = 1.0,
  bool production = false,
  bool gathering = false,
  bool building = false,
  bool smoothMotion = true,
  bool fog = false,
  bool Function(int col, int row)? blocksSight,
  bool selectionMarkers = true,
  ({
    String team,
    String atlasId,
    String unknownRegion,
    String exploredRegion,
    String clearRegion,
  })? fogShade,
}) {
  EntityId? fogEntity;
  if (fog) {
    fogEntity = world.spawn();
    world.storeOf<FogOfWar>().set(fogEntity, FogOfWar(navigator.cols, navigator.rows));
    world.addSystem(VisionSystem(blocksSight: blocksSight ?? (_, _) => false));
  }
  final fields = FlowFieldCache(navigator);
  // Income and production first: a unit finished this tick can be ordered by the AI
  // (below) in the same tick.
  // Construction before production, so a building finished this tick can start work.
  if (production || gathering || building) world.addSystem(ConstructionSystem());
  if (production) world.addSystem(ProductionSystem(navigator));
  // Gatherers queue their moves before the order system runs, so they start this tick.
  if (gathering) world.addSystem(GatherSystem(navigator));
  // Builders walk up to their site the same way.
  if (building) world.addSystem(BuildSystem(navigator));
  // The AI decides first, so its new orders start executing this very tick.
  if (aiTeams.isNotEmpty) world.addSystem(RealtimeAISystem(aiTeams, interval: aiInterval));
  world.addSystem(RealtimeOrderSystem(fields: fields, attackRange: attackRange, autoEngage: autoEngage));
  final matchRule = LastTeamStandingSystem();
  world.addSystem(matchRule);
  world.addSystem(smoothMotion ? SmoothGridToWorldSystem(cellSize) : GridToWorldSystem(cellSize));
  if (selectionMarkers) world.addSystem(SelectionMarkerSystem(cellSize));
  if (fogShade != null) {
    if (!fog) throw ArgumentError('fogShade needs fog: true');
    _registerOnce<FogShadeCell>(world, 'fogShadeCell', (c) => c.toJson(), FogShadeCell.fromJson);
    _registerOnce<FogHidden>(world, 'fogHidden', (h) => h.toJson(), FogHidden.fromJson);
    world.addSystem(FogShadeSystem(
      team: fogShade.team,
      cellSize: cellSize,
      atlasId: fogShade.atlasId,
      unknownRegion: fogShade.unknownRegion,
      exploredRegion: fogShade.exploredRegion,
      clearRegion: fogShade.clearRegion,
    ));
  }
  return RealtimeInstall(fields: fields, matchRule: matchRule, fog: fogEntity);
}
