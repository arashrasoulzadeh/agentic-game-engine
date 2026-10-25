import 'dart:async';

import 'cancellation.dart';
import 'context.dart';
import 'json_schema.dart';
import 'operation.dart';
import 'param.dart';
import 'result.dart';

/// Turns a write handler's [Proposal] into a final result (preview, confirmation, validation, locks, atomic
/// write and undo record). Supplied by the safety layer; without one, writes are refused.
typedef ProposalFinisher =
    Future<OpResult> Function(
      Operation op,
      Map<String, Object?> args,
      OpOutcome outcome,
      OpContext ctx,
    );

/// The single list of operations every surface binds to, and the one place that validates, enforces policy,
/// serializes writes, times and wraps results.
class OperationRegistry {
  OperationRegistry(
    Iterable<Operation> operations, {
    this.version = '0.1.0',
    this.finisher,
  }) {
    for (final op in operations) {
      if (!Operation.namePattern.hasMatch(op.name)) {
        throw ArgumentError(
          'Operation name "${op.name}" must look like group.verb in lower snake case.',
        );
      }
      if (_byName.containsKey(op.name))
        throw ArgumentError('Operation "${op.name}" is registered twice.');
      _byName[op.name] = op;
    }
  }

  /// Semver of the operation set: a new operation or optional parameter is a minor bump, removing or renaming
  /// anything or changing a result shape is a major one.
  final String version;
  final ProposalFinisher? finisher;
  final Map<String, Operation> _byName = {};

  /// Every operation in name order.
  List<Operation> get all =>
      _byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  Operation? lookup(String name) => _byName[name];

  /// The operations [ctx]'s policy lets a client see.
  List<Operation> visibleTo(OpContext ctx) => [
    for (final o in all)
      if (ctx.policy.visible(o.name)) o,
  ];

  /// A copy of the registry with [replacements] swapped in by name (the CLI uses this to give the
  /// `requiresFlutter` operations their process-running handlers).
  OperationRegistry replacing(Map<String, OpHandler> replacements) =>
      OperationRegistry(
        [
          for (final o in all)
            replacements.containsKey(o.name)
                ? o.copyWith(handler: replacements[o.name])
                : o,
        ],
        version: version,
        finisher: finisher,
      );

  /// Runs [name] with [rawArgs]. Never throws: every failure is an [OpResult.failure].
  ///
  /// When [cancellation] / [onProgress] are set they are visible via Zone for
  /// the duration of the call, so concurrent invokes on one [OpContext] stay isolated.
  Future<OpResult> call(
    String name,
    Map<String, Object?> rawArgs,
    OpContext ctx, {
    CancellationToken? cancellation,
    void Function(Map<String, Object?> progress)? onProgress,
  }) {
    Future<OpResult> body() async {
      final sw = Stopwatch()..start();
      try {
        cancellation?.throwIfCancelled();
        final op = _byName[name];
        if (op == null) {
          throw OpError(
            ErrorCode.unknownOperation,
            'No operation named "$name".',
            hint: 'List them with engine.operations.',
          );
        }
        ctx.policy.check(op);
        final args = ParamValidator(
          op.params,
          implicit: op.implicitParams,
        ).coerce(rawArgs);
        if (op.scope == OperationScope.project && ctx.project == null) {
          throw OpError(
            ErrorCode.notFound,
            'No project is open.',
            hint: 'Call project.open first.',
          );
        }
        final outcome = await ctx.serialize(
          op.kind,
          () async => await op.handler(ctx, args),
        );
        OpResult result;
        if (outcome.proposal != null) {
          final f = finisher;
          if (f == null) {
            throw OpError(
              ErrorCode.internal,
              'Write operations are not available (no safety pipeline).',
            );
          }
          result = await ctx.serialize(op.kind, () => f(op, args, outcome, ctx));
        } else {
          result = OpResult.success(
            outcome.data,
            warnings: [
              ...outcome.warnings,
              if (op.deprecated != null)
                'deprecated since ${op.deprecated!.since}${op.deprecated!.replacement == null ? '' : '; use ${op.deprecated!.replacement}'}',
            ],
          );
        }
        cancellation?.throwIfCancelled();
        return result.withDuration(sw.elapsedMilliseconds);
      } on OpError catch (e) {
        return OpResult.failure(e, durationMs: sw.elapsedMilliseconds);
      } catch (e, st) {
        ctx.log('internal error in $name: $e\n$st');
        return OpResult.failure(
          OpError(ErrorCode.internal, 'Internal error.'),
          durationMs: sw.elapsedMilliseconds,
        );
      }
    }

    if (cancellation == null && onProgress == null) return body();
    return runZoned(
      body,
      zoneValues: {
        if (cancellation != null) opCancellationZoneKey: cancellation,
        if (onProgress != null) opProgressZoneKey: onProgress,
      },
    );
  }
}

/// One-line description of an operation for catalogues.
Map<String, Object?> operationSummaryJson(Operation op) => {
  'name': op.name,
  'group': op.group,
  'summary': op.summary,
  'kind': op.kind.name,
  'scope': op.scope.name,
  'requiresFlutter': op.requiresFlutter,
  'since': op.since,
  if (op.deprecated != null) 'deprecated': true,
};

/// Everything a client needs to call [op] correctly.
Map<String, Object?> operationDetailJson(Operation op) => {
  ...operationSummaryJson(op),
  'description': op.description,
  'idempotent': op.idempotent,
  'inputSchema': inputSchemaFor(op),
  'resultSchema': op.result.schema,
  'errors': {for (final e in op.errors.entries) e.key.code: e.value},
  'examples': [
    for (final e in op.examples)
      {
        'title': e.title,
        'args': e.args,
        if (e.expect != null) 'expect': e.expect,
      },
  ],
  if (op.deprecated != null)
    'deprecation': {
      'since': op.deprecated!.since,
      'removeIn': op.deprecated!.removeIn,
      if (op.deprecated!.replacement != null)
        'replacement': op.deprecated!.replacement,
    },
};
