import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';

import 'studio_command.dart' show canonicalJson;
import 'studio_edit_commands.dart' show loadLevelOrNull;

/// Registers `diff` and `merge` on the `studio` command.
void addStudioDiffCommands(Command<int> studio) {
  studio
    ..addSubcommand(StudioDiffCommand())
    ..addSubcommand(StudioMergeCommand());
}

/// `game_agent studio diff <before> <after>`: what changed between two level files, by entity
/// and component, instead of a line diff of JSON.
class StudioDiffCommand extends Command<int> {
  @override
  final name = 'diff';
  @override
  final description =
      'Show what differs between two level files (entities added/removed, component fields changed).';

  StudioDiffCommand() {
    argParser
      ..addFlag('json', negatable: false, help: 'Print the diff as JSON.')
      ..addFlag(
        'exit-code',
        negatable: false,
        help: 'Exit 1 when the levels differ (like git diff --exit-code).',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException('Give two level files: studio diff <before> <after>.');
    }
    final before = loadLevelOrNull(rest[0]);
    final after = loadLevelOrNull(rest[1]);
    if (before == null || after == null) return 1;
    final diff = diffLevels(before, after);
    stdout.writeln(
      argResults!['json'] as bool
          ? canonicalJson(diff.toJson())
          : diff.format(),
    );
    return argResults!['exit-code'] as bool && !diff.isEmpty ? 1 : 0;
  }
}

/// `game_agent studio merge <base> <ours> <theirs>`: a three-way merge of level files, usable
/// as a git merge driver (`merge=level` with `driver = game_agent studio merge %O %A %B`):
/// the result is written over **ours** unless `--out` says otherwise, and the exit code is 1
/// when something conflicted (ours was kept there) so git marks the file unmerged.
class StudioMergeCommand extends Command<int> {
  @override
  final name = 'merge';
  @override
  final description =
      'Three-way merge of level files by entity and component; exits 1 on conflicts.';

  StudioMergeCommand() {
    argParser.addOption(
      'out',
      help: 'Where to write the result (default: the "ours" file).',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 3) {
      usageException(
        'Give three level files: studio merge <base> <ours> <theirs>.',
      );
    }
    final base = loadLevelOrNull(rest[0]);
    final ours = loadLevelOrNull(rest[1]);
    final theirs = loadLevelOrNull(rest[2]);
    if (base == null || ours == null || theirs == null) return 1;

    final result = mergeLevels(base, ours, theirs);
    final out = (argResults!['out'] as String?) ?? rest[1];
    File(out).writeAsStringSync(canonicalJson(result.merged.toJson()));

    for (final c in result.conflicts) {
      stderr.writeln(
        c.component == null
            ? 'Conflict: "${c.entity}" was deleted on one side and edited on the other.'
            : 'Conflict: ${c.entity}.${c.component} was changed differently on both sides '
                  '(kept ours: ${jsonEncode(c.ours)}; theirs: ${jsonEncode(c.theirs)}).',
      );
    }
    return result.hasConflicts ? 1 : 0;
  }
}
