import 'dart:async';

import '../io/file_lock.dart' as locks;
import 'files.dart';
import 'operation.dart';
import 'paths.dart';
import 'world_sandbox.dart';
import 'result.dart';
import 'undo_log.dart';

/// Per-process rules about which operations may run: allow/deny globs (`*` matches within a name) and read-only.
class Policy {
  const Policy({
    this.allow = const [],
    this.deny = const [],
    this.readOnly = false,
  });

  final List<String> allow;
  final List<String> deny;
  final bool readOnly;

  static bool _glob(String pattern, String name) => RegExp(
    '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
  ).hasMatch(name);

  /// Whether [name] is visible and callable: deny wins, a non-empty allow list must match.
  bool visible(String name) {
    if (deny.any((d) => _glob(d, name))) return false;
    return allow.isEmpty || allow.any((a) => _glob(a, name));
  }

  void check(Operation op) {
    if (!visible(op.name)) {
      throw OpError(
        ErrorCode.forbidden,
        'Operation ${op.name} is disabled on this server.',
      );
    }
    if (readOnly && op.kind != OperationKind.read) {
      throw OpError(
        ErrorCode.readOnly,
        'The server is read-only; ${op.name} would change files.',
        hint: 'Restart without --read-only to allow writes.',
      );
    }
  }
}

/// Everything an operation may depend on, injected so tests and surfaces control it.
class OpContext {
  OpContext({
    this.project,
    this.policy = const Policy(),
    ProjectFiles? files,
    DateTime Function()? clock,
    this.actor = 'api',
    void Function(String message)? log,
    DateTime? startedAt,
    String? lockOwner,
    this.undoKeep = 100,
    this.confirmationTtl = const Duration(minutes: 5),
    this.allowProjectOpen = true,
    this.allowProjectSwitch = true,
  }) : lockOwner = lockOwner ?? _defaultOwner(),
       files = files ?? const DiskFiles(),
       clock = clock ?? DateTime.now,
       log = log ?? _ignore,
       startedAt = startedAt ?? (clock ?? DateTime.now)();

  static void _ignore(String _) {}

  static String _defaultOwner() => locks.lockOwner();

  /// In-memory worlds for the `world.*` operations; shared by every transport of this context.
  final WorldSandbox sandbox = WorldSandbox();

  /// Who this process is when taking advisory locks; another owner's lock blocks writes.
  final String lockOwner;

  /// How many writes the undo journal keeps.
  final int undoKeep;

  /// How long a destructive preview's confirmation token stays valid.
  final Duration confirmationTtl;

  /// Whether `project.open` may run at all (false when the server is bound to one project).
  final bool allowProjectOpen;

  /// Whether `project.open` may replace an already open project.
  final bool allowProjectSwitch;

  UndoLog? _undoLog;

  /// The project's write journal (`.studio/undo/`). Requires an open project.
  UndoLog undoLog() => _undoLog ??= UndoLog(
    files: files,
    projectRoot: project!.root,
    clock: clock,
    keep: undoKeep,
  );

  /// The open project, or null.
  ProjectRoot? project;
  final Policy policy;
  final ProjectFiles files;

  /// The only source of time for operations (tests inject a fixed clock).
  final DateTime Function() clock;

  /// Who is calling: `cli`, `mcp:<client>`, `rest`, `rpc`.
  final String actor;
  final void Function(String message) log;
  final DateTime startedAt;

  Future<void> _tail = Future.value();

  /// Runs [body] after every earlier write on this context has finished, so two callers cannot interleave a
  /// read-modify-write of the same file. Reads run immediately.
  Future<T> serialize<T>(OperationKind kind, Future<T> Function() body) {
    if (kind == OperationKind.read) return body();
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
