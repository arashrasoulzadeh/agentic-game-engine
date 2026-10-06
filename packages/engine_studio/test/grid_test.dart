import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 24.0, 'y': 8.0},
      },
    },
  ],
});

String _snapshot(LevelDocument doc) => jsonEncode(doc.toJson());

void main() {
  group('snapping', () {
    test(
      'snapped() rounds to the nearest grid intersection when snapping is on',
      () {
        final editor = LevelEditor(_level())
          ..snapToGrid = true
          ..gridSize = 16;
        expect(editor.snapped(const Offset(23, 9)), const Offset(16, 16));
        expect(editor.snapped(const Offset(25, 30)), const Offset(32, 32));
      },
    );

    test('snapped() leaves a point alone when snapping is off', () {
      final editor = LevelEditor(_level())..gridSize = 16;
      expect(editor.snapped(const Offset(23, 9)), const Offset(23, 9));
    });

    test(
      'snapping with a non-positive grid size changes nothing rather than dividing by zero',
      () {
        final editor = LevelEditor(_level())
          ..snapToGrid = true
          ..gridSize = 0;
        expect(editor.snapped(const Offset(23, 9)), const Offset(23, 9));
      },
    );

    test('a placed entity lands on the grid when snapping is on', () {
      final editor = LevelEditor(_level())
        ..tool = EditorTool.placeEntity
        ..snapToGrid = true;
      editor.tap(const Offset(23, 9));
      expect(editor.selected!.components['position'], {'x': 16.0, 'y': 16.0});
    });

    test('a move lands on the grid when snapping is on', () {
      final doc = _level();
      final editor = LevelEditor(doc)
        ..tool = EditorTool.move
        ..snapToGrid = true;
      editor.dragStart(const Offset(24, 8));
      editor.dragEnd(const Offset(70, 39));
      expect(doc.entities.first.components['position'], {'x': 64.0, 'y': 32.0});
    });
  });

  group('layer visibility', () {
    test(
      'hiding a layer does not change the data, so nothing is dirty and nothing is lost',
      () {
        final doc = _level();
        final before = _snapshot(doc);
        final editor = LevelEditor(doc)
          ..showEntities = false
          ..showTiles = false;
        expect(_snapshot(doc), before);
        expect(editor.isDirty, isFalse);
      },
    );
  });

  group('toolbar', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('grid_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('the grid and snap toggles switch their state', (tester) async {
      final path = '${dir.path}/level.json';
      File(path).writeAsStringSync(jsonEncode(_level().toJson()));
      await tester.pumpWidget(
        MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
      );

      IconButton button(String key) =>
          tester.widget<IconButton>(find.byKey(Key(key)));
      expect(
        button('toggle-grid').isSelected,
        isTrue,
        reason: 'the grid starts shown',
      );
      expect(
        button('toggle-snap').isSelected,
        isFalse,
        reason: 'snapping starts off',
      );

      await tester.tap(find.byKey(const Key('toggle-snap')));
      await tester.pump();
      expect(button('toggle-snap').isSelected, isTrue);

      await tester.tap(find.byKey(const Key('toggle-grid')));
      await tester.pump();
      expect(button('toggle-grid').isSelected, isFalse);
    });
  });
}
