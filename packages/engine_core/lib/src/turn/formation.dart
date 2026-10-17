import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'grid_navigation.dart';
import 'order.dart';

/// Distinct destination cells for [count] units heading to [center]: the nearest
/// free, walkable cells, spiralling outward, so a group sent to one place spreads
/// into a blob around it instead of every unit pathing to the same cell and
/// jamming.
///
/// A cell is excluded if it is impassable, off the grid, in [taken] (cells already
/// occupied by units that aren't moving), or unreachable from [center] on the
/// navigator. Fewer than [count] cells come back only if the map really has no
/// room. Deterministic: nearest first, ties broken row-major.
List<GridPosition> formationCells(
  GridNavigator navigator,
  GridPosition center,
  int count, {
  bool Function(int col, int row)? taken,
}) {
  if (count <= 0) return const [];
  final isTaken = taken ?? (_, _) => false;
  final result = <GridPosition>[];
  final maxRadius = navigator.cols > navigator.rows ? navigator.cols : navigator.rows;
  for (var radius = 0; radius <= maxRadius && result.length < count; radius++) {
    final ring = <GridPosition>[];
    for (var dr = -radius; dr <= radius; dr++) {
      for (var dc = -radius; dc <= radius; dc++) {
        // Only the ring at exactly this Chebyshev distance.
        if ((dc.abs() > dr.abs() ? dc.abs() : dr.abs()) != radius) continue;
        final c = center.col + dc, r = center.row + dr;
        if (!navigator.inBounds(c, r) || navigator.terrainCost(c, r) == null || isTaken(c, r)) continue;
        ring.add(GridPosition(c, r));
      }
    }
    ring.sort((a, b) {
      final da = (a.col - center.col) * (a.col - center.col) + (a.row - center.row) * (a.row - center.row);
      final db = (b.col - center.col) * (b.col - center.col) + (b.row - center.row) * (b.row - center.row);
      return da != db ? da.compareTo(db) : (a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
    });
    for (final cell in ring) {
      if (result.length == count) break;
      if (radius == 0 || navigator.findPath(center, cell) != null) result.add(cell);
    }
  }
  return result;
}

/// Matches [units] to [cells] so the total walking distance is small: each cell in
/// turn goes to the nearest still-unassigned unit. Greedy, not optimal, but cheap
/// and it keeps units from crossing paths in the common case. Deterministic: ties
/// go to the lower entity id.
Map<EntityId, GridPosition> assignFormation(World world, List<EntityId> units, List<GridPosition> cells) {
  final grid = world.storeOf<GridPosition>();
  final remaining = [...units]..sort();
  final out = <EntityId, GridPosition>{};
  for (final cell in cells) {
    if (remaining.isEmpty) break;
    EntityId? best;
    var bestD = 1 << 30;
    for (final u in remaining) {
      final p = grid.get(u);
      if (p == null) continue;
      final d = p.chebyshev(cell);
      if (d < bestD) {
        bestD = d;
        best = u;
      }
    }
    if (best == null) break;
    out[best] = cell;
    remaining.remove(best);
  }
  return out;
}

/// Cells currently held by units other than [movers] - the "taken" set for
/// [formationCells] when ordering a group.
bool Function(int col, int row) cellsHeldExcept(World world, Iterable<EntityId> movers) {
  final moving = movers.toSet();
  final grid = world.storeOf<GridPosition>();
  return (c, r) {
    for (var i = 0; i < grid.length; i++) {
      final g = grid.denseAt(i);
      if (g.col == c && g.row == r && !moving.contains(grid.entityAt(i))) return true;
    }
    return false;
  };
}
