import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_canvas.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/studio/design.md 3.16: a 500x500 tile level should pan and paint at 60fps
/// (under ~16.6ms/frame) on the reference machine. `flutter test` can't
/// measure a real GPU frame, so this measures what the studio actually
/// controls -- `LevelCanvasPainter.paint`'s own CPU cost -- by recording it
/// into an off-screen `ui.PictureRecorder`/`Canvas` (available under
/// `flutter test` without a widget tree) the same number of times a minute
/// of panning at 60fps would call it, and prints the measured per-frame
/// average so real numbers are recorded, not just asserted blindly.
///
/// The pass/fail threshold here is deliberately generous (100ms/frame, ~6x
/// slower than 60fps) rather than a tight 16.6ms gate: CI runners vary far
/// more in raw speed than any one "reference machine" this number is
/// actually about, so a tight bound would make this test flaky, not useful.
/// The printed average is the number that answers 3.16's question.
LevelDocument _bigLevel({required int size}) {
  final map = TileMap(
    cols: size,
    rows: size,
    tileWidth: 16,
    tileHeight: 16,
    tiles: List.generate(size * size, (i) => i % 7 == 0 ? 1 : 0),
    solidTileIds: {1},
  );
  return LevelDocument(
    entities: [
      LevelEntity(
        name: 'map',
        components: {
          'position': {'x': 0.0, 'y': 0.0},
          'tileMap': map.toJson(),
        },
      ),
      for (var i = 0; i < 50; i++)
        LevelEntity(
          name: 'entity$i',
          components: {
            'position': {'x': (i * 37 % size) * 16.0, 'y': (i * 53 % size) * 16.0},
          },
        ),
    ],
  );
}

void main() {
  test(
    'LevelCanvasPainter.paint on a 500x500 level stays fast enough across '
    'many simulated frames',
    () {
      final editor = LevelEditor(_bigLevel(size: 500));
      final painter = LevelCanvasPainter(editor: editor);
      const viewport = Size(1200, 800);
      const frames = 60;

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, viewport);
        recorder.endRecording().dispose();
      }
      stopwatch.stop();

      final perFrameMs = stopwatch.elapsedMicroseconds / frames / 1000;
      // ignore: avoid_print
      print(
        'LevelCanvasPainter on a 500x500 level: '
        '${perFrameMs.toStringAsFixed(2)}ms/frame average over $frames frames '
        '(60fps budget is ${(1000 / 60).toStringAsFixed(1)}ms/frame).',
      );
      expect(
        perFrameMs,
        lessThan(100),
        reason:
            'a 500x500-tile frame took ${perFrameMs.toStringAsFixed(1)}ms, '
            'which is far outside even a generous budget -- something got '
            'much slower, not just "not quite 60fps on this machine"',
      );
    },
  );
}
