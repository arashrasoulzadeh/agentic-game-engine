import 'dart:typed_data';

/// Stable error codes of the operation API. Strings are never reused or renamed; the numbers map each code onto the
/// surfaces (HTTP status, JSON-RPC error code, CLI exit code, following `sysexits.h` where a match exists).
enum ErrorCode {
  invalidParams('invalid_params', 400, -32602, 64),
  unknownOperation('unknown_operation', 404, -32601, 64),
  notFound('not_found', 404, -32001, 66),
  alreadyExists('already_exists', 409, -32002, 73),
  validationFailed('validation_failed', 422, -32003, 65),
  locked('locked', 423, -32004, 75),
  readOnly('read_only', 403, -32005, 77),
  forbidden('forbidden', 403, -32006, 77),
  confirmationRequired('confirmation_required', 409, -32007, 78),
  confirmationStale('confirmation_stale', 409, -32008, 78),
  conflict('conflict', 409, -32009, 1),
  unsupported('unsupported', 501, -32010, 69),
  tooLarge('too_large', 413, -32011, 64),
  rateLimited('rate_limited', 429, -32012, 75),
  unauthorized('unauthorized', 401, -32013, 77),
  ioError('io_error', 500, -32014, 74),
  /// Client asked to stop an in-flight call (`notifications/cancelled`).
  cancelled('cancelled', 499, -32015, 75),
  internal('internal', 500, -32603, 70);

  const ErrorCode(this.code, this.http, this.rpc, this.exit);

  /// The wire name (`invalid_params`).
  final String code;
  final int http;
  final int rpc;
  final int exit;

  static ErrorCode? byCode(String code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// A failed operation. Throw it from a handler; the dispatcher turns it into the error envelope.
class OpError implements Exception {
  OpError(this.code, this.message, {this.details, this.hint});

  final ErrorCode code;
  final String message;

  /// Machine-readable extras (`problems`, `owner`, `conflicts`, ...).
  final Map<String, Object?>? details;

  /// What to do next, in one sentence.
  final String? hint;

  Map<String, Object?> toJson() => {
    'code': code.code,
    'message': message,
    if (details != null) 'details': details,
    if (hint != null) 'hint': hint,
  };

  @override
  String toString() => 'OpError(${code.code}): $message';
}

/// One file a write operation wants to change. `after == null` (and no [afterBytes]) deletes the file;
/// `before == null` (and no [beforeBytes]) means it did not exist. Text ops use [before]/[after]; binary
/// ops (`asset.pack` PNG sheets) use [beforeBytes]/[afterBytes] — undo journals base64-encode those.
class FileChange {
  const FileChange({
    required this.path,
    this.before,
    this.after,
    this.beforeBytes,
    this.afterBytes,
  });

  /// Project-relative path.
  final String path;
  final String? before;
  final String? after;
  final Uint8List? beforeBytes;
  final Uint8List? afterBytes;

  /// True when this change carries raw bytes rather than UTF-8 text.
  bool get isBinary => beforeBytes != null || afterBytes != null;

  /// Whether the after-state is a delete (no text and no bytes).
  bool get isDelete => after == null && afterBytes == null;
}

/// The set of file changes a write handler proposes (applied by the safety pipeline, never by the handler).
class Proposal {
  const Proposal(this.changes, {this.summary});

  final List<FileChange> changes;

  /// One sentence for previews ("Removes entity 'guard' and 2 components").
  final String? summary;
}

/// What a handler returns: plain data for a read, or data plus a [Proposal] for a write.
class OpOutcome {
  const OpOutcome.data(this.data, {this.warnings = const []}) : proposal = null;
  const OpOutcome.proposal(
    Proposal this.proposal, {
    this.data,
    this.warnings = const [],
  });

  final Object? data;
  final List<String> warnings;
  final Proposal? proposal;
}

/// The uniform result envelope every surface returns: `{ok, data, warnings, diff?, undoId?, durationMs}` or
/// `{ok: false, error}`.
class OpResult {
  const OpResult.success(
    this.data, {
    this.warnings = const [],
    this.diff,
    this.undoId,
    this.durationMs = 0,
  }) : error = null;
  const OpResult.failure(OpError this.error, {this.durationMs = 0})
    : data = null,
      warnings = const [],
      diff = null,
      undoId = null;

  final Object? data;
  final List<String> warnings;
  final Map<String, Object?>? diff;
  final String? undoId;
  final OpError? error;
  final int durationMs;

  bool get ok => error == null;

  OpResult withDuration(int ms) => ok
      ? OpResult.success(
          data,
          warnings: warnings,
          diff: diff,
          undoId: undoId,
          durationMs: ms,
        )
      : OpResult.failure(error!, durationMs: ms);

  Map<String, Object?> toJson() => ok
      ? {
          'ok': true,
          'data': data,
          'warnings': warnings,
          if (diff != null) 'diff': diff,
          if (undoId != null) 'undoId': undoId,
          'durationMs': durationMs,
        }
      : {'ok': false, 'error': error!.toJson(), 'durationMs': durationMs};
}

/// The JSON Schema of an operation's result `data`, for documentation and clients. `any` means "documented in
/// the description only".
class ResultSpec {
  const ResultSpec(this.schema);
  const ResultSpec.any() : schema = const {};

  final Map<String, Object?> schema;
}
