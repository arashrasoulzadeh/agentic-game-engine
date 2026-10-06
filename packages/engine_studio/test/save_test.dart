import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:engine_studio/src/level/level_saver.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _level() => {
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 24.0, 'y': 8.0},
      },
    },
  ],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('save_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String levelPath() => '${dir.path}/assets/levels/level.json';

  void writeLevel() {
    File(levelPath())
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(_level()));
  }

  group('LevelSaver', () {
    test(
      'a saved level loads back to the same data, with no temp file left behind',
      () {
        writeLevel();
        final doc = LevelDocument.fromJson(_level())
          ..entities.first.components['position'] = {'x': 99.0, 'y': 1.0};
        LevelSaver.save(levelPath(), doc);

        final reloaded = LevelDocument.fromJson(
          jsonDecode(File(levelPath()).readAsStringSync())
              as Map<String, dynamic>,
        );
        expect(reloaded.toJson(), doc.toJson());
        expect(File('${levelPath()}.tmp').existsSync(), isFalse);
      },
    );

    test(
      'autosave writes a backup under .studio and leaves the level file untouched',
      () {
        writeLevel();
        final original = File(levelPath()).readAsStringSync();
        final doc = LevelDocument.fromJson(_level())
          ..entities.first.components['position'] = {'x': 5.0, 'y': 5.0};

        final backup = LevelSaver.autosave(
          projectRoot: dir.path,
          levelPath: levelPath(),
          document: doc,
        );

        expect(backup, '${dir.path}/.studio/autosave/level.json');
        expect(File(backup).readAsStringSync(), contains('5.0'));
        expect(File(levelPath()).readAsStringSync(), original);
      },
    );
  });

  group('LevelEditor dirty state', () {
    test(
      'an edit makes the level dirty, saving clears it, and undo back to the saved state is clean',
      () {
        final editor = LevelEditor(LevelDocument.fromJson(_level()));
        expect(editor.isDirty, isFalse);

        editor.tool = EditorTool.move;
        editor.dragStart(const Offset(24, 8));
        editor.dragEnd(const Offset(60, 60));
        expect(editor.isDirty, isTrue);

        editor.markSaved();
        expect(editor.isDirty, isFalse);

        editor.dragStart(const Offset(60, 60));
        editor.dragEnd(const Offset(70, 70));
        expect(editor.isDirty, isTrue);
        editor.undo();
        expect(editor.isDirty, isFalse, reason: 'back at the saved state');
      },
    );
  });

  group('LevelScreen save', () {
    testWidgets(
      'Save writes the edit to the level file and clears the dirty marker',
      (tester) async {
        writeLevel();
        await tester.pumpWidget(
          MaterialApp(
            home: LevelScreen(levelPath: levelPath(), autosaveInterval: null),
          ),
        );

        expect(find.byKey(const Key('dirty-marker')), findsNothing);
        await tester.tap(find.text('Place'));
        await tester.pump();
        final canvas = find.byKey(const Key('level-canvas'));
        await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 30));
        await tester.pump();
        expect(find.byKey(const Key('dirty-marker')), findsOneWidget);

        await tester.tap(find.byKey(const Key('save')));
        await tester.pump();

        expect(find.byKey(const Key('dirty-marker')), findsNothing);
        final saved =
            jsonDecode(File(levelPath()).readAsStringSync())
                as Map<String, dynamic>;
        expect(
          (saved['entities'] as List).length,
          2,
          reason: 'the placed entity is on disk',
        );
      },
    );

    testWidgets('a level with no edits has nothing to save', (tester) async {
      writeLevel();
      await tester.pumpWidget(
        MaterialApp(
          home: LevelScreen(levelPath: levelPath(), autosaveInterval: null),
        ),
      );
      final save = tester.widget<IconButton>(find.byKey(const Key('save')));
      expect(save.onPressed, isNull);
    });
  });
}
