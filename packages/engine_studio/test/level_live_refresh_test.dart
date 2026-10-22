import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _level(List<String> names) => {
  'entities': [
    for (final n in names)
      {
        'name': n,
        'components': {
          'position': {'x': 24.0, 'y': 8.0},
        },
      },
  ],
};

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('live_refresh');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    path = '${root.path}/assets/levels/level.json';
    File(path).writeAsStringSync(jsonEncode(_level(['player'])));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: LevelScreen(
        levelPath: path,
        projectRoot: root.path,
        autosaveInterval: null,
        watchInterval: const Duration(milliseconds: 200),
      ),
    ),
  );

  /// Writes the file with a clearly different modification time, as another person's save would.
  Future<void> someoneElseSaves(WidgetTester tester, List<String> names) async {
    final file = File(path)..writeAsStringSync(jsonEncode(_level(names)));
    file.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  }

  Future<void> addEntityLocally(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('palette-search')), 'pushable');
    await tester.pump();
    await tester.tap(find.byKey(const Key('palette-pushable')));
    await tester.pump();
    final canvas = find.byKey(const Key('level-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 30));
    await tester.pump();
  }

  testWidgets('a clean editor reloads silently when someone else saves', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('level-reloaded')), findsNothing);

    await someoneElseSaves(tester, ['player', 'boss']);
    expect(find.byKey(const Key('level-reloaded')), findsOneWidget);
    expect(find.byKey(const Key('level-changed-on-disk')), findsNothing);
  });

  testWidgets(
    'with unsaved edits it asks instead, and Keep leaves them alone',
    (tester) async {
      await open(tester);
      await addEntityLocally(tester);

      await someoneElseSaves(tester, ['player', 'boss']);
      expect(find.byKey(const Key('level-changed-on-disk')), findsOneWidget);
      expect(
        find.byKey(const Key('level-reloaded')),
        findsNothing,
        reason: 'nothing was replaced',
      );

      await tester.tap(find.byKey(const Key('disk-keep')));
      await tester.pump();
      expect(find.byKey(const Key('level-changed-on-disk')), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('level-changed-on-disk')),
        findsNothing,
        reason: 'not nagged again for the same change',
      );
    },
  );

  testWidgets('Reload discards the local edits and takes the file', (
    tester,
  ) async {
    await open(tester);
    await addEntityLocally(tester);
    await someoneElseSaves(tester, ['player', 'boss']);

    await tester.tap(find.byKey(const Key('disk-reload')));
    await tester.pump();
    expect(find.byKey(const Key('level-changed-on-disk')), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('save'))).onPressed,
      isNull,
      reason: 'the reloaded document is clean',
    );
  });

  testWidgets('our own save does not look like someone else\'s', (
    tester,
  ) async {
    await open(tester);
    await addEntityLocally(tester);
    await tester.tap(find.byKey(const Key('save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('level-reloaded')), findsNothing);
    expect(find.byKey(const Key('level-changed-on-disk')), findsNothing);
  });

  testWidgets('a half-written file is ignored until it parses', (tester) async {
    await open(tester);
    File(path).writeAsStringSync('{"entities": [');
    File(
      path,
    ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(
      find.byKey(const Key('level-canvas')),
      findsOneWidget,
      reason: 'the editor survives',
    );
    expect(find.byKey(const Key('level-reloaded')), findsNothing);
  });
}
