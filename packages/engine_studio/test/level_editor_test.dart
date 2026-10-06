import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 3x2 legend-authored map at the origin with a player at (24, 8), which is
/// cell (1, 0)'s centre-ish, and a coin at (40, 24).
LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['...', '###'],
        },
      },
    },
    {
      'name': 'player',
      'components': {
        'position': {'x': 24.0, 'y': 8.0},
      },
    },
    {
      'name': 'coin',
      'components': {
        'position': {'x': 40.0, 'y': 24.0},
      },
    },
  ],
});

String _snapshot(LevelDocument doc) => jsonEncode(doc.toJson());

List<int> _tiles(LevelDocument doc) =>
    ((doc.entities.first.components['tileMap']!['tiles']) as List).cast<int>();

void main() {
  _validationTests();
  group('select', () {
    test('a tap selects the entity under it', () {
      final editor = LevelEditor(_level());
      editor.tap(const Offset(24, 8));
      expect(editor.selected?.name, 'player');
    });

    test('a tap on empty space clears the selection', () {
      final editor = LevelEditor(_level());
      editor.tap(const Offset(24, 8));
      editor.tap(const Offset(45, 45));
      expect(editor.selected, isNull);
    });

    test('selecting does not change the document or the undo history', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tap(const Offset(24, 8));
      expect(_snapshot(doc), before);
      expect(editor.history.canUndo, isFalse);
    });
  });

  group('place entity', () {
    test('a tap adds an entity at that point and selects it, undoably', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.placeEntity;
      final before = _snapshot(doc);

      editor.tap(const Offset(100, 60));
      expect(doc.entities, hasLength(4));
      expect(editor.selected, same(doc.entities.last));
      expect(doc.entities.last.components['position'], {'x': 100.0, 'y': 60.0});

      editor.history.undo();
      expect(_snapshot(doc), before);
    });
  });

  group('move', () {
    test('a drag previews the position and commits one move on release', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.move;
      final player = doc.entities[1];

      editor.dragStart(const Offset(24, 8));
      editor.dragUpdate(const Offset(60, 40));
      expect(editor.displayPositionOf(player), const Offset(60, 40));
      expect(
        player.components['position'],
        {'x': 24.0, 'y': 8.0},
        reason: 'the document is not changed until the drag ends',
      );

      editor.dragEnd(const Offset(60, 40));
      expect(player.components['position'], {'x': 60.0, 'y': 40.0});
      expect(editor.history.undoLabel, 'Move player');
    });

    test('moving and then undoing restores the original position', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tool = EditorTool.move;
      editor.dragStart(const Offset(24, 8));
      editor.dragEnd(const Offset(70, 70));
      editor.history.undo();
      expect(_snapshot(doc), before);
    });

    test('dragging empty space does nothing', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tool = EditorTool.move;
      editor.dragStart(const Offset(200, 200));
      editor.dragEnd(const Offset(210, 210));
      expect(_snapshot(doc), before);
    });
  });

  group('tile tools', () {
    test(
      'the first tile edit converts the legend map to flat ids, undoably',
      () {
        final doc = _level();
        final before = _snapshot(doc);
        final editor = LevelEditor(doc)..tool = EditorTool.paintTile;

        editor.tap(const Offset(20, 2)); // cell (1, 0)
        expect(
          doc.entities.first.components['tileMap']!.containsKey('tiles'),
          isTrue,
        );
        expect(_tiles(doc)[1], 1);

        editor.history.undo(); // the paint
        editor.history.undo(); // the flatten
        expect(_snapshot(doc), before);
      },
    );

    test('a paint drag is one undo step, painting each cell it crosses', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.paintTile;
      final before = _snapshot(doc);

      editor.dragStart(const Offset(2, 2)); // cell (0, 0)
      editor.dragUpdate(const Offset(20, 2)); // cell (1, 0)
      editor.dragUpdate(const Offset(36, 2)); // cell (2, 0)
      editor.dragEnd(const Offset(36, 2));

      expect(_tiles(doc).take(3), [1, 1, 1]);
      expect(editor.history.undoLabel, 'Paint stroke');
      editor.history.undo();
      // Undoing the stroke leaves the flattened map, with its original tiles.
      expect(_tiles(doc).take(3), [0, 0, 0]);
      expect(
        before,
        isNot(_snapshot(doc)),
        reason: 'the flatten is still applied',
      );
    });

    test('erase writes id 0 over painted cells', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.paintTile;
      editor.tap(const Offset(2, 2));
      editor.tool = EditorTool.eraseTile;
      editor.tap(const Offset(2, 2));
      expect(_tiles(doc).first, 0);
    });

    test('fill replaces the connected region of the tapped cell', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.fill;
      editor.paintTileId = 5;
      editor.tap(const Offset(2, 2)); // open cell in row 0
      expect(_tiles(doc).take(3), [5, 5, 5]);
      expect(_tiles(doc).skip(3), [
        1,
        1,
        1,
      ], reason: 'the solid row is a different region');
    });

    test('a tap outside the tile map does nothing', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tool = EditorTool.paintTile;
      editor.tap(const Offset(500, 500));
      expect(_snapshot(doc), before);
    });
  });

  group('delete', () {
    test('removes the selected entity as one undoable command', () {
      final doc = _level();
      final before = _snapshot(doc);
      final editor = LevelEditor(doc)..tap(const Offset(24, 8));
      editor.deleteSelected();
      expect(doc.entities.map((e) => e.name), ['map', 'coin']);
      editor.history.undo();
      expect(_snapshot(doc), before);
    });

    test('does nothing with no selection', () {
      final doc = _level();
      final editor = LevelEditor(doc)..deleteSelected();
      expect(editor.history.canUndo, isFalse);
    });
  });

  group('history selection', () {
    test(
      'undoing the placement that created the selected entity clears the selection',
      () {
        final editor = LevelEditor(_level())..tool = EditorTool.placeEntity;
        editor.tap(const Offset(100, 60));
        expect(editor.selected, isNotNull);
        editor.undo();
        expect(editor.selected, isNull);
      },
    );

    test(
      'redo keeps selection clear when the re-applied entity is not selected',
      () {
        final editor = LevelEditor(_level())..tool = EditorTool.placeEntity;
        editor.tap(const Offset(100, 60));
        editor.undo();
        editor.redo();
        expect(editor.selected, isNull);
      },
    );

    test('undoing an edit keeps a selection that is still in the level', () {
      final doc = _level();
      final editor = LevelEditor(doc)..tool = EditorTool.placeEntity;
      editor.tap(const Offset(100, 60));
      editor.tool = EditorTool.select;
      editor.tap(const Offset(24, 8)); // selects the player; no command
      editor.undo(); // removes the placed entity, not the player
      expect(editor.selected?.name, 'player');
    });
  });
}

void _validationTests() {
  group('validation', () {
    test(
      'issues reports the validator problems for the level as it is now',
      () {
        final doc = LevelDocument.fromJson({
          'entities': [
            {
              'components': {'warpDrive': {}},
            },
          ],
        });
        final editor = LevelEditor(doc);
        expect(editor.issues.map((i) => i.message), [
          'unknown component "warpDrive"',
        ]);
      },
    );

    test('issues updates after an edit fixes the problem', () {
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'pushable': {'pushSpeed': -1.0},
            },
          },
        ],
      });
      final editor = LevelEditor(doc);
      expect(editor.issues, isNotEmpty);
      editor.history.execute(
        SetComponentFieldCommand(
          entity: doc.entities.first,
          component: 'pushable',
          field: 'pushSpeed',
          value: 1.0,
        ),
      );
      expect(editor.issues, isEmpty);
    });

    test(
      'selectIndex selects that entity, and ignores an index outside the level',
      () {
        final doc = _level();
        final editor = LevelEditor(doc);
        editor.selectIndex(1);
        expect(editor.selected, same(doc.entities[1]));
        editor.selectIndex(9);
        expect(editor.selected, same(doc.entities[1]));
      },
    );
  });
}
