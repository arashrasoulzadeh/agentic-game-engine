import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_canvas.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed sample level (docs/studio/design.md 3.14): a small tile map mixing solid
/// and one-way tiles, plus a named entity, so the golden image exercises
/// every tile-color branch LevelCanvasPainter has, not just solid-vs-empty.
LevelDocument _sampleLevel() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1, '=': 2},
          'rows': ['....', '=..#', '####'],
          'oneWayTileIds': [2],
        },
      },
    },
    {
      'name': 'player',
      'components': {
        'position': {'x': 24.0, 'y': 16.0},
      },
    },
  ],
});

void main() {
  testWidgets(
    'the level canvas renders a fixed sample level consistently',
    (tester) async {
      final editor = LevelEditor(_sampleLevel());
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 150,
              child: RepaintBoundary(
                key: const Key('level-canvas-golden'),
                child: CustomPaint(painter: LevelCanvasPainter(editor: editor)),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(const Key('level-canvas-golden')),
        matchesGoldenFile('goldens/level_canvas_sample.png'),
      );
    },
  );
}
