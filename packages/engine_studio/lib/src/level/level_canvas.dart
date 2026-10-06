import 'package:flutter/material.dart';

import 'level_editor.dart';
import 'level_geometry.dart';

/// Draws a level's tile map and entity markers from its data, without running
/// any systems. Tiles are coloured by collision kind; each entity gets a marker
/// and its name. Positions come from the [LevelEditor], so an in-progress drag
/// shows where the entity is going before the move is committed.
///
/// This draws directly rather than through `EngineView`, which needs sprite
/// atlases that the asset browser provides in phase 5.
class LevelCanvasPainter extends CustomPainter {
  final LevelEditor editor;

  LevelCanvasPainter({required this.editor});

  static const _empty = Color(0xFF1E1E22);
  static const _solid = Color(0xFF8A8A94);
  static const _oneWay = Color(0xFF6FA8DC);
  static const _marker = Color(0xFFE0474C);
  static const _grid = Color(0x22FFFFFF);
  static const _selected = Color(0xFFFFD54F);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _empty);
    if (editor.showTiles) _paintTiles(canvas, editor.geometry);
    if (editor.gridVisible) _paintGrid(canvas, size);
    if (editor.showEntities) _paintEntities(canvas);
  }

  /// Grid lines every [LevelEditor.gridSize] world units, drawn faintly so they
  /// help placement without competing with tiles and markers.
  void _paintGrid(Canvas canvas, Size size) {
    final step = editor.gridSize;
    if (step <= 0) return;
    final paint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintTiles(Canvas canvas, LevelGeometry geometry) {
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
        canvas.drawRect(
          Rect.fromLTWH(
            origin.dx + col * map.tileWidth,
            origin.dy + row * map.tileHeight,
            map.tileWidth,
            map.tileHeight,
          ),
          paint,
        );
      }
    }
  }

  void _paintEntities(Canvas canvas) {
    final document = editor.document;
    for (final entity in document.entities) {
      final at = editor.displayPositionOf(entity);
      if (at == null) continue;
      final selected = identical(entity, editor.selected);
      canvas.drawCircle(
        at,
        selected ? 7 : 5,
        Paint()..color = selected ? _selected : _marker,
      );

      final name = entity.name;
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
  bool shouldRepaint(LevelCanvasPainter old) => true;
}
