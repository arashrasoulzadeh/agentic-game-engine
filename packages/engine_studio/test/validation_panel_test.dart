import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _levelWithProblem() => {
  'entities': [
    {
      'name': 'door',
      'components': {
        'position': {'x': 10.0, 'y': 10.0},
      },
    },
    {
      'name': 'crate',
      'components': {
        'pushable': {'pushSpeed': -1.0},
      },
    },
  ],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('validation_panel'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('the panel counts the problems in the level', (tester) async {
    final path = '${dir.path}/level.json';
    File(path).writeAsStringSync(jsonEncode(_levelWithProblem()));
    await tester.pumpWidget(
      MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
    );

    expect(find.text('Problems: 1 error(s), 0 warning(s)'), findsOneWidget);
  });

  testWidgets('clicking a problem selects the entity it belongs to', (
    tester,
  ) async {
    final path = '${dir.path}/level.json';
    File(path).writeAsStringSync(jsonEncode(_levelWithProblem()));
    await tester.pumpWidget(
      MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
    );

    await tester.tap(find.text('Problems: 1 error(s), 0 warning(s)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('problem-0')));
    await tester.pump();

    expect(find.text('Selected: crate'), findsOneWidget);
  });

  testWidgets('a clean level says it has no problems', (tester) async {
    final path = '${dir.path}/clean.json';
    File(path).writeAsStringSync(
      jsonEncode({
        'entities': [
          {
            'name': 'door',
            'components': {
              'position': {'x': 1.0, 'y': 1.0},
            },
          },
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
    );
    expect(find.text('No problems'), findsOneWidget);
  });
}
