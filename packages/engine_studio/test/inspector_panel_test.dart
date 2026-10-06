import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _level() => {
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['..#', '###'],
        },
      },
    },
    {
      'name': 'player',
      'components': {
        'position': {'x': 24.0, 'y': 8.0},
        'pushable': {'pushSpeed': 2.5},
      },
    },
  ],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('inspector_panel'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> selectPlayer(WidgetTester tester) async {
    final canvas = find.byKey(const Key('level-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(24, 8));
    await tester.pump();
  }

  testWidgets('selecting an entity shows its components and their fields', (
    tester,
  ) async {
    final path = '${dir.path}/level.json';
    File(path).writeAsStringSync(jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));
    await selectPlayer(tester);

    expect(find.byKey(const Key('component-position')), findsOneWidget);
    expect(find.byKey(const Key('field-position.x')), findsOneWidget);
    expect(find.byKey(const Key('field-pushable.pushSpeed')), findsOneWidget);
  });

  testWidgets('submitting a valid number changes the document', (tester) async {
    final path = '${dir.path}/level.json';
    File(path).writeAsStringSync(jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));
    await selectPlayer(tester);

    await tester.enterText(find.byKey(const Key('field-position.x')), '55');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final saved = jsonDecode(File(path).readAsStringSync());
    expect(
      saved,
      _level(),
      reason: 'nothing is saved until the save command exists',
    );
    final undo = tester.widget<IconButton>(find.byKey(const Key('undo')));
    expect(
      undo.onPressed,
      isNotNull,
      reason: 'the edit is in the undo history',
    );
  });

  testWidgets(
    'an unparseable value shows its message under the field and changes nothing',
    (tester) async {
      final path = '${dir.path}/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));
      await selectPlayer(tester);

      await tester.enterText(find.byKey(const Key('field-position.x')), 'left');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.byKey(const Key('error-position.x')), findsOneWidget);
      expect(find.text('x must be a number'), findsOneWidget);
      final undo = tester.widget<IconButton>(find.byKey(const Key('undo')));
      expect(
        undo.onPressed,
        isNull,
        reason: 'a rejected value records no edit',
      );
    },
  );
}
