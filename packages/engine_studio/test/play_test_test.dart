import 'dart:async';
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

/// A process that stays "running" until killed, so tests can see stop() act on it.
class _LongProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(143);
    return true;
  }

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 1;
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

  group('devices and stopping', () {
    test('parseFlutterDevices reads the machine output and tolerates junk', () {
      expect(
        parseFlutterDevices(
          '[{"id":"macos","name":"macOS"},{"id":"emulator-5554"},{"name":"no id"},7]',
        ),
        [
          const PlayTestDevice('macos', 'macOS'),
          const PlayTestDevice('emulator-5554', 'emulator-5554'),
        ],
      );
      expect(parseFlutterDevices('not json'), isEmpty);
      expect(parseFlutterDevices('{"a":1}'), isEmpty);
    });

    test(
      'listDevices uses the injected runner, and a missing SDK means no devices',
      () async {
        String? ran;
        final ok = PlayTest(
          run: (exe, args) async {
            ran = '$exe ${args.join(' ')}';
            return '[{"id":"chrome","name":"Chrome"}]';
          },
        );
        expect((await ok.listDevices()).single.id, 'chrome');
        expect(ran, 'flutter devices --machine');
        final broken = PlayTest(
          run: (exe, args) async => throw const ProcessException('flutter', []),
        );
        expect(await broken.listDevices(), isEmpty);
      },
    );

    test(
      'stop kills the running game, and a relaunch replaces the old one',
      () async {
        final procs = <_LongProcess>[];
        final pt = PlayTest(
          start: (e, a, {required workingDirectory}) async {
            final p = _LongProcess();
            procs.add(p);
            return p;
          },
        );
        final project = StudioProject.open(root.path);
        final doc = LevelDocument.fromJson(_level());
        await pt.launch(project, doc);
        expect(pt.isRunning, isTrue);
        await pt.launch(project, doc);
        expect(
          procs.first.killed,
          isTrue,
          reason: 'the first game must not be left running',
        );
        expect(pt.isRunning, isTrue);
        pt.stop();
        expect(procs.last.killed, isTrue);
        expect(pt.isRunning, isFalse);
        pt.stop();
      },
    );

    test('a game that exits by itself is no longer running', () async {
      final p = _LongProcess();
      final pt = PlayTest(
        start: (e, a, {required workingDirectory}) async => p,
      );
      await pt.launch(
        StudioProject.open(root.path),
        LevelDocument.fromJson(_level()),
      );
      expect(pt.isRunning, isTrue);
      p.kill();
      await Future<void>.delayed(Duration.zero);
      expect(pt.isRunning, isFalse);
    });

    test('the device in use appears in the launch arguments', () async {
      final recorder = _Recorder();
      final pt = PlayTest(start: recorder.start, device: 'macos');
      pt.device = 'chrome';
      await pt.launch(
        StudioProject.open(root.path),
        LevelDocument.fromJson(_level()),
      );
      expect(recorder.arguments, contains('chrome'));
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

    testWidgets(
      'the button turns into stop while the game runs, and choosing a device changes the target',
      (tester) async {
        final path = '${root.path}/assets/levels/level.json';
        File(path).writeAsStringSync(jsonEncode(_level()));
        final proc = _LongProcess();
        final pt = PlayTest(
          start: (e, a, {required workingDirectory}) async => proc,
          run: (e, a) async =>
              '[{"id":"chrome","name":"Chrome"},{"id":"macos","name":"macOS"}]',
        );
        await open(tester, path, pt, projectRoot: root.path);

        await tester.tap(find.byKey(const Key('game-device')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('device-chrome')));
        await tester.pumpAndSettle();
        expect(pt.device, 'chrome');

        await tester.tap(find.byKey(const Key('run-game')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        expect(find.byKey(const Key('stop-game')), findsOneWidget);
        expect(find.byKey(const Key('run-game')), findsNothing);

        await tester.tap(find.byKey(const Key('stop-game')));
        await tester.pump();
        expect(proc.killed, isTrue);
        expect(find.byKey(const Key('run-game')), findsOneWidget);
      },
    );

    testWidgets('closing the editor stops the game it started', (tester) async {
      final path = '${root.path}/assets/levels/level.json';
      File(path).writeAsStringSync(jsonEncode(_level()));
      final proc = _LongProcess();
      final pt = PlayTest(
        start: (e, a, {required workingDirectory}) async => proc,
      );
      await open(tester, path, pt, projectRoot: root.path);
      await tester.tap(find.byKey(const Key('run-game')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(proc.killed, isTrue);
    });

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
