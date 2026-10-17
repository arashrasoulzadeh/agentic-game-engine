import 'dart:math' as math;

import 'package:engine_core/engine_core.dart';

/// Glides each unit's `Position` toward the center of its cell instead of snapping
/// to it, so units that advance a whole cell per step (real-time play) render as
/// smooth movement.
///
/// **Rendering only.** The grid stays the single source of truth: `GridPosition`
/// is what rules, fog and networking read, and this system never changes it. Run it
/// in place of `GridToWorldSystem` (not alongside); [installRealtimeStrategySystems]
/// does that when asked for `smoothMotion`.
///
/// Speed is [cellsPerSecond] *of catch-up*: a unit that the order system moves at
/// 4 cells/s should glide at least that fast or it lags further behind; the default
/// is generous so visual lag stays under about one cell. A unit teleported far away
/// (a respawn, a snapshot restore) snaps once the gap exceeds [snapDistanceCells]
/// rather than sliding across the map.
class SmoothGridToWorldSystem extends System {
  SmoothGridToWorldSystem(
    this.cellSize, {
    this.cellsPerSecond = 12,
    this.snapDistanceCells = 4,
  });

  final double cellSize;
  final double cellsPerSecond;
  final double snapDistanceCells;

  @override
  String get name => 'smoothGridToWorld';

  @override
  void update(World world, double dt) {
    final grid = world.storeOf<GridPosition>();
    final positions = world.storeOf<Position>();
    final maxStep = cellsPerSecond * cellSize * dt;
    for (var i = 0; i < grid.length; i++) {
      final p = positions.get(grid.entityAt(i));
      if (p == null) continue;
      final g = grid.denseAt(i);
      final tx = (g.col + 0.5) * cellSize, ty = (g.row + 0.5) * cellSize;
      final dx = tx - p.x, dy = ty - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= maxStep || dist > snapDistanceCells * cellSize) {
        p.x = tx;
        p.y = ty;
      } else {
        p.x += dx / dist * maxStep;
        p.y += dy / dist * maxStep;
      }
    }
  }
}
