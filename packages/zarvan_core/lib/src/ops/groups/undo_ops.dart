import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import '../undo_log.dart';

OpOutcome _flip(OpContext ctx, Map<String, Object?> a, {required bool undo}) {
  final log = ctx.undoLog();
  UndoEntry? entry;
  final id = a['id'] as String?;
  if (id != null) {
    entry = log.find(id);
    if (entry == null)
      throw OpError(ErrorCode.notFound, 'No undo entry "$id".');
  } else {
    // Undo walks back from the newest write; redo walks forward from the oldest undone one.
    final entries = log.list(limit: 100);
    for (final e in undo ? entries : entries.reversed) {
      if (undo ? !e.undone : e.undone) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      throw OpError(
        ErrorCode.notFound,
        undo ? 'Nothing to undo.' : 'Nothing to redo.',
      );
    }
  }
  if (undo && entry.undone)
    throw OpError(ErrorCode.conflict, 'Entry ${entry.id} is already undone.');
  if (!undo && !entry.undone)
    throw OpError(ErrorCode.conflict, 'Entry ${entry.id} is not undone.');
  final force = a['force'] == true;
  final changes = <FileChange>[];
  final stale = <String>[];
  for (final f in entry.files) {
    final abs = ctx.project!.resolve(f.path);
    if (f.isBinary) {
      final current = ctx.files.readBytes(abs);
      final expected = undo ? f.afterBytes : f.beforeBytes;
      if (!force && sha256OfBytes(current) != sha256OfBytes(expected)) {
        stale.add(f.path);
      }
      changes.add(
        FileChange(
          path: f.path,
          beforeBytes: current,
          afterBytes: undo ? f.beforeBytes : f.afterBytes,
        ),
      );
    } else {
      final current = ctx.files.read(abs);
      final expected = undo ? f.after : f.before;
      if (!force && sha256Of(current) != sha256Of(expected)) stale.add(f.path);
      changes.add(
        FileChange(
          path: f.path,
          before: current,
          after: undo ? f.before : f.after,
        ),
      );
    }
  }
  if (stale.isNotEmpty) {
    throw OpError(
      ErrorCode.conflict,
      'These files changed since the entry was recorded: ${stale.join(', ')}.',
      details: {'files': stale},
      hint: 'Pass force: true to overwrite them anyway.',
    );
  }
  return OpOutcome.proposal(
    Proposal(
      changes,
      summary: '${undo ? 'Undo' : 'Redo'} ${entry.op} (${entry.id})',
    ),
    data: {
      'entryId': entry.id,
      'op': entry.op,
      'files': [for (final f in entry.files) f.path],
    },
  );
}

/// `undo.*`: the project's write journal (`.studio/undo/`, the last 100 writes).
List<Operation> undoOperations() => [
  Operation(
    name: 'undo.list',
    summary: 'List recent writes that can be undone, newest first.',
    description:
        'Reads the journal in `.studio/undo/`. Each entry has the operation, who did it, when and which files it touched.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('limit', ParamType.integer, min: 1, max: 100, defaultValue: 20),
    ],
    handler: (ctx, a) => OpOutcome.data([
      for (final e in ctx.undoLog().list(limit: a['limit']! as int))
        e.summaryJson(),
    ]),
    examples: const [
      Example('Latest five', {'limit': 5}),
    ],
  ),
  Operation(
    name: 'undo.undo',
    summary:
        'Undo the newest write (or a given entry) by restoring the files it changed.',
    description:
        'Restores the files of a journal entry to their content before that write. It refuses if a file changed '
        'after the entry (so a later edit is not lost) unless `force` is true. An undone entry can be redone.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param(
        'id',
        ParamType.string,
        description:
            'Entry id from undo.list; default the newest not yet undone.',
      ),
      Param('force', ParamType.boolean, defaultValue: false),
    ],
    errors: {
      ErrorCode.notFound: 'There is nothing to undo, or the id is unknown.',
      ErrorCode.conflict:
          'A touched file changed since the entry (details.files).',
    },
    handler: (ctx, a) => _flip(ctx, a, undo: true),
  ),
  Operation(
    name: 'undo.redo',
    summary: 'Redo the newest undone write (or a given entry).',
    description:
        'Re-applies a journal entry that was undone, if its files are still as the undo left them (or `force`).',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param(
        'id',
        ParamType.string,
        description: 'Entry id from undo.list; default the newest undone.',
      ),
      Param('force', ParamType.boolean, defaultValue: false),
    ],
    errors: {
      ErrorCode.notFound: 'There is nothing to redo, or the id is unknown.',
      ErrorCode.conflict:
          'A touched file changed since the undo (details.files).',
    },
    handler: (ctx, a) => _flip(ctx, a, undo: false),
  ),
];
