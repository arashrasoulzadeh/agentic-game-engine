import 'position.dart';
import 'tile_map.dart';

/// One waypoint of a path from `findPath` — a tile cell's world-space
/// center.
class PathPoint {
  final double x;
  final double y;
  PathPoint(this.x, this.y);
}

/// A* pathfinding over [map]'s grid, 4-directional (no diagonal
/// movement — simplest to reason about for a platformer's mostly-flat
/// tile grids, and avoids "can I actually fit through this diagonal
/// gap" corner-cutting questions). Only `solidTileIds` block — one-way
/// and slope tiles don't (they're walkable surfaces, not walls, same
/// reasoning `raycastTileMap` uses).
///
/// Returns waypoints from the step *after* the start cell through the
/// goal cell (inclusive), as world-space cell centers — empty if
/// [toX]/[toY] is already in the same cell as [fromX]/[fromY], if the
/// goal cell is blocked, or if no path exists at all.
///
/// Uses a plain list (scanned for the lowest-cost node, not a real
/// priority queue) as its open set — correct, and fine at the scale a
/// single AI's pathfind needs (matching this engine's existing
/// `WorldView.nearestWithPosition`, whose own linear scan carries the
/// same "revisit if a real game's profiling shows this mattering"
/// caveat — see `TODO.md`).
List<PathPoint> findPath(
  TileMap map,
  Position origin,
  double fromX,
  double fromY,
  double toX,
  double toY,
) {
  int colOf(double x) => ((x - origin.x) / map.tileWidth).floor();
  int rowOf(double y) => ((y - origin.y) / map.tileHeight).floor();
  bool blocked(int col, int row) {
    if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return true;
    return map.solidTileIds.contains(map.tileAt(col, row));
  }

  final startCol = colOf(fromX);
  final startRow = rowOf(fromY);
  final goalCol = colOf(toX);
  final goalRow = rowOf(toY);
  if ((startCol == goalCol && startRow == goalRow) || blocked(goalCol, goalRow)) {
    return [];
  }

  int key(int col, int row) => row * map.cols + col;
  final startKey = key(startCol, startRow);
  final goalKey = key(goalCol, goalRow);

  final gScore = <int, double>{startKey: 0};
  final cameFrom = <int, int>{};
  final open = <_Node>[_Node(startCol, startRow, _heuristic(startCol, startRow, goalCol, goalRow))];
  final closed = <int>{};
  const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];

  while (open.isNotEmpty) {
    open.sort((a, b) => a.f.compareTo(b.f));
    final current = open.removeAt(0);
    final currentKey = key(current.col, current.row);
    if (currentKey == goalKey) {
      return _reconstructPath(cameFrom, startKey, currentKey, map, origin);
    }
    if (!closed.add(currentKey)) continue;

    for (final (dc, dr) in dirs) {
      final nCol = current.col + dc;
      final nRow = current.row + dr;
      if (blocked(nCol, nRow)) continue;
      final nKey = key(nCol, nRow);
      if (closed.contains(nKey)) continue;

      final tentativeG = gScore[currentKey]! + 1;
      if (tentativeG < (gScore[nKey] ?? double.infinity)) {
        gScore[nKey] = tentativeG;
        cameFrom[nKey] = currentKey;
        open.add(_Node(nCol, nRow, tentativeG + _heuristic(nCol, nRow, goalCol, goalRow)));
      }
    }
  }
  return []; // goal unreachable
}

List<PathPoint> _reconstructPath(
  Map<int, int> cameFrom,
  int startKey,
  int goalKey,
  TileMap map,
  Position origin,
) {
  final path = <PathPoint>[];
  var k = goalKey;
  while (k != startKey) {
    final col = k % map.cols;
    final row = k ~/ map.cols;
    path.add(PathPoint(
      origin.x + col * map.tileWidth + map.tileWidth / 2,
      origin.y + row * map.tileHeight + map.tileHeight / 2,
    ));
    k = cameFrom[k]!;
  }
  return path.reversed.toList();
}

double _heuristic(int c1, int r1, int c2, int r2) =>
    (c1 - c2).abs().toDouble() + (r1 - r2).abs().toDouble(); // Manhattan -- matches 4-directional movement

class _Node {
  final int col;
  final int row;
  final double f;
  _Node(this.col, this.row, this.f);
}
