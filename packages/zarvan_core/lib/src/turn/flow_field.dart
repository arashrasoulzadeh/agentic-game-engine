import 'grid_navigation.dart';
import 'order.dart';

/// Every cell's cheapest cost to a goal, computed once, so any number of units
/// can path to that goal by repeatedly stepping "downhill" -- the standard way to
/// move a large group. `GridNavigator.findPath` runs a search per unit; a hundred
/// units sent to one spot would run a hundred searches, while a flow field is one
/// pass over the grid whose answer every unit shares.
///
/// Costs use the navigator's rules (terrain costs, diagonals, no corner cutting),
/// so a unit following the field takes the same routes `findPath` would, just
/// without re-searching. Units are not part of the field (they move); pass
/// [nextStep] a `blocked` callback and it steers around them.
class FlowField {
  FlowField._(this.navigator, this.goalCol, this.goalRow, this._cost);

  final GridNavigator navigator;
  final int goalCol;
  final int goalRow;
  final List<int> _cost;

  static const int unreachable = -1;

  /// Builds the field for a goal cell. A goal on impassable terrain leaves every
  /// cell [unreachable].
  factory FlowField.build(GridNavigator navigator, int goalCol, int goalRow) {
    final cols = navigator.cols, rows = navigator.rows;
    final cost = List<int>.filled(cols * rows, unreachable);
    if (navigator.inBounds(goalCol, goalRow) &&
        navigator.terrainCost(goalCol, goalRow) != null) {
      cost[goalRow * cols + goalCol] = 0;
      // Dijkstra with a bucket queue would be faster; a plain sorted frontier
      // keeps this short and is fine at strategy-map sizes.
      final frontier = <(int, int, int)>[(0, goalCol, goalRow)];
      while (frontier.isNotEmpty) {
        var best = 0;
        for (var i = 1; i < frontier.length; i++) {
          if (frontier[i].$1 < frontier[best].$1) best = i;
        }
        final (d, c, r) = frontier.removeAt(best);
        if (d > cost[r * cols + c]) continue;
        // Entering (c, r) costs its terrain; a cell X that can step into (c, r)
        // is therefore d + terrainCost(c, r) away from the goal.
        final enter = navigator.terrainCost(c, r)!;
        for (final (nc, nr, _) in navigator.neighbours(c, r)) {
          final nd = d + enter;
          final at = nr * cols + nc;
          if (cost[at] == unreachable || nd < cost[at]) {
            cost[at] = nd;
            frontier.add((nd, nc, nr));
          }
        }
      }
    }
    return FlowField._(navigator, goalCol, goalRow, cost);
  }

  /// Cost from ([col], [row]) to the goal, or [unreachable].
  int costAt(int col, int row) => navigator.inBounds(col, row)
      ? _cost[row * navigator.cols + col]
      : unreachable;

  bool reaches(int col, int row) => costAt(col, row) != unreachable;

  /// The best cell to step into from [from], or null when already at the goal,
  /// when the goal is unreachable from here, or when every improving neighbour is
  /// [blocked] (by another unit). Never returns a cell that isn't strictly closer
  /// to the goal, so following it always terminates.
  GridPosition? nextStep(
    GridPosition from, {
    bool Function(int col, int row)? blocked,
  }) {
    final here = costAt(from.col, from.row);
    if (here == unreachable || here == 0) return null;
    GridPosition? best;
    var bestTotal = 1 << 30;
    for (final (c, r, enter) in navigator.neighbours(
      from.col,
      from.row,
      blocked: blocked,
    )) {
      final there = costAt(c, r);
      // Only strictly closer cells count, so following the field always ends.
      if (there == unreachable || there >= here) continue;
      final total = there + enter;
      if (total < bestTotal) {
        best = GridPosition(c, r);
        bestTotal = total;
      }
    }
    return best;
  }
}

/// Flow fields keyed by goal cell, so units sent to the same place share one.
///
/// Call [invalidate] when the terrain changes (a wall built or destroyed): fields
/// bake in the navigator's rules at build time. Bounded by [capacity] with
/// least-recently-used eviction, because every distinct goal is a full grid of
/// ints and a game issuing orders to thousands of different cells shouldn't grow
/// without limit.
class FlowFieldCache {
  FlowFieldCache(this.navigator, {this.capacity = 32});

  final GridNavigator navigator;
  final int capacity;
  final Map<int, FlowField> _fields = {};

  /// Fields built since creation (cache misses): what a test or profiler reads to
  /// confirm a group is sharing work.
  int builds = 0;

  final Map<int, GridNavigator> _bodies = {};

  /// The field leading to ([goalCol], [goalRow]) for a unit whose body is [footprint] x [footprint] cells:
  /// a big unit's field avoids gaps it cannot fit through. Fields are cached per footprint.
  FlowField fieldFor(int goalCol, int goalRow, {int footprint = 1}) {
    final key =
        (footprint * navigator.rows + goalRow) * navigator.cols + goalCol;
    final existing = _fields.remove(key);
    if (existing != null) {
      _fields[key] = existing; // refresh recency
      return existing;
    }
    builds++;
    final field = FlowField.build(
      _bodies.putIfAbsent(footprint, () => navigator.forFootprint(footprint)),
      goalCol,
      goalRow,
    );
    _fields[key] = field;
    if (_fields.length > capacity) _fields.remove(_fields.keys.first);
    return field;
  }

  int get size => _fields.length;

  void invalidate() {
    _fields.clear();
    _bodies.clear();
  }
}
