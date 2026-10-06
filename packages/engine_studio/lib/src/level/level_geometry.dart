import 'dart:ui';

import 'package:engine_core/engine_core.dart';

/// Where a level's things are in world units, read from its data. Pure Dart, so
/// the view and the hit-test share one answer for "where is this entity" and
/// neither can drift from the other.
class LevelGeometry {
  /// The level's tile map, or null when the level has none. Legend-authored maps
  /// are converted by `TileMap.fromJson`, the same parser the engine uses.
  final TileMap? tileMap;

  /// World position of the tile map's origin entity. Tiles are drawn relative to it.
  final Offset tileOrigin;

  /// Each positioned entity's world position, by its index in the document.
  final Map<int, Offset> entityPositions;

  const LevelGeometry({
    required this.tileMap,
    required this.tileOrigin,
    required this.entityPositions,
  });

  /// Reads [document]. A malformed tile map is treated as absent here, since the
  /// validator already reports it as an error and the view should still open.
  factory LevelGeometry.of(LevelDocument document) {
    TileMap? map;
    Offset origin = Offset.zero;
    final positions = <int, Offset>{};

    for (var i = 0; i < document.entities.length; i++) {
      final components = document.entities[i].components;
      final position = _positionOf(components);
      if (position != null) positions[i] = position;

      final tileJson = components['tileMap'];
      if (tileJson != null && map == null) {
        try {
          map = TileMap.fromJson(tileJson);
          origin = position ?? Offset.zero;
        } on Object {
          map = null;
        }
      }
    }
    return LevelGeometry(
      tileMap: map,
      tileOrigin: origin,
      entityPositions: positions,
    );
  }

  static Offset? _positionOf(Map<String, Map<String, dynamic>> components) {
    final position = components['position'];
    if (position == null) return null;
    final x = position['x'];
    final y = position['y'];
    if (x is! num || y is! num) return null;
    return Offset(x.toDouble(), y.toDouble());
  }

  /// World-space size of one tile, or a placeholder size when there is no map.
  Size get tileSize {
    final map = tileMap;
    return map == null
        ? const Size(16, 16)
        : Size(map.tileWidth, map.tileHeight);
  }

  /// The index of the entity under [point] (world units), or null. The nearest
  /// entity within [pickRadius] wins; ties go to the entity earlier in the file,
  /// so clicking a stack of markers picks the same one every time.
  int? entityAt(Offset point, {double pickRadius = 12}) {
    int? best;
    var bestDistance = double.infinity;
    entityPositions.forEach((index, position) {
      final distance = (position - point).distance;
      if (distance <= pickRadius && distance < bestDistance) {
        best = index;
        bestDistance = distance;
      }
    });
    return best;
  }
}
