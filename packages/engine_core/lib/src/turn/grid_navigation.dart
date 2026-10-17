import '../physics/tile_map.dart';
import 'order.dart';

/// Rules for moving on a grid: bounds, per-cell terrain cost, and
/// optional diagonals. Separate from `findPath` (physics/pathfinding.dart),
/// which is a 4-directional, jump-aware platformer router -- strategy
/// movement needs weighted terrain and 8-way steps instead.
class GridNavigator {
  final int cols;
  final int rows;

  /// Cost to enter a cell, or null when it is impassable.
  final int? Function(int col, int row) terrainCost;

  /// Allow diagonal steps (cost = the destination cell's cost). A
  /// diagonal is refused when either orthogonal neighbour is impassable
  /// terrain, so units can't cut through wall corners.
  final bool diagonals;

  const GridNavigator({
    required this.cols,
    required this.rows,
    required this.terrainCost,
    this.diagonals = true,
  });

  /// Builds a navigator from a [TileMap]: `solidTileIds` are impassable,
  /// other tiles cost [terrainCosts] (default 1) -- e.g. `{5: 3}` makes
  /// tile 5 (forest) cost 3.
  factory GridNavigator.fromTileMap(
    TileMap map, {
    Map<int, int> terrainCosts = const {},
    bool diagonals = true,
  }) {
    return GridNavigator(
      cols: map.cols,
      rows: map.rows,
      diagonals: diagonals,
      terrainCost: (c, r) {
        final id = map.tiles[r * map.cols + c];
        if (map.solidTileIds.contains(id)) return null;
        return terrainCosts[id] ?? 1;
      },
    );
  }

  bool inBounds(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;

  int? _cost(int c, int r, bool Function(int, int) blocked) {
    if (!inBounds(c, r) || blocked(c, r)) return null;
    return terrainCost(c, r);
  }

  Iterable<(int, int, int)> _neighbours(
    int c,
    int r,
    bool Function(int, int) blocked,
  ) sync* {
    for (var dc = -1; dc <= 1; dc++) {
      for (var dr = -1; dr <= 1; dr++) {
        if (dc == 0 && dr == 0) continue;
        final diagonal = dc != 0 && dr != 0;
        if (diagonal) {
          if (!diagonals) continue;
          // Terrain only: a unit standing beside the corner doesn't
          // stop you slipping past it, a wall does.
          if (!inBounds(c + dc, r) || terrainCost(c + dc, r) == null) continue;
          if (!inBounds(c, r + dr) || terrainCost(c, r + dr) == null) continue;
        }
        final cost = _cost(c + dc, r + dr, blocked);
        if (cost != null) yield (c + dc, r + dr, cost);
      }
    }
  }

  /// Cheapest path from [from] to [to], excluding [from] and including
  /// [to]; null if unreachable, empty if already there. [blocked] marks
  /// cells occupied by other units.
  List<GridPosition>? findPath(
    GridPosition from,
    GridPosition to, {
    bool Function(int col, int row)? blocked,
  }) {
    final isBlocked = blocked ?? (_, __) => false;
    if (from.col == to.col && from.row == to.row) return [];
    if (_cost(to.col, to.row, isBlocked) == null) return null;

    int key(int c, int r) => r * cols + c;
    int h(int c, int r) {
      final dx = (c - to.col).abs();
      final dy = (r - to.row).abs();
      return diagonals ? (dx > dy ? dx : dy) : dx + dy;
    }

    final best = <int, int>{key(from.col, from.row): 0};
    final parent = <int, int>{};
    final open = <(int, int, int, int)>[(h(from.col, from.row), 0, from.col, from.row)];
    while (open.isNotEmpty) {
      var bi = 0;
      for (var i = 1; i < open.length; i++) {
        if (open[i].$1 < open[bi].$1) bi = i;
      }
      final (_, g, c, r) = open.removeAt(bi);
      if (g > (best[key(c, r)] ?? 1 << 30)) continue;
      if (c == to.col && r == to.row) {
        final path = <GridPosition>[];
        var k = key(c, r);
        while (k != key(from.col, from.row)) {
          path.add(GridPosition(k % cols, k ~/ cols));
          k = parent[k]!;
        }
        return path.reversed.toList();
      }
      for (final (nc, nr, cost) in _neighbours(c, r, isBlocked)) {
        final ng = g + cost;
        final nk = key(nc, nr);
        if (ng < (best[nk] ?? 1 << 30)) {
          best[nk] = ng;
          parent[nk] = key(c, r);
          open.add((ng + h(nc, nr), ng, nc, nr));
        }
      }
    }
    return null;
  }

  /// Every cell reachable from [from] spending at most [budget], mapped
  /// to its cheapest cost -- the data behind a "where can I move"
  /// overlay. Excludes [from] itself.
  Map<(int, int), int> reachable(
    GridPosition from,
    int budget, {
    bool Function(int col, int row)? blocked,
  }) {
    final isBlocked = blocked ?? (_, __) => false;
    final dist = <(int, int), int>{(from.col, from.row): 0};
    final queue = <(int, int)>[(from.col, from.row)];
    while (queue.isNotEmpty) {
      var bi = 0;
      for (var i = 1; i < queue.length; i++) {
        if (dist[queue[i]]! < dist[queue[bi]]!) bi = i;
      }
      final (c, r) = queue.removeAt(bi);
      final d = dist[(c, r)]!;
      for (final (nc, nr, cost) in _neighbours(c, r, isBlocked)) {
        final nd = d + cost;
        if (nd > budget) continue;
        if (nd < (dist[(nc, nr)] ?? 1 << 30)) {
          dist[(nc, nr)] = nd;
          queue.add((nc, nr));
        }
      }
    }
    dist.remove((from.col, from.row));
    return dist;
  }
}
