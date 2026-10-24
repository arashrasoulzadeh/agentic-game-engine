import '../json_schema.dart';
import '../operation.dart';
import '../param.dart';
import '../registry.dart';
import '../result.dart';

/// `engine.*`: what the server is, what it can do and what operations exist. The registry is passed in because
/// these operations describe it.
List<Operation> engineOperations(OperationRegistry Function() registry) => [
  Operation(
    name: 'engine.health',
    summary:
        'Report that the server is alive, its versions and whether a project is open.',
    description:
        'Cheap liveness and identity check. Safe to call at any time; changes nothing.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    handler: (ctx, a) => OpOutcome.data({
      'status': 'ok',
      'registryVersion': registry().version,
      'uptimeMs': ctx.clock().difference(ctx.startedAt).inMilliseconds,
      'project': {
        'open': ctx.project != null,
        if (ctx.project != null) 'root': ctx.project!.root,
      },
      'readOnly': ctx.policy.readOnly,
    }),
  ),
  Operation(
    name: 'engine.capabilities',
    summary:
        'List operation groups, unsupported operations and the active restrictions.',
    description:
        'Tells a client what to expect before it calls anything: how many operations each group has, which ones '
        'exist but are not served here (they need the Flutter SDK), whether the server is read-only and which '
        'operations the allow/deny lists hide.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    handler: (ctx, a) {
      final all = registry().all;
      final visible = registry().visibleTo(ctx);
      final groups = <String, int>{};
      for (final o in visible) {
        groups[o.group] = (groups[o.group] ?? 0) + 1;
      }
      return OpOutcome.data({
        'registryVersion': registry().version,
        'groups': groups,
        'operationCount': visible.length,
        'unsupported': [
          for (final o in visible)
            if (o.requiresFlutter)
              {
                'name': o.name,
                'reason': 'needs the Flutter SDK; use the game_agent CLI',
              },
        ],
        'readOnly': ctx.policy.readOnly,
        'hidden': all.length - visible.length,
        'flutter': false,
      });
    },
  ),
  Operation(
    name: 'engine.operations',
    summary:
        'List every operation (name, kind, scope, summary), optionally filtered.',
    description:
        'The catalogue. Filter by `group` or `kind`; operations hidden by the allow/deny lists are not listed.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'group',
        ParamType.string,
        description: 'Only this group, e.g. level.',
      ),
      Param(
        'kind',
        ParamType.enumeration,
        options: ['read', 'write', 'destructive'],
      ),
    ],
    handler: (ctx, a) => OpOutcome.data([
      for (final o in registry().visibleTo(ctx))
        if ((a['group'] == null || o.group == a['group']) &&
            (a['kind'] == null || o.kind.name == a['kind']))
          operationSummaryJson(o),
    ]),
    examples: const [
      Example('Only reads', {'kind': 'read'}),
    ],
  ),
  Operation(
    name: 'engine.operation',
    summary:
        'Describe one operation: parameters as JSON Schema, errors, examples.',
    description:
        'Everything needed to call an operation correctly, including its input JSON Schema.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'name',
        ParamType.string,
        required: true,
        positional: true,
        description: 'group.verb',
      ),
    ],
    errors: {
      ErrorCode.notFound: 'No operation has that name (or it is hidden).',
    },
    handler: (ctx, a) {
      final op = registry().lookup(a['name']! as String);
      if (op == null || !ctx.policy.visible(op.name)) {
        throw OpError(ErrorCode.notFound, 'No operation named "${a['name']}".');
      }
      return OpOutcome.data(operationDetailJson(op));
    },
    examples: const [
      Example('Describe the catalogue operation', {
        'name': 'engine.operations',
      }),
    ],
  ),
];

/// JSON Schema of every operation's input, keyed by name (documentation generators use it).
Map<String, Object?> allInputSchemas(OperationRegistry r) => {
  for (final o in r.all) o.name: inputSchemaFor(o),
};
