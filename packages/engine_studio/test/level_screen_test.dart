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
      },
    },
  ],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('level_screen'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String contents) {
    final file = File('${dir.path}/$name')..writeAsStringSync(contents);
    return file.path;
  }

  testWidgets('draws the canvas and asks for a selection before any tap', (
    tester,
  ) async {
    final path = write('level.json', jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

    expect(find.byKey(const Key('level-canvas')), findsOneWidget);
    expect(find.text('Tap an entity to select it.'), findsOneWidget);
  });

  testWidgets('tapping an entity marker selects it by name', (tester) async {
    final path = write('level.json', jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

    // The canvas is drawn at its own origin, so the player at world (24, 8) is
    // at the same offset within the canvas. Tap there.
    final canvas = find.byKey(const Key('level-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(24, 8));
    await tester.pump();

    expect(find.text('Selected: player'), findsOneWidget);
  });

  testWidgets('a tap on empty space clears the selection', (tester) async {
    final path = write('level.json', jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

    final canvas = find.byKey(const Key('level-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(24, 8));
    await tester.pump();
    expect(find.text('Selected: player'), findsOneWidget);

    // Well away from the map origin (0, 0) and the player (24, 8), so no entity
    // is within the pick radius.
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 28));
    await tester.pump();
    expect(find.text('Tap an entity to select it.'), findsOneWidget);
  });

  testWidgets('a level that cannot be read shows its error, not a crash', (
    tester,
  ) async {
    final path = write('broken.json', '{ not json');
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

    expect(find.byKey(const Key('level-error')), findsOneWidget);
    expect(find.textContaining('Could not open'), findsOneWidget);
  });

  testWidgets(
    'the place tool adds an entity where the canvas is tapped, and undo removes it',
    (tester) async {
      final path = write('level.json', jsonEncode(_level()));
      await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

      await tester.tap(find.text('Place'));
      await tester.pump();
      final canvas = find.byKey(const Key('level-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(100, 60));
      await tester.pump();

      final status = tester
          .widget<Text>(find.byKey(const Key('selection-status')))
          .data;
      expect(status, 'Selected: entity 3');
      final undo = tester.widget<IconButton>(find.byKey(const Key('undo')));
      expect(undo.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('undo')));
      await tester.pump();
      expect(find.text('Tap an entity to select it.'), findsOneWidget);
    },
  );

  testWidgets('undo and redo are disabled until there is something to undo', (
    tester,
  ) async {
    final path = write('level.json', jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));

    final undo = tester.widget<IconButton>(find.byKey(const Key('undo')));
    final redo = tester.widget<IconButton>(find.byKey(const Key('redo')));
    expect(undo.onPressed, isNull);
    expect(redo.onPressed, isNull);
  });

  testWidgets('the delete button is disabled until an entity is selected', (
    tester,
  ) async {
    final path = write('level.json', jsonEncode(_level()));
    await tester.pumpWidget(MaterialApp(home: LevelScreen(levelPath: path)));
    final button = tester.widget<IconButton>(
      find.byKey(const Key('delete-selected')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'the preview scrolls horizontally and vertically when the level is larger than the view',
    (tester) async {
      final big = {
        'entities': [
          {
            'name': 'far',
            'components': {
              'position': {'x': 900.0, 'y': 700.0},
            },
          },
        ],
      };
      final path = write('big.json', jsonEncode(big));
      await tester.pumpWidget(
        MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
      );

      final scrollables = find.ancestor(
        of: find.byKey(const Key('level-canvas')),
        matching: find.byType(Scrollable),
      );
      final states = tester.stateList<ScrollableState>(scrollables).toList();
      expect(
        states.map((s) => s.widget.axis),
        containsAll([Axis.vertical, Axis.horizontal]),
      );
      for (final state in states) {
        expect(
          state.position.maxScrollExtent,
          greaterThan(0),
          reason: 'the ${state.widget.axis} view has somewhere to scroll',
        );
      }
    },
  );
}
