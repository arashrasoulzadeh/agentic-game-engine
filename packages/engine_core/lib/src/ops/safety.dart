import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../content/level_diff.dart';
import '../content/level_document.dart';
import '../io/file_lock.dart';
import '../validation/level_validator.dart';
import 'package:engine_schema/engine_schema.dart';

import 'context.dart';
import 'files.dart';
import 'operation.dart';
import 'result.dart';
import 'undo_log.dart';

/// Checks one proposed file; returns the problems found (empty = fine). Applied to every file a write changes
/// so no operation can leave the project with a file the engine would reject.
typedef ChangeValidator = List<String> Function(FileChange change);

bool _isLevel(String path) =>
    path.startsWith('assets/levels/') && path.endsWith('.json');

/// Level files must parse and have no validator errors.
List<String> validateLevelChange(FileChange c) {
  if (!_isLevel(c.path) || c.after == null) return const [];
  try {
    final doc = LevelDocument.fromJson(
      jsonDecode(c.after!) as Map<String, dynamic>,
    );
    return [
      for (final i in LevelValidator.forSchemas(
        allComponentSchemas,
      ).validate(doc))
        if (i.severity == IssueSeverity.error) i.toString(),
    ];
  } on Object catch (e) {
    return ['${c.path} is not a loadable level ($e)'];
  }
}

String _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canon(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_canon).join(',')}]';
  return jsonEncode(v);
}

/// What the safety pipeline does with a write operation's [Proposal]: validates every file, checks advisory
/// locks, builds the diff, previews destructive changes behind a confirmation token, writes atomically (with
/// rollback if a later file fails) and records an undo entry **before** touching the first file.
class SafetyPipeline {
  SafetyPipeline({List<ChangeValidator>? validators, List<int>? secret})
    : validators = validators ?? [validateLevelChange],
      _secret = Uint8List.fromList(
        secret ?? List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );

  final List<ChangeValidator> validators;
  final Uint8List _secret;

  /// Plugs into `OperationRegistry(finisher: pipeline.finish)`.
  Future<OpResult> finish(
    Operation op,
    Map<String, Object?> args,
    OpOutcome outcome,
    OpContext ctx,
  ) async {
    final proposal = outcome.proposal!;
    final project = ctx.project;
    if (project == null) {
      throw OpError(
        ErrorCode.notFound,
        'No project is open.',
        hint: 'Call project.open first.',
      );
    }
    final changes = [
      for (final c in proposal.changes)
        if (c.before != c.after) c,
    ];

    for (final c in changes) {
      final rel = p.posix.normalize(c.path.replaceAll('\\', '/'));
      if (rel == '.studio' ||
          rel.startsWith('.studio/') ||
          rel == '.git' ||
          rel.startsWith('.git/')) {
        throw OpError(
          ErrorCode.forbidden,
          'Operations never write to ${c.path}.',
          hint:
              '.studio holds the API token and the undo journal, .git is the repository.',
        );
      }
    }

    final problems = [
      for (final c in changes)
        for (final v in validators) ...v(c),
    ];
    if (problems.isNotEmpty) {
      throw OpError(
        ErrorCode.validationFailed,
        'This would make the project invalid; nothing was written.',
        details: {'problems': problems},
      );
    }

    if (ctx.files is DiskFiles) {
      for (final c in changes) {
        final info = FileLock(project.resolve(c.path)).inspect();
        if (info != null && info.owner != ctx.lockOwner) {
          throw OpError(
            ErrorCode.locked,
            '${c.path} is locked by ${info.owner}.',
            details: {
              'path': c.path,
              'owner': info.owner,
              'since': info.acquiredAt.toUtc().toIso8601String(),
            },
            hint: 'Ask them to unlock it, or use level.unlock with force.',
          );
        }
      }
    }

    final diff = _diffFor(changes);
    final summary = proposal.summary ?? _summaryOf(changes);
    final confirmation = args['confirmation'] as String?;
    final wantsApply = args['apply'] == true;
    final applyAllowed = args['apply'] != false;

    if (op.kind == OperationKind.destructive) {
      if (confirmation == null) {
        final preview = _preview(
          op,
          args,
          changes,
          summary,
          diff,
          outcome,
          ctx,
        );
        if (wantsApply) {
          throw OpError(
            ErrorCode.confirmationRequired,
            'This operation is destructive: review the preview and repeat the call with its confirmation token.',
            details: {'preview': preview},
          );
        }
        return OpResult.success(
          preview,
          warnings: outcome.warnings,
          diff: diff,
        );
      }
      _verify(confirmation, op, args, changes, ctx);
    } else if (!applyAllowed) {
      return OpResult.success(
        {
          'preview': true,
          'summary': summary,
          'diff': diff,
          'wouldReturn': outcome.data,
        },
        warnings: outcome.warnings,
        diff: diff,
      );
    }

    if (changes.isEmpty) {
      return OpResult.success(
        outcome.data,
        warnings: [...outcome.warnings, 'nothing changed'],
      );
    }

    String? undoId;
    final isUndo = op.group == 'undo';
    if (!isUndo) {
      undoId = ctx.undoLog().record(op.name, ctx.actor, changes);
    }
    _write(changes, ctx);
    if (isUndo) {
      final data = outcome.data as Map;
      ctx.undoLog().mark(data['entryId'] as String, undone: op.verb == 'undo');
    }
    return OpResult.success(
      outcome.data,
      warnings: outcome.warnings,
      diff: diff,
      undoId: undoId,
    );
  }

  void _write(List<FileChange> changes, OpContext ctx) {
    final project = ctx.project!;
    final done = <FileChange>[];
    try {
      for (final c in changes) {
        final abs = project.resolve(c.path);
        if (c.after == null) {
          ctx.files.delete(abs);
        } else {
          ctx.files.writeAtomic(abs, c.after!);
        }
        done.add(c);
      }
    } on Object catch (e) {
      for (final c in done.reversed) {
        final abs = project.resolve(c.path);
        if (c.before == null) {
          ctx.files.delete(abs);
        } else {
          ctx.files.writeAtomic(abs, c.before!);
        }
      }
      throw OpError(
        ErrorCode.ioError,
        'Writing failed and the earlier files were restored ($e).',
      );
    }
  }

  Map<String, Object?> _preview(
    Operation op,
    Map<String, Object?> args,
    List<FileChange> changes,
    String summary,
    Map<String, Object?> diff,
    OpOutcome outcome,
    OpContext ctx,
  ) {
    final exp = ctx.clock().toUtc().add(ctx.confirmationTtl);
    return {
      'preview': true,
      'summary': summary,
      'diff': diff,
      'confirmation': _issue(op, args, changes, exp),
      'expiresAt': exp.toIso8601String(),
      'wouldReturn': outcome.data,
    };
  }

  String _argsHash(Map<String, Object?> args) => crypto.sha256
      .convert(
        utf8.encode(
          _canon({
            for (final e in args.entries)
              if (e.key != 'apply' && e.key != 'confirmation') e.key: e.value,
          }),
        ),
      )
      .toString();

  String _beforeHash(List<FileChange> changes) => crypto.sha256
      .convert(
        utf8.encode(
          changes
              .map(
                (c) => '${c.path}\n${sha256Of(c.before)}\n${sha256Of(c.after)}',
              )
              .join('\n'),
        ),
      )
      .toString();

  String _sign(String payload) => crypto.Hmac(
    crypto.sha256,
    _secret,
  ).convert(utf8.encode(payload)).toString();

  String _issue(
    Operation op,
    Map<String, Object?> args,
    List<FileChange> changes,
    DateTime expires,
  ) {
    final payload =
        'v1:${op.name}:${_argsHash(args)}:${_beforeHash(changes)}:${expires.millisecondsSinceEpoch ~/ 1000}';
    return base64Url.encode(utf8.encode('$payload:${_sign(payload)}'));
  }

  void _verify(
    String token,
    Operation op,
    Map<String, Object?> args,
    List<FileChange> changes,
    OpContext ctx,
  ) {
    final String raw;
    try {
      raw = utf8.decode(base64Url.decode(base64Url.normalize(token)));
    } on Object {
      throw OpError(
        ErrorCode.invalidParams,
        'The confirmation token is not valid.',
      );
    }
    final i = raw.lastIndexOf(':');
    final parts = i < 0 ? const <String>[] : raw.substring(0, i).split(':');
    if (parts.length != 5 ||
        parts.first != 'v1' ||
        !_constantTimeEquals(
          raw.substring(i + 1),
          _sign(raw.substring(0, i)),
        )) {
      throw OpError(
        ErrorCode.invalidParams,
        'The confirmation token is not valid.',
      );
    }
    if (parts[1] != op.name || parts[2] != _argsHash(args)) {
      throw OpError(
        ErrorCode.invalidParams,
        'The confirmation token belongs to a different call.',
        hint: 'Preview again with these exact arguments.',
      );
    }
    final expires = DateTime.fromMillisecondsSinceEpoch(
      int.parse(parts[4]) * 1000,
      isUtc: true,
    );
    if (!ctx.clock().toUtc().isBefore(expires) ||
        parts[3] != _beforeHash(changes)) {
      throw OpError(
        ErrorCode.confirmationStale,
        'The project changed or the preview expired.',
        hint: 'Preview again and confirm the new diff.',
      );
    }
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }

  String _summaryOf(List<FileChange> changes) {
    if (changes.isEmpty) return 'No changes.';
    return changes
        .map(
          (c) =>
              '${c.before == null
                  ? 'creates'
                  : c.after == null
                  ? 'deletes'
                  : 'changes'} ${c.path}',
        )
        .join('; ');
  }

  Map<String, Object?> _diffFor(List<FileChange> changes) => {
    'files': [
      for (final c in changes)
        {
          'path': c.path,
          'change': c.before == null
              ? 'created'
              : c.after == null
              ? 'deleted'
              : 'modified',
          if (_isLevel(c.path)) ...?_levelDiff(c),
        },
    ],
  };

  Map<String, Object?>? _levelDiff(FileChange c) {
    try {
      final before = c.before == null
          ? LevelDocument(entities: [])
          : LevelDocument.fromJson(
              jsonDecode(c.before!) as Map<String, dynamic>,
            );
      final after = c.after == null
          ? LevelDocument(entities: [])
          : LevelDocument.fromJson(
              jsonDecode(c.after!) as Map<String, dynamic>,
            );
      final d = diffLevels(before, after);
      return {'levelDiff': d.toJson(), 'text': d.format()};
    } on Object {
      return null;
    }
  }
}
