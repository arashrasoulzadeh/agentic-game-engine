import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

import '../project/studio_project.dart';

/// The snapshot file play-test writes into a project's levels folder. The game
/// loads it when started with `--dart-define=PLAYTEST_LEVEL=<this name>`.
const playtestLevelFile = 'playtest.level.json';

/// Where a play-test's output is kept, inside the project's `.studio` folder.
const playtestLogFile = 'playtest.log';

/// The `flutter run` arguments that start a game on a play-test snapshot. Pure, so
/// the exact command is tested without launching anything.
List<String> playTestArguments({required String device}) => [
  'run',
  '-d',
  device,
  '--dart-define=PLAYTEST_LEVEL=$playtestLevelFile',
];

/// Starts a process. Injected so tests can record the command instead of running it.
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// Runs the level being edited inside the game, as a separate process, so a game
/// crash cannot take the editor down (ADR 0003).
///
/// The snapshot is the in-memory document, edits included, not the saved file: a
/// designer tries the level they are looking at, even before saving it.
class PlayTest {
  /// The Flutter command. Apps launched from Finder do not inherit the shell's
  /// PATH, so this may need to be an absolute path to the SDK.
  final String flutter;

  /// The device the game runs on, for example `macos`.
  final String device;

  final ProcessStarter _start;

  PlayTest({
    this.flutter = 'flutter',
    this.device = 'macos',
    ProcessStarter? start,
  }) : _start = start ?? _defaultStart;

  static Future<Process> _defaultStart(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) =>
      Process.start(executable, arguments, workingDirectory: workingDirectory);

  /// Writes [document] as the project's play-test snapshot and starts the game on
  /// it. Returns the started process.
  Future<Process> launch(StudioProject project, LevelDocument document) async {
    final snapshot = File(
      p.join(project.root, 'assets', 'levels', playtestLevelFile),
    );
    snapshot.createSync(recursive: true);
    snapshot.writeAsStringSync(encodeLevelJson(document.toJson()));
    final process = await _start(
      flutter,
      playTestArguments(device: device),
      workingDirectory: project.root,
    );
    _capture(process, project);
    return process;
  }

  /// Writes the game's output to `.studio/playtest.log`, so a play-test that exits
  /// straight away leaves its reason behind for the designer to read. Each run
  /// starts the log afresh.
  static void _capture(Process process, StudioProject project) {
    final log = File(p.join(project.root, '.studio', playtestLogFile))
      ..createSync(recursive: true)
      ..writeAsStringSync('');
    final sink = log.openWrite(mode: FileMode.append);
    process.stdout.listen(sink.add, onDone: () {});
    process.stderr.listen(sink.add, onDone: () {});
    process.exitCode.then((code) {
      sink
        ..writeln('\n[play-test exited with code $code]')
        ..close();
    });
  }
}
