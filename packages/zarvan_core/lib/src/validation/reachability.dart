import 'dart:collection';

import '../physics/tile_map.dart';

/// Whether a walker starting on the tile at ([startX], [startY]) can reach the
/// tile at ([targetX], [targetY]) by walking, falling, and jumping.
///
/// This is a conservative heuristic, not a physics simulation. It models:
/// - walking sideways on ground, and walking off ledges (which falls);
/// - a jump that rises up to [maxJumpTiles] cells, moves sideways at the apex
///   through empty cells only (no jumping through walls), and then falls;
/// - no movement sideways while airborne except along a jump's apex.
///
/// A level that passes is reachable under these rules. A level that fails may
/// still be playable with mechanics this does not model, such as wall jumps,
/// ladders, or double jumps, so the validator reports it as a warning.
///
/// Coordinates are world units, with the tile map's origin already subtracted.
bool isTileReachable(
  TileMap map, {
  required double startX,
  required double startY,
  required double targetX,
  required double targetY,
  int maxJumpTiles = 3,
}) {
  final start = _cellOf(map, startX, startY);
  final target = _cellOf(map, targetX, targetY);
  if (!_inBounds(map, start) || !_inBounds(map, target)) return false;
  if (!_passable(map, start) || !_passable(map, target)) return false;

  final seen = <_Cell>{};
  final queue = Queue<_Cell>();

  /// Enters [cell] as a walker would: a walker that is not standing on ground
  /// falls until it is. Returns true when that fall passes through [target].
  bool enter(_Cell cell) {
    var at = cell;
    while (true) {
      if (at == target) return true;
      if (!_inBounds(map, at) || !_passable(map, at)) return false;
      if (_grounded(map, at)) {
        if (seen.add(at)) queue.add(at);
        return false;
      }
      at = _Cell(at.col, at.row + 1);
    }
  }

  if (enter(start)) return true;

  while (queue.isNotEmpty) {
    final cell = queue.removeFirst();
    if (cell == target) return true;

    for (final next in [
      _Cell(cell.col - 1, cell.row),
      _Cell(cell.col + 1, cell.row),
    ]) {
      if (enter(next)) return true;
    }

    for (var up = 1; up <= maxJumpTiles; up++) {
      final head = _Cell(cell.col, cell.row - up);
      if (!_inBounds(map, head) || !_passable(map, head)) break;
      for (final dir in const [-1, 1]) {
        for (var step = 1; step <= maxJumpTiles; step++) {
          final apex = _Cell(cell.col + dir * step, cell.row - up);
          if (!_inBounds(map, apex) || !_passable(map, apex)) break;
          if (enter(apex)) return true;
        }
      }
    }
  }
  return false;
}

class _Cell {
  final int col;
  final int row;
  const _Cell(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      other is _Cell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);
}

_Cell _cellOf(TileMap map, double x, double y) =>
    _Cell((x / map.tileWidth).floor(), (y / map.tileHeight).floor());

bool _inBounds(TileMap map, _Cell cell) =>
    cell.col >= 0 &&
    cell.col < map.cols &&
    cell.row >= 0 &&
    cell.row < map.rows;

bool _passable(TileMap map, _Cell cell) => !map.isSolid(cell.col, cell.row);

/// A walker stands on a cell when the cell below is solid or one-way, or the
/// cell itself is a ladder, which is the same test the physics uses.
bool _grounded(TileMap map, _Cell cell) {
  final below = _Cell(cell.col, cell.row + 1);
  if (!_inBounds(map, below)) return false;
  if (map.isSolid(below.col, below.row)) return true;
  if (map.oneWayTileIds.contains(map.tileAt(below.col, below.row))) return true;
  return map.ladderTileIds.contains(map.tileAt(cell.col, cell.row));
}
