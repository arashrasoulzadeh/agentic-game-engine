import 'dart:io';

import 'package:args/command_runner.dart';

import 'process_utils.dart';

/// Every self-referencing engine package `CreateCommand`'s template can
/// write into a generated project's pubspec.yaml — currently
/// `engine_core` and `engine_flutter` always, `engine_platformer` too
/// now that the template depends on it. Keep in sync with
/// `templates/default_game/pubspec.yaml.tmpl`'s dependency block.
const _enginePackageNames = ['engine_core', 'engine_flutter', 'engine_platformer'];

/// Matches one engine package's git-dependency block (name from
/// [_enginePackageNames]) as written by `CreateCommand`'s template,
/// capturing the `ref:` line so it can be swapped in place without
/// disturbing the rest of pubspec.yaml.
RegExp _refPatternFor(String packageName) => RegExp(
      '($packageName:\\s*\\n\\s*git:\\s*\\n\\s*url:[^\\n]*\\n\\s*path:[^\\n]*\\n\\s*ref:\\s*)(\\S+)',
    );

class UpgradeCommand extends Command<int> {
  @override
  final name = 'upgrade';
  @override
  final description =
      'Point this project\'s engine package dependencies at a new git ref and refetch.';

  final CommandProcessRunner _runProcess;

  /// Inject process execution to validate upgrades without fetching packages.
  UpgradeCommand({CommandProcessRunner runProcess = runStreamed})
      : _runProcess = runProcess {
    argParser.addOption('ref',
        defaultsTo: 'v0.1.0',
        help: 'Git ref (branch or tag) to upgrade engine packages to.');
  }

  @override
  Future<int> run() async {
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln(
          'Error: no pubspec.yaml in the current directory. Run this inside a project created by `game_agent create`.');
      return 1;
    }

    var content = pubspecFile.readAsStringSync();
    final newRef = argResults!['ref'] as String;

    var foundAny = false;
    for (final packageName in _enginePackageNames) {
      final match = _refPatternFor(packageName).firstMatch(content);
      if (match == null) continue; // this project doesn't depend on it
      foundAny = true;

      final oldRef = match.group(2);
      if (oldRef == newRef) {
        stdout.writeln('$packageName is already pinned to "$newRef".');
        continue;
      }
      content = content.replaceRange(
        match.start,
        match.end,
        '${match.group(1)}$newRef',
      );
      stdout.writeln('Updated $packageName ref: $oldRef -> $newRef');
    }

    if (!foundAny) {
      stderr.writeln(
          'Error: could not find any engine package git dependency in pubspec.yaml. '
          'This project may not have been created by `game_agent create`.');
      return 1;
    }

    pubspecFile.writeAsStringSync(content);

    stdout.writeln('Refetching packages...');
    await _runProcess('flutter', ['pub', 'upgrade']);
    stdout.writeln('Done.');
    return 0;
  }
}
