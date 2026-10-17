import '../ecs/component_store.dart';
import '../ecs/entity.dart';
import 'order.dart';

/// A "is this cell taken?" test for [self]'s pathing: true if any *other* entity
/// stands on the cell. [ignore] is also treated as absent -- an attacker
/// approaching a target must be able to plan a route onto the target's own cell,
/// stopping short of it.
///
/// Shared by the turn-based and real-time order systems so both agree on what
/// blocks a step.
bool Function(int col, int row) occupiedBy(
  ComponentStore<GridPosition> grid,
  EntityId self, {
  EntityId? ignore,
}) {
  return (c, r) {
    for (var i = 0; i < grid.length; i++) {
      final o = grid.denseAt(i);
      final e = grid.entityAt(i);
      if (e != self && e != ignore && o.col == c && o.row == r) return true;
    }
    return false;
  };
}
