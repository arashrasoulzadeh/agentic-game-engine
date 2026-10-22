import 'dart:convert';
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
///
/// [assetDir] is the project's `assets` folder. Passing it as `ASSET_DIR` makes the
/// game read levels from disk and watch them, so saving a level in the studio updates
/// the running game without a restart.
List<String> playTestArguments({required String device, String? assetDir}) => [
  'run',
  '-d',
  device,
  '--dart-define=PLAYTEST_LEVEL=$playtestLevelFile',
  if (assetDir != null) '--dart-define=ASSET_DIR=$assetDir',
];

/// Starts a process. Injected so tests can record the command instead of running it.
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

/// A device `flutter run` can target.
class PlayTestDevice {
  final String id;
  final String name;
  const PlayTestDevice(this.id, this.name);

  @override
  bool operator ==(Object other) =>
      other is PlayTestDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Parses the output of `flutter devices --machine`. Anything that is not a JSON list of objects with an `id`
/// yields no devices rather than an error: a missing or broken SDK just means an empty choice list.
List<PlayTestDevice> parseFlutterDevices(String machineOutput) {
  try {
    final decoded = jsonDecode(machineOutput);
    if (decoded is! List) return const [];
    return [
      for (final d in decoded)
        if (d is Map && d['id'] is String)
          PlayTestDevice(
            d['id'] as String,
            (d['name'] as String?) ?? d['id'] as String,
          ),
    ];
  } on FormatException {
    return const [];
  }
}

/// Runs a command to completion and returns its standard output. Injected so tests need no Flutter SDK.
typedef ProcessRunner =
    Future<String> Function(String executable, List<String> arguments);

/// Runs the level being edited inside the game, as a separate process, so a game
/// crash cannot take the editor down (ADR 0003).
///
/// The snapshot is the in-memory document, edits included, not the saved file: a
/// designer tries the level they are looking at, even before saving it.
class PlayTest {
  /// The Flutter command. Apps launched from Finder do not inherit the shell's
  /// PATH, so this may need to be an absolute path to the SDK.
  final String flutter;

  /// The device the game runs on, for example `macos`. Change it between launches (see [listDevices]).
  String device;

  final ProcessStarter _start;
  final ProcessRunner _run;
  Process? _process;

  PlayTest({
    this.flutter = 'flutter',
    this.device = 'macos',
    ProcessStarter? start,
    ProcessRunner? run,
  }) : _start = start ?? _defaultStart,
       _run = run ?? _defaultRun;

  static Future<String> _defaultRun(
    String executable,
    List<String> arguments,
  ) async => (await Process.run(executable, arguments)).stdout as String;

  /// Whether a launched game is still running.
  bool get isRunning => _process != null;

  /// The devices `flutter devices` reports, or none if the SDK cannot be run.
  Future<List<PlayTestDevice>> listDevices() async {
    try {
      return parseFlutterDevices(await _run(flutter, ['devices', '--machine']));
    } on Object {
      return const [];
    }
  }

  /// Stops the running game, if any. Safe to call when nothing runs.
  void stop() {
    final process = _process;
    _process = null;
    process?.kill();
  }

  static Future<Process> _defaultStart(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) =>
      Process.start(executable, arguments, workingDirectory: workingDirectory);

  /// Writes [document] as the project's play-test snapshot and starts the game on
  /// it. Returns the started process.
  Future<Process> launch(StudioProject project, LevelDocument document) async {
    stop();
    final snapshot = File(
      p.join(project.root, 'assets', 'levels', playtestLevelFile),
    );
    snapshot.createSync(recursive: true);
    snapshot.writeAsStringSync(encodeLevelJson(document.toJson()));
    final process = await _start(
      flutter,
      playTestArguments(
        device: device,
        assetDir: p.join(project.root, 'assets'),
      ),
      workingDirectory: project.root,
    );
    _process = process;
    process.exitCode.then((_) {
      if (identical(_process, process)) _process = null;
    });
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
