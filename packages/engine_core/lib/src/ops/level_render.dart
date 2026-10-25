import 'dart:typed_data';

import '../physics/tile_map.dart';
import 'image_codec.dart';

/// Pixels per tile in a lint preview PNG — not the level's own `tileWidth`/`tileHeight`
/// (which could be tiny or huge), so levels with different tile sizes render at a
/// consistent, readable size.
const levelRenderPixelsPerTile = 16;

/// Structural preview colours — distinguishable at a glance, not game art.
const levelRenderEmpty = EngineColor(30, 30, 34);
const levelRenderSolid = EngineColor(120, 120, 128);
const levelRenderOneWay = EngineColor(140, 180, 220);
const levelRenderSlope = EngineColor(210, 150, 90);
const levelRenderEntity = EngineColor(230, 60, 60);

/// One positioned entity to mark on the preview.
class LevelRenderMarker {
  const LevelRenderMarker(this.x, this.y, [this.name]);

  final double x, y;
  final String? name;
}

/// Result of [renderLevelPreview].
class LevelRenderResult {
  const LevelRenderResult({
    required this.png,
    required this.cols,
    required this.rows,
    required this.markerCount,
    required this.width,
    required this.height,
  });

  final Uint8List png;
  final int cols, rows, markerCount, width, height;
}

/// Rasterizes [map] (plus optional entity [markers]) to a PNG via [codec].
///
/// Same structural preview `game_agent lint --render` used: solid / one-way / slope
/// tiles coloured, entities as red dots with optional name labels.
LevelRenderResult renderLevelPreview(
  ImageCodec codec,
  TileMap map, {
  List<LevelRenderMarker> markers = const [],
  int pixelsPerTile = levelRenderPixelsPerTile,
}) {
  final image = codec.create(
    map.cols * pixelsPerTile,
    map.rows * pixelsPerTile,
  );
  codec.fill(image, levelRenderEmpty);

  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final tileId = map.tileAt(col, row);
      if (tileId == 0) continue;
      final color = map.isSolid(col, row)
          ? levelRenderSolid
          : map.isOneWay(col, row)
          ? levelRenderOneWay
          : (map.isSlopeUpRight(col, row) || map.isSlopeUpLeft(col, row))
          ? levelRenderSlope
          : levelRenderEmpty;
      codec.fillRect(
        image,
        x1: col * pixelsPerTile,
        y1: row * pixelsPerTile,
        x2: (col + 1) * pixelsPerTile - 1,
        y2: (row + 1) * pixelsPerTile - 1,
        color: color,
      );
    }
  }

  final scaleX = pixelsPerTile / map.tileWidth;
  final scaleY = pixelsPerTile / map.tileHeight;
  for (final m in markers) {
    final px = (m.x * scaleX).round();
    final py = (m.y * scaleY).round();
    codec.fillCircle(
      image,
      x: px,
      y: py,
      radius: 3,
      color: levelRenderEntity,
    );
    if (m.name != null) {
      codec.drawString(
        image,
        m.name!,
        x: px + 5,
        y: py - 6,
        color: levelRenderEntity,
      );
    }
  }

  return LevelRenderResult(
    png: codec.encodePng(image),
    cols: map.cols,
    rows: map.rows,
    markerCount: markers.length,
    width: image.width,
    height: image.height,
  );
}
