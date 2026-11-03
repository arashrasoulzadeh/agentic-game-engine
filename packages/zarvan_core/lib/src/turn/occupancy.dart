import '../ecs/component_store.dart';
import '../ecs/entity.dart';
import 'footprint.dart';
import 'grid_navigation.dart';
import 'order.dart';

/// A "is this cell taken?" test for [self]'s pathing: true if any *other* entity
/// stands on the cell. [ignore] is also treated as absent -- an attacker
/// approaching a target must be able to plan a route onto the target's own cell,
/// stopping short of it.
///
/// With [footprints], units larger than one cell count: another unit blocks every cell it covers, and a
/// cell is blocked for [self] when its own footprint, placed there, would overlap another unit. With
/// [navigator] too, a big [self] also needs every covered cell to be passable terrain inside the grid.
///
/// Shared by the turn-based and real-time order systems so both agree on what
/// blocks a step.
bool Function(int col, int row) occupiedBy(
  ComponentStore<GridPosition> grid,
  EntityId self, {
  EntityId? ignore,
  ComponentStore<GridFootprint>? footprints,
  GridNavigator? navigator,
}) {
  final mine = footprints?.get(self)?.size ?? 1;
  return (c, r) {
    if (navigator != null && mine > 1) {
      for (var dc = 0; dc < mine; dc++) {
        for (var dr = 0; dr < mine; dr++) {
          if (!navigator.inBounds(c + dc, r + dr) ||
              navigator.terrainCost(c + dc, r + dr) == null) {
            return true;
          }
        }
      }
    }
    final at = GridPosition(c, r);
    for (var i = 0; i < grid.length; i++) {
      final e = grid.entityAt(i);
      if (e == self || e == ignore) continue;
      final o = grid.denseAt(i);
      final theirs = footprints?.get(e)?.size ?? 1;
      if (mine == 1 && theirs == 1) {
        if (o.col == c && o.row == r) return true;
      } else if (footprintsOverlap(at, mine, o, theirs)) {
        return true;
      }
    }
    return false;
  };
}
