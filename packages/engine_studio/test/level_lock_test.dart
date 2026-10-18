import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_io.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String level;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('level_lock');
    level = '${dir.path}/assets/levels/one.level.json';
    File(level)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'entities': [
            {
              'name': 'player',
              'components': {
                'position': {'x': 24.0, 'y': 8.0},
              },
            },
          ],
        }),
      );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // The project app bar (with Run game) needs a desktop-sized window.
  Future<void> open(
    WidgetTester tester, {
    String? root,
    String as = 'ann@laptop',
  }) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: LevelScreen(
          levelPath: level,
          projectRoot: root,
          autosaveInterval: null,
          lockedAs: as,
        ),
      ),
    );
  }

  Future<void> dirty(WidgetTester tester) async {
    await tester.tap(find.text('Place'));
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('level-canvas'))) +
          const Offset(40, 30),
    );
    await tester.pump();
  }

  testWidgets('opening a level in a project locks it; closing releases it', (
    tester,
  ) async {
    await open(tester, root: dir.path);
    expect(FileLock(level).inspect()!.owner, 'ann@laptop');
    expect(find.byKey(const Key('level-locked')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    expect(FileLock(level).inspect(), isNull, reason: 'released on close');
  });

  testWidgets(
    'a level held by someone else is view-only, with a banner naming them',
    (tester) async {
      FileLock(level).acquire('bob@desktop');
      await open(tester, root: dir.path);

      expect(find.byKey(const Key('level-locked')), findsOneWidget);
      expect(find.textContaining('bob@desktop'), findsOneWidget);

      final before = File(level).readAsStringSync();
      await dirty(tester);
      final save = tester.widget<IconButton>(find.byKey(const Key('save')));
      expect(save.onPressed, isNull, reason: 'dirty, but saving is off');
      expect(File(level).readAsStringSync(), before);

      await tester.pumpWidget(const SizedBox());
      expect(
        FileLock(level).inspect()!.owner,
        'bob@desktop',
        reason: 'we never held it, so we do not release it',
      );
    },
  );

  testWidgets('Take over replaces the holder and re-enables saving', (
    tester,
  ) async {
    FileLock(level).acquire('bob@desktop');
    await open(tester, root: dir.path);
    await dirty(tester);

    await tester.tap(find.byKey(const Key('lock-take-over')));
    await tester.pump();

    expect(find.byKey(const Key('level-locked')), findsNothing);
    expect(FileLock(level).inspect()!.owner, 'ann@laptop');
    final save = tester.widget<IconButton>(find.byKey(const Key('save')));
    expect(save.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(FileLock(level).inspect(), isNull);
  });

  testWidgets('a level opened without a project is not locked', (tester) async {
    await open(tester);
    expect(File('$level.lock').existsSync(), isFalse);
  });

  testWidgets('re-opening your own level (a crashed session) is not blocked', (
    tester,
  ) async {
    FileLock(level).acquire('ann@laptop');
    await open(tester, root: dir.path);
    expect(find.byKey(const Key('level-locked')), findsNothing);
  });

  testWidgets(
    'a narrow window shortens the title instead of overflowing the app bar',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: LevelScreen(
            levelPath: level,
            projectRoot: dir.path,
            autosaveInterval: null,
            lockedAs: 'ann@a',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
