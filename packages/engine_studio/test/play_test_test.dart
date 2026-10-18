import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:engine_studio/src/playtest/play_test.dart';
import 'package:engine_studio/src/project/studio_project.dart';
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

/// A starter that records what it was asked to run and returns a harmless real
/// process, since play-test needs a Process back.
class _Recorder {
  String? executable;
  List<String>? arguments;
  String? workingDirectory;

  Future<Process> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    return Process.start('true', []);
  }
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('play_test');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('playTestArguments', () {
    test('runs the game on the device with the snapshot define', () {
      expect(playTestArguments(device: 'macos'), [
        'run',
        '-d',
        'macos',
        '--dart-define=PLAYTEST_LEVEL=playtest.level.json',
      ]);
    });

    test('an asset dir turns on hot reload in the game', () {
      expect(
        playTestArguments(device: 'macos', assetDir: '/p/assets'),
        contains('--dart-define=ASSET_DIR=/p/assets'),
      );
    });
  });

  group('PlayTest.launch', () {
    test(
      'writes the in-memory level as the snapshot and starts the game in the project',
      () async {
        final recorder = _Recorder();
        final doc = LevelDocument.fromJson(_level())
          ..entities.first.components['position'] = {'x': 99.0, 'y': 1.0};

        await PlayTest(
          flutter: '/sdk/bin/flutter',
          start: recorder.start,
        ).launch(StudioProject.open(root.path), doc);

        final snapshot = File('${root.path}/assets/levels/$playtestLevelFile');
        expect(snapshot.existsSync(), isTrue);
        expect(
          jsonDecode(snapshot.readAsStringSync()),
          doc.toJson(),
          reason: 'the unsaved edit is in the snapshot',
        );
        expect(recorder.executable, '/sdk/bin/flutter');
        expect(
          recorder.arguments,
          playTestArguments(device: 'macos', assetDir: '${root.path}/assets'),
        );
        expect(recorder.workingDirectory, root.path);
      },
    );

    test('the snapshot is not listed as a level of the project', () async {
      final recorder = _Recorder();
      await PlayTest(
        start: recorder.start,
      ).launch(StudioProject.open(root.path), LevelDocument.fromJson(_level()));
      File(
        '${root.path}/assets/levels/real.json',
      ).writeAsStringSync('{"entities":[]}');

      expect(StudioProject.open(root.path).levelPaths(), [
        'assets/levels/real.json',
      ]);
    });
  });

  group('play button', () {
    testWidgets(
      'switches to the Preview mode and runs the level in the engine',
      (tester) async {
        final path = '${root.path}/assets/levels/level.json';
        File(path).writeAsStringSync(jsonEncode(_level()));

        await tester.pumpWidget(
          MaterialApp(
            home: LevelScreen(
              levelPath: path,
              projectRoot: root.path,
              autosaveInterval: null,
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('playtest')));
        await tester.pump();

        expect(find.byKey(const Key('preview-canvas')), findsOneWidget);
        final switcher = tester.widget<SegmentedButton<bool>>(
          find.byKey(const Key('mode-switch')),
        );
        expect(switcher.selected, {true});
      },
    );

    testWidgets('the Edit mode brings the editing canvas back', (tester) async {
      final path = '${root.path}/assets/levels/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));

      await tester.pumpWidget(
        MaterialApp(home: LevelScreen(levelPath: path, autosaveInterval: null)),
      );
      await tester.tap(find.byKey(const Key('playtest')));
      await tester.pump();
      await tester.tap(find.text('Edit'));
      await tester.pump();

      expect(find.byKey(const Key('level-canvas')), findsOneWidget);
      expect(find.byKey(const Key('preview-canvas')), findsNothing);
    });
  });

  group('run game button', () {
    Future<void> open(
      WidgetTester tester,
      String path,
      PlayTest? pt, {
      String? projectRoot,
    }) => tester.pumpWidget(
      MaterialApp(
        home: LevelScreen(
          levelPath: path,
          projectRoot: projectRoot,
          autosaveInterval: null,
          playTest: pt,
        ),
      ),
    );

    testWidgets(
      'starts the game on the unsaved level and says where the log is',
      (tester) async {
        final path = '${root.path}/assets/levels/level.json';
        File(path).writeAsStringSync(jsonEncode(_level()));
        final recorder = _Recorder();
        await open(
          tester,
          path,
          PlayTest(start: recorder.start),
          projectRoot: root.path,
        );

        await tester.tap(find.byKey(const Key('run-game')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

        expect(recorder.workingDirectory, root.path);
        expect(
          recorder.arguments,
          playTestArguments(device: 'macos', assetDir: '${root.path}/assets'),
        );
        expect(
          File('${root.path}/assets/levels/$playtestLevelFile').existsSync(),
          isTrue,
        );
        expect(find.byKey(const Key('run-game-started')), findsOneWidget);
      },
    );

    testWidgets('a launcher failure is shown, not thrown', (tester) async {
      final path = '${root.path}/assets/levels/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      final broken = PlayTest(
        start: (exe, args, {required workingDirectory}) async =>
            throw const ProcessException('flutter', [], 'not found'),
      );
      await open(tester, path, broken, projectRoot: root.path);

      await tester.tap(find.byKey(const Key('run-game')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.byKey(const Key('run-game-failed')), findsOneWidget);
      expect(find.textContaining('not found'), findsOneWidget);
    });

    testWidgets('a level outside any project has no Run game button', (
      tester,
    ) async {
      final path = '${root.path}/assets/levels/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      await open(tester, path, null);
      expect(find.byKey(const Key('run-game')), findsNothing);
    });
  });
}
