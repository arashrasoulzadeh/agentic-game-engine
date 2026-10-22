import 'order.dart';

/// How many cells a grid unit covers: a [size] x [size] square whose top-left cell is its
/// `GridPosition`. Absent means one cell, so existing units are unchanged.
///
/// This is the "collision radius larger than one cell" of the real-time and turn-based strategy layers: a
/// siege engine or a boss that blocks, and is blocked by, a 2x2 or 3x3 patch of ground.
class GridFootprint {
  /// Side length in cells (1 or more).
  final int size;

  GridFootprint(this.size)
    : assert(size >= 1, 'a footprint covers at least one cell');

  Map<String, dynamic> toJson() => {'size': size};

  factory GridFootprint.fromJson(Map<String, dynamic> json) =>
      GridFootprint((json['size'] as num?)?.toInt() ?? 1);
}

/// Whether a [aSize] square at [a] and a [bSize] square at [b] share a cell.
bool footprintsOverlap(GridPosition a, int aSize, GridPosition b, int bSize) =>
    a.col < b.col + bSize &&
    b.col < a.col + aSize &&
    a.row < b.row + bSize &&
    b.row < a.row + aSize;

/// Cells between the nearest edges of two footprints, measured like [GridPosition.chebyshev]: 0 when they
/// overlap, 1 when adjacent. Attack range for a big unit is measured from its edge, not its corner.
int footprintDistance(GridPosition a, int aSize, GridPosition b, int bSize) {
  int gap(int pa, int sa, int pb, int sb) {
    if (pa + sa <= pb) return pb - (pa + sa) + 1;
    if (pb + sb <= pa) return pa - (pb + sb) + 1;
    return 0;
  }

  final dc = gap(a.col, aSize, b.col, bSize);
  final dr = gap(a.row, aSize, b.row, bSize);
  return dc > dr ? dc : dr;
}
