import 'dart:convert';
import 'dart:io';

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
  setUp(() => dir = Directory.systemTemp.createTempSync('entity_palette'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets(
    'picking a component then tapping the canvas places an entity carrying its template',
    (tester) async {
      final path = '${dir.path}/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      await tester.pumpWidget(
        MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
      );

      await tester.enterText(
        find.byKey(const Key('palette-search')),
        'pushable',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('palette-pushable')));
      await tester.pump();
      final canvas = find.byKey(const Key('level-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 30));
      await tester.pump();

      expect(find.text('Selected: entity 2'), findsOneWidget);
      expect(find.byKey(const Key('component-pushable')), findsOneWidget);
      expect(find.byKey(const Key('field-pushable.pushSpeed')), findsOneWidget);
    },
  );

  testWidgets('the search box narrows the components offered', (tester) async {
    final path = '${dir.path}/level.json';
    File(path).writeAsStringSync(jsonEncode(_level()));
    await tester.pumpWidget(
      MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
    );

    await tester.enterText(find.byKey(const Key('palette-search')), 'pushable');
    await tester.pump();

    expect(find.byKey(const Key('palette-pushable')), findsOneWidget);
    expect(find.byKey(const Key('palette-tween')), findsNothing);
  });
}
