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
        expect(recorder.arguments, playTestArguments(device: 'macos'));
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

  group('play-test button', () {
    testWidgets('starts the game on the level from its project', (
      tester,
    ) async {
      final recorder = _Recorder();
      final path = '${root.path}/assets/levels/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));

      await tester.pumpWidget(
        MaterialApp(
          home: LevelScreen(
            levelPath: path,
            projectRoot: root.path,
            autosaveInterval: null,
            playTest: PlayTest(start: recorder.start),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('playtest')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(recorder.workingDirectory, root.path);
      expect(find.text('Play-test started.'), findsOneWidget);
    });

    testWidgets(
      'a level outside a project says so instead of starting anything',
      (tester) async {
        final recorder = _Recorder();
        final path = '${root.path}/assets/levels/level.json';
        File(path).writeAsStringSync(jsonEncode(_level()));

        await tester.pumpWidget(
          MaterialApp(
            home: LevelScreen(
              levelPath: path,
              autosaveInterval: null,
              playTest: PlayTest(start: recorder.start),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('playtest')));
        await tester.pump();

        expect(recorder.executable, isNull);
        expect(
          find.text('Open the level from a project to play-test it.'),
          findsOneWidget,
        );
      },
    );
  });
}
