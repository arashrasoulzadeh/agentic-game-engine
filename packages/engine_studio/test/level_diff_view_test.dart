import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/diff/level_diff_view.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _doc(List<Map<String, dynamic>> entities) =>
    LevelDocument.fromJson({'entities': entities});

Map<String, dynamic> _e(String name, Map<String, dynamic> components) => {
  'name': name,
  'components': components,
};

void main() {
  testWidgets(
    'shows added, removed, and per-field changes with old and new values',
    (tester) async {
      final before = _doc([
        _e('player', {
          'position': {'x': 1.0, 'y': 2.0},
          'health': {'current': 5},
        }),
        _e('old_crate', {
          'position': {'x': 0.0, 'y': 0.0},
        }),
      ]);
      final after = _doc([
        _e('player', {
          'position': {'x': 9.0, 'y': 2.0},
        }),
        _e('new_coin', {
          'position': {'x': 3.0, 'y': 3.0},
        }),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LevelDiffView(diff: diffLevels(before, after))),
        ),
      );
      expect(find.byKey(const Key('diff-added-new_coin')), findsOneWidget);
      expect(find.byKey(const Key('diff-removed-old_crate')), findsOneWidget);
      expect(
        find.byKey(const Key('diff-comp-removed-player.health')),
        findsOneWidget,
      );
      expect(find.text('player.position.x: 1.0 → 9.0'), findsOneWidget);
      expect(
        find.byKey(const Key('diff-field-player.position.y')),
        findsNothing,
        reason: 'unchanged fields are not listed',
      );
    },
  );

  testWidgets('identical levels say there are no differences', (tester) async {
    final d = _doc([
      _e('a', {
        'position': {'x': 1.0, 'y': 1.0},
      }),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LevelDiffView(diff: diffLevels(d, d))),
      ),
    );
    expect(find.byKey(const Key('diff-empty')), findsOneWidget);
  });

  group('level screen', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('level_changes'));
    tearDown(() => root.deleteSync(recursive: true));

    testWidgets(
      'the Changes button is off until there is something to save, then compares with the file',
      (tester) async {
        final path = '${root.path}/level.json';
        File(path).writeAsStringSync(
          jsonEncode({
            'entities': [
              _e('player', {
                'position': {'x': 24.0, 'y': 8.0},
              }),
            ],
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LevelScreen(levelPath: path, autosaveInterval: null),
          ),
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('show-changes')))
              .onPressed,
          isNull,
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

        await tester.tap(find.byKey(const Key('show-changes')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('changes-dialog')), findsOneWidget);
        expect(find.textContaining('Added'), findsOneWidget);
      },
    );
  });
}
