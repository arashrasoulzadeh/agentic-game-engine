import 'position.dart';
import 'tile_map.dart';

/// One waypoint of a path from `findPath` / `findPlatformerPath` — a
/// tile cell's world-space center.
class PathPoint {
  final double x;
  final double y;

  /// True if reaching this point requires a jump from the previous point.
  final bool jumpRequired;

  /// True if reaching this point requires climbing (ladder).
  final bool climbRequired;

  PathPoint(this.x, this.y, {this.jumpRequired = false, this.climbRequired = false});

  PathPoint copyWith({double? x, double? y, bool? jumpRequired, bool? climbRequired}) {
    return PathPoint(
      x ?? this.x,
      y ?? this.y,
      jumpRequired: jumpRequired ?? this.jumpRequired,
      climbRequired: climbRequired ?? this.climbRequired,
    );
  }
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
/// Uses a binary min-heap (`_MinHeap`, private to this file — a small
/// enough data structure that a `package:collection` dependency wasn't
/// worth adding just for this) as its open set: O(log n) insert/
/// extract-min instead of the O(n log n) sort-then-take-first a plain
/// list previously did every iteration. Doesn't implement decrease-key
/// (a node can be pushed more than once if a cheaper path to it is
/// found later) — the existing `closed` set already discards a stale
/// duplicate the moment it's popped a second time, so this stays
/// correct without the extra bookkeeping a full decrease-key would
/// need.
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
  final open = _MinHeap()..add(_Node(startCol, startRow, _heuristic(startCol, startRow, goalCol, goalRow)));
  final closed = <int>{};
  const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];

  while (open.isNotEmpty) {
    final current = open.removeMin();
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

/// A plain binary min-heap on `_Node.f`, array-backed — the standard
/// shape (parent at `i`, children at `2i+1`/`2i+2`), nothing fancier.
/// No decrease-key: see `findPath`'s doc comment for why that's fine
/// here.
class _MinHeap {
  final List<_Node> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(_Node node) {
    _items.add(node);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_items[i].f >= _items[parent].f) break;
      _swap(i, parent);
      i = parent;
    }
  }

  _Node removeMin() {
    final min = _items[0];
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      final n = _items.length;
      while (true) {
        final left = 2 * i + 1;
        final right = 2 * i + 2;
        var smallest = i;
        if (left < n && _items[left].f < _items[smallest].f) smallest = left;
        if (right < n && _items[right].f < _items[smallest].f) smallest = right;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return min;
  }

void _swap(int a, int b) {
    final tmp = _items[a];
    _items[a] = _items[b];
    _items[b] = tmp;
  }
}