import 'dart:io';

import 'package:args/command_runner.dart';

import 'process_utils.dart';

/// Matches the engine_core git-dependency block written by CreateCommand's
/// template, capturing the `ref:` line so it can be swapped in place
/// without disturbing the rest of pubspec.yaml.
final _engineRefPattern = RegExp(
  r'(engine_core:\s*\n\s*git:\s*\n\s*url:[^\n]*\n\s*path:[^\n]*\n\s*ref:\s*)(\S+)',
);

class UpgradeCommand extends Command<int> {
  @override
  final name = 'upgrade';
  @override
  final description =
      'Point this project\'s engine_core dependency at a new git ref and refetch.';

  UpgradeCommand() {
    argParser.addOption('ref',
        defaultsTo: 'main',
        help: 'Git ref (branch or tag) to upgrade engine_core to.');
  }

  @override
  Future<int> run() async {
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln(
          'Error: no pubspec.yaml in the current directory. Run this inside a project created by `game_agent create`.');
      return 1;
    }

    final content = pubspecFile.readAsStringSync();
    final newRef = argResults!['ref'] as String;
    final match = _engineRefPattern.firstMatch(content);
    if (match == null) {
      stderr.writeln(
          'Error: could not find an engine_core git dependency in pubspec.yaml. '
          'This project may not have been created by `game_agent create`.');
      return 1;
    }

    final oldRef = match.group(2);
    if (oldRef == newRef) {
      stdout.writeln('engine_core is already pinned to "$newRef".');
    } else {
      final updated = content.replaceRange(
        match.start,
        match.end,
        '${match.group(1)}$newRef',
      );
      pubspecFile.writeAsStringSync(updated);
      stdout.writeln('Updated engine_core ref: $oldRef -> $newRef');
    }

    stdout.writeln('Refetching packages...');
    await runStreamed('flutter', ['pub', 'upgrade']);
    stdout.writeln('Done.');
    return 0;
  }
}
