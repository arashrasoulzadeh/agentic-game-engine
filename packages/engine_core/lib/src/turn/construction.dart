import 'dart:math' as math;

import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'economy.dart';
import 'formation.dart';
import 'grid_navigation.dart';
import 'order.dart';
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
/// [buildSeconds] > 0 it starts as a [Construction] that [ConstructionSystem] counts down; with
/// [needsBuilder] it only counts down while an assigned [BuildWorker] stands next to it.
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
  bool needsBuilder = false,
}) {
  if (!navigator.inBounds(col, row))
    return (id: null, failure: BuildFailure.outOfBounds);
  if (navigator.terrainCost(col, row) == null)
    return (id: null, failure: BuildFailure.blocked);
  if (cellsHeldExcept(world, const [])(col, row))
    return (id: null, failure: BuildFailure.occupied);
  final treasury = treasuryOf(world, team);
  if (treasury == null) return (id: null, failure: BuildFailure.noTreasury);
  if (!treasury.spend(cost))
    return (id: null, failure: BuildFailure.cantAfford);
  final id = world.spawn();
  world.components.applyToEntity(id, {
    ...template,
    'team': {'id': team},
    'gridPosition': {'col': col, 'row': row},
    if (buildSeconds > 0)
      'construction': {
        'remaining': buildSeconds,
        if (needsBuilder) 'needsBuilder': true,
      },
  });
  return (id: id, failure: null);
}

/// A unit that can put buildings up. Give it to a unit with `RealtimeStats` and an `OrderQueue`, and
/// send it with [assignBuild].
class BuildWorker {
  /// The building it is working on, or null when idle.
  EntityId? site;

  BuildWorker({this.site});

  Map<String, dynamic> toJson() => {'site': site};
  factory BuildWorker.fromJson(Map<String, dynamic> json) =>
      BuildWorker(site: (json['site'] as num?)?.toInt());
}

/// Sends [unit] to work on [site]. False (nothing changes) when the unit is not a [BuildWorker], the
/// site is not under construction, or they are on different teams.
bool assignBuild(World world, EntityId unit, EntityId site) {
  final b = world.storeOf<BuildWorker>().get(unit);
  if (b == null || !world.storeOf<Construction>().has(site)) return false;
  final teams = world.storeOf<Team>();
  if (teams.get(unit)?.id != teams.get(site)?.id) return false;
  b.site = site;
  world.storeOf<OrderQueue>().get(unit)?.orders.clear();
  return true;
}

/// Walks assigned [BuildWorker]s up to their building, and frees them when it is finished or gone.
/// Run it before `RealtimeOrderSystem` (like `GatherSystem`) so the move starts the same step.
class BuildSystem extends System {
  BuildSystem(this.navigator);

  final GridNavigator navigator;

  @override
  String get name => 'build';

  @override
  void update(World world, double dt) {
    final builders = world.storeOf<BuildWorker>();
    final ids = [for (var i = 0; i < builders.length; i++) builders.entityAt(i)]
      ..sort();
    for (final id in ids) {
      final b = builders.get(id);
      final site = b?.site;
      if (b == null || site == null) continue;
      if (!world.entities.isAlive(site) ||
          !world.storeOf<Construction>().has(site)) {
        b.site = null;
        continue;
      }
      final here = world.storeOf<GridPosition>().get(id);
      final there = world.storeOf<GridPosition>().get(site);
      if (here == null || there == null || here.chebyshev(there) <= 1) continue;
      queueMoveNextTo(world, navigator, id, there);
    }
  }
}

/// Counts down every [Construction] and removes it when done. Deterministic (by entity id).
/// Run it before `ProductionSystem` so a finished building works the same step.
class ConstructionSystem extends System {
  @override
  String get name => 'construction';

  @override
  void update(World world, double dt) {
    final store = world.storeOf<Construction>();
    final ids = [for (var i = 0; i < store.length; i++) store.entityAt(i)]
      ..sort();
    for (final id in ids) {
      final c = store.get(id);
      if (c == null) continue;
      // With needsBuilder the clock runs once per assigned builder standing next to the site.
      final workers = c.needsBuilder ? _buildersAt(world, id) : 1;
      c.remaining = math.max(0, c.remaining - dt * workers);
      if (c.remaining <= 1e-9) {
        store.remove(id);
        world.events.emit(BuildingCompletedEvent(id));
      }
    }
  }

  int _buildersAt(World world, EntityId site) {
    final builders = world.storeOf<BuildWorker>();
    final grid = world.storeOf<GridPosition>();
    final at = grid.get(site);
    if (at == null) return 0;
    var n = 0;
    for (var i = 0; i < builders.length; i++) {
      if (builders.denseAt(i).site != site) continue;
      final p = grid.get(builders.entityAt(i));
      if (p != null && p.chebyshev(at) <= 1) n++;
    }
    return n;
  }
}
