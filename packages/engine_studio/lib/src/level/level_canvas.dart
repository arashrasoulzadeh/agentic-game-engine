import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import 'level_geometry.dart';

/// Draws a level's tile map and entity markers from its data, without running
/// any systems. Tiles are coloured by collision kind so a designer can read the
/// level's shape at a glance; each entity gets a marker and its name.
///
/// This is the first view, and it draws directly rather than through `EngineView`
/// because `EngineView` needs sprite atlases, which the asset browser (phase 5)
/// provides.
class LevelCanvasPainter extends CustomPainter {
  final LevelDocument document;
  final LevelGeometry geometry;
  final int? selectedEntity;

  LevelCanvasPainter({
    required this.document,
    required this.geometry,
    this.selectedEntity,
  });

  static const _empty = Color(0xFF1E1E22);
  static const _solid = Color(0xFF8A8A94);
  static const _oneWay = Color(0xFF6FA8DC);
  static const _marker = Color(0xFFE0474C);
  static const _selected = Color(0xFFFFD54F);

  /// Pixels per world unit, so one 16-unit tile is 16px at the default zoom.
  static const double scale = 1;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _empty);
    _paintTiles(canvas);
    _paintEntities(canvas);
  }

  void _paintTiles(Canvas canvas) {
    final map = geometry.tileMap;
    if (map == null) return;
    final origin = geometry.tileOrigin;
    final solid = Paint()..color = _solid;
    final oneWay = Paint()..color = _oneWay;
    for (var row = 0; row < map.rows; row++) {
      for (var col = 0; col < map.cols; col++) {
        final id = map.tileAt(col, row);
        final Paint? paint = map.solidTileIds.contains(id)
            ? solid
            : map.oneWayTileIds.contains(id)
            ? oneWay
            : null;
        if (paint == null) continue;
        final rect = Rect.fromLTWH(
          origin.dx + col * map.tileWidth,
          origin.dy + row * map.tileHeight,
          map.tileWidth,
          map.tileHeight,
        );
        canvas.drawRect(rect, paint);
      }
    }
  }

  void _paintEntities(Canvas canvas) {
    for (final entry in geometry.entityPositions.entries) {
      final index = entry.key;
      final at = entry.value;
      final selected = index == selectedEntity;
      canvas.drawCircle(
        at,
        selected ? 7 : 5,
        Paint()..color = selected ? _selected : _marker,
      );

      final name = document.entities[index].name;
      if (name == null) continue;
      final label = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: selected ? _selected : Colors.white,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, at + const Offset(8, -6));
    }
  }

  @override
  bool shouldRepaint(LevelCanvasPainter old) =>
      old.document != document || old.selectedEntity != selectedEntity;
}
