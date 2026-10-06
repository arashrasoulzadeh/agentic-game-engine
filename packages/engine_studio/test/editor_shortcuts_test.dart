import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/level/editor_shortcuts.dart';
import 'package:engine_studio/src/level/level_editor.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  group('shortcutFor', () {
    ShortcutResult? press(
      LogicalKeyboardKey key, {
      bool command = false,
      bool shift = false,
    }) => shortcutFor(key, command: command, shift: shift);

    test('Cmd or Ctrl with Z undoes, and with Shift redoes', () {
      expect(
        press(LogicalKeyboardKey.keyZ, command: true)?.action,
        EditorAction.undo,
      );
      expect(
        press(LogicalKeyboardKey.keyZ, command: true, shift: true)?.action,
        EditorAction.redo,
      );
      expect(
        press(LogicalKeyboardKey.keyY, command: true)?.action,
        EditorAction.redo,
      );
    });

    test('Cmd or Ctrl with S saves and with G toggles the grid', () {
      expect(
        press(LogicalKeyboardKey.keyS, command: true)?.action,
        EditorAction.save,
      );
      expect(
        press(LogicalKeyboardKey.keyG, command: true)?.action,
        EditorAction.toggleGrid,
      );
    });

    test('Delete and Backspace delete the selection', () {
      expect(
        press(LogicalKeyboardKey.delete)?.action,
        EditorAction.deleteSelected,
      );
      expect(
        press(LogicalKeyboardKey.backspace)?.action,
        EditorAction.deleteSelected,
      );
    });

    test('bare letters select tools', () {
      expect(press(LogicalKeyboardKey.keyV)?.tool, EditorTool.select);
      expect(press(LogicalKeyboardKey.keyM)?.tool, EditorTool.move);
      expect(press(LogicalKeyboardKey.keyB)?.tool, EditorTool.paintTile);
      expect(press(LogicalKeyboardKey.keyE)?.tool, EditorTool.eraseTile);
      expect(press(LogicalKeyboardKey.keyF)?.tool, EditorTool.fill);
      expect(press(LogicalKeyboardKey.keyP)?.tool, EditorTool.placeEntity);
    });

    test('a key with no meaning here does nothing', () {
      expect(press(LogicalKeyboardKey.keyQ), isNull);
      expect(press(LogicalKeyboardKey.keyQ, command: true), isNull);
    });

    test(
      'a tool letter with Cmd is not a tool, so Cmd+B cannot switch tools',
      () {
        expect(press(LogicalKeyboardKey.keyB, command: true), isNull);
      },
    );
  });

  group('screen keys', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('shortcuts_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pumpLevel(WidgetTester tester) async {
      final path = '${dir.path}/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      await tester.pumpWidget(
        MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
      );
    }

    SegmentedButton<EditorTool> toolBar(WidgetTester tester) => tester
        .widget<SegmentedButton<EditorTool>>(find.byKey(const Key('tool-bar')));

    testWidgets('the P key selects the place tool', (tester) async {
      await pumpLevel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(toolBar(tester).selected, {EditorTool.placeEntity});
    });

    testWidgets('Ctrl+Z undoes the last edit', (tester) async {
      await pumpLevel(tester);
      await tester.tap(find.text('Place'));
      await tester.pump();
      final canvas = find.byKey(const Key('level-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 30));
      await tester.pump();
      expect(find.byKey(const Key('dirty-marker')), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byKey(const Key('dirty-marker')), findsNothing);
    });

    testWidgets('typing a tool letter in the inspector does not switch tools', (
      tester,
    ) async {
      await pumpLevel(tester);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('level-canvas'))) +
            const Offset(24, 8),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('field-position.x')));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(
        toolBar(tester).selected,
        {EditorTool.select},
        reason: 'the P went into the field, not to the tool shortcut',
      );
    });
  });
}
