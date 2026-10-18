import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart' show FileLock, lockOwner;

import 'studio_command.dart' show canonicalJson;
import 'studio_edit_commands.dart' show loadLevelOrNull;

/// Registers `diff`, `merge`, `lock` and `unlock` on the `studio` command.
void addStudioDiffCommands(Command<int> studio) {
  studio
    ..addSubcommand(StudioDiffCommand())
    ..addSubcommand(StudioMergeCommand())
    ..addSubcommand(StudioLockCommand())
    ..addSubcommand(StudioUnlockCommand());
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

/// `game_agent studio lock <level>`: claim a level in a shared folder so teammates (and the
/// studio) see it is being edited. Exits 1 when someone else holds it.
class StudioLockCommand extends Command<int> {
  @override
  final name = 'lock';
  @override
  final description =
      'Claim a level file (advisory lock in <level>.lock); exits 1 if someone else holds it.';

  StudioLockCommand() {
    argParser.addOption('as', help: 'Who is locking (default: user@host).');
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1)
      usageException('Give one level file: studio lock <level>.');
    final owner = (argResults!['as'] as String?) ?? lockOwner();
    final result = FileLock(rest.single).acquire(owner);
    if (!result.acquired) {
      stderr.writeln(
        'Locked by ${result.holder.owner} since ${result.holder.acquiredAt.toLocal()}.',
      );
      return 1;
    }
    stdout.writeln('Locked ${rest.single} as $owner.');
    return 0;
  }
}

/// `game_agent studio unlock <level>`: release your lock (or `--force` someone else's).
class StudioUnlockCommand extends Command<int> {
  @override
  final name = 'unlock';
  @override
  final description =
      'Release the lock on a level file; --force removes someone else\'s.';

  StudioUnlockCommand() {
    argParser
      ..addOption('as', help: 'Who is unlocking (default: user@host).')
      ..addFlag(
        'force',
        negatable: false,
        help: 'Remove the lock even if someone else holds it.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1)
      usageException('Give one level file: studio unlock <level>.');
    final owner = (argResults!['as'] as String?) ?? lockOwner();
    final released = FileLock(
      rest.single,
    ).release(owner, force: argResults!['force'] as bool);
    if (!released) {
      stderr.writeln('Held by someone else; use --force to remove it.');
      return 1;
    }
    return 0;
  }
}
