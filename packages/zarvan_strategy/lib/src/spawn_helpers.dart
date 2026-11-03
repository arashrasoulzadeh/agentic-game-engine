import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';

/// Spawns a grid unit with the components the strategy systems expect:
/// `Team`, `GridPosition`, `Position` (centered in its cell, kept in
/// sync afterwards by `GridToWorldSystem`), `ActionPoints`, `UnitStats`,
/// and optionally `Vision`, an `AttackProfile` (pass [attackRange] and/or
/// [attackCost] for ranged or expensive attacks) and a `Sprite`.
///
/// Pass [realtime] (`RealtimeStats(speed: 3, attackInterval: 0.8)`) for a
/// real-time game: the unit gets those instead of `ActionPoints`.
///
/// Action points start at 0 -- `startTurnBasedGame`/`endTurn` refill
/// them when the unit's team's turn begins -- so a unit spawned
/// mid-game can't act on the turn it appears.
EntityId spawnStrategyUnit(
  World world, {
  required String team,
  required int col,
  required int row,
  required double cellSize,
  int maxHp = 10,
  int attack = 3,
  int defense = 0,
  int actionPoints = 3,
  int? visionRange,
  int? attackRange,
  int? attackCost,
  RealtimeStats? realtime,
  String? atlasId,
  String? spriteRegion,
}) {
  final id = world.spawn();
  world.componentsOf<Team>().set(id, Team(team));
  world.componentsOf<GridPosition>().set(id, GridPosition(col, row));
  world.componentsOf<Position>().set(id, Position((col + 0.5) * cellSize, (row + 0.5) * cellSize));
  if (realtime != null) {
    // Real-time units act on speed and cooldowns, not action points.
    world.componentsOf<RealtimeStats>().set(id, realtime);
  } else {
    world.componentsOf<ActionPoints>().set(id, ActionPoints(actionPoints, current: 0));
  }
  world.componentsOf<UnitStats>().set(id, UnitStats(maxHp: maxHp, attack: attack, defense: defense));
  if (attackRange != null || attackCost != null) {
    world.componentsOf<AttackProfile>().set(id, AttackProfile(range: attackRange ?? 1, cost: attackCost ?? 1));
  }
  if (visionRange != null) world.componentsOf<Vision>().set(id, Vision(visionRange));
  if (atlasId != null && spriteRegion != null) {
    world.componentsOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
  return id;
}
