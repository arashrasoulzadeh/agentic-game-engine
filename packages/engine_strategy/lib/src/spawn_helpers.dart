import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Spawns a grid unit with the components the strategy systems expect:
/// `Team`, `GridPosition`, `Position` (centered in its cell, kept in
/// sync afterwards by `GridToWorldSystem`), `ActionPoints`, `UnitStats`,
/// and optionally `Vision` and a `Sprite`.
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
  String? atlasId,
  String? spriteRegion,
}) {
  final id = world.spawn();
  world.storeOf<Team>().set(id, Team(team));
  world.storeOf<GridPosition>().set(id, GridPosition(col, row));
  world.storeOf<Position>().set(id, Position((col + 0.5) * cellSize, (row + 0.5) * cellSize));
  world.storeOf<ActionPoints>().set(id, ActionPoints(actionPoints, current: 0));
  world.storeOf<UnitStats>().set(id, UnitStats(maxHp: maxHp, attack: attack, defense: defense));
  if (visionRange != null) world.storeOf<Vision>().set(id, Vision(visionRange));
  if (atlasId != null && spriteRegion != null) {
    world.storeOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
  return id;
}
