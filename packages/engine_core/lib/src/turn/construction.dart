import 'dart:math' as math;

import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'economy.dart';
import 'formation.dart';
import 'grid_navigation.dart';
import 'turn_components.dart';

/// A building finished construction.
class BuildingCompletedEvent {
  final EntityId building;
  BuildingCompletedEvent(this.building);
}

/// Why [placeBuilding] refused.
enum BuildFailure { outOfBounds, blocked, occupied, noTreasury, cantAfford }

/// Puts a building for [team] on cell ([col], [row]): checks the cell is on the map, passable
/// and empty, takes [cost] from the team's [Treasury], and spawns [template] there. With
/// [buildSeconds] > 0 it starts as a [Construction] that [ConstructionSystem] counts down.
///
/// All-or-nothing: on any failure nothing is spent and no entity is created.
({EntityId? id, BuildFailure? failure}) placeBuilding(
  World world,
  GridNavigator navigator, {
  required String team,
  required Map<String, dynamic> template,
  required int col,
  required int row,
  Map<String, int> cost = const {},
  double buildSeconds = 0,
}) {
  if (!navigator.inBounds(col, row)) return (id: null, failure: BuildFailure.outOfBounds);
  if (navigator.terrainCost(col, row) == null) return (id: null, failure: BuildFailure.blocked);
  if (cellsHeldExcept(world, const [])(col, row)) return (id: null, failure: BuildFailure.occupied);
  final treasury = treasuryOf(world, team);
  if (treasury == null) return (id: null, failure: BuildFailure.noTreasury);
  if (!treasury.spend(cost)) return (id: null, failure: BuildFailure.cantAfford);
  final id = world.spawn();
  world.components.applyToEntity(id, {
    ...template,
    'team': {'id': team},
    'gridPosition': {'col': col, 'row': row},
    if (buildSeconds > 0) 'construction': {'remaining': buildSeconds},
  });
  return (id: id, failure: null);
}

/// Counts down every [Construction] and removes it when done. Deterministic (by entity id).
/// Run it before `ProductionSystem` so a finished building works the same step.
class ConstructionSystem extends System {
  @override
  String get name => 'construction';

  @override
  void update(World world, double dt) {
    final store = world.storeOf<Construction>();
    final ids = [for (var i = 0; i < store.length; i++) store.entityAt(i)]..sort();
    for (final id in ids) {
      final c = store.get(id);
      if (c == null) continue;
      c.remaining = math.max(0, c.remaining - dt);
      if (c.remaining <= 1e-9) {
        store.remove(id);
        world.events.emit(BuildingCompletedEvent(id));
      }
    }
  }
}
