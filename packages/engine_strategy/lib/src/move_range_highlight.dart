import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Lights up the cells the single selected unit can reach with the action points
/// it has left, using one marker `Sprite` per cell.
///
/// Rebuilt only when the selection, the unit's cell or its points change (a
/// short key comparison per tick), never every frame. Marker entities are
/// ordinary world entities tagged with [MoveRangeMarker], so a save never
/// carries stale highlights: they are removed on the next update.
class MoveRangeHighlightSystem extends System {
  MoveRangeHighlightSystem({
    required this.navigator,
    required this.cellSize,
    required this.atlasId,
    required this.region,
    this.zIndex = -5,
    this.spriteSize = 32,
  });

  final GridNavigator navigator;
  final double cellSize;
  final String atlasId;
  final String region;
  final int zIndex;

  /// Pixel size of [region] in its atlas; the sprite is scaled to [cellSize].
  final double spriteSize;

  String _key = '';

  @override
  String get name => 'moveRangeHighlight';

  @override
  void update(World world, double dt) {
    final selected = selectedEntities(world);
    final unit = selected.length == 1 ? selected.single : null;
    final grid = world.storeOf<GridPosition>();
    final pos = unit == null ? null : grid.get(unit);
    final points = unit == null ? null : world.storeOf<ActionPoints>().get(unit);
    final key = pos == null || points == null ? '' : '$unit:${pos.col},${pos.row}:${points.current}';
    if (key == _key) return;
    _key = key;

    final markers = world.storeOf<MoveRangeMarker>();
    for (final id in [for (var i = 0; i < markers.length; i++) markers.entityAt(i)]) {
      world.destroy(id);
    }
    if (pos == null || points == null) return;

    bool occupied(int col, int row) {
      for (var i = 0; i < grid.length; i++) {
        final g = grid.denseAt(i);
        if (grid.entityAt(i) != unit && g.col == col && g.row == row) return true;
      }
      return false;
    }

    for (final cell in navigator.reachable(pos, points.current, blocked: occupied).keys) {
      final id = world.spawn();
      world.storeOf<MoveRangeMarker>().set(id, const MoveRangeMarker());
      world.storeOf<Position>().set(id, Position((cell.$1 + 0.5) * cellSize, (cell.$2 + 0.5) * cellSize));
      world.storeOf<Sprite>().set(
            id,
            Sprite(atlasId, region)
              ..scaleX = cellSize / spriteSize
              ..scaleY = cellSize / spriteSize
              ..zIndex = zIndex,
          );
    }
  }
}

/// Tags a highlight entity so the system can find and clear its own markers.
class MoveRangeMarker {
  const MoveRangeMarker();

  Map<String, dynamic> toJson() => {};
  factory MoveRangeMarker.fromJson(Map<String, dynamic> json) => const MoveRangeMarker();
}
