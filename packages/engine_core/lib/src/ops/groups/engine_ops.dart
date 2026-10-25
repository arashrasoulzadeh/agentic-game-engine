import 'package:path/path.dart' as p;

import '../json_schema.dart';
import '../operation.dart';
import '../param.dart';
import '../registry.dart';
import '../result.dart';

/// Pages under [docsRoot] that agents may read (same exclusions as the published site).
bool _docsPageAllowed(String rel) {
  if (!rel.endsWith('.md')) return false;
  if (rel.startsWith('proposals/') || rel.contains('/proposals/')) return false;
  if (rel == 'studio/qa-level-editor.md') return false;
  return true;
}

String _docsRel(String abs, String root) =>
    p.normalize(p.relative(abs, from: root)).replaceAll('\\', '/');

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
        'docsUrl': 'https://meetarash.ir/agentic-game-engine/',
        'docsAvailable': ctx.docsRoot != null && ctx.docsRoot!.isNotEmpty,
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
  Operation(
    name: 'engine.docs',
    summary: 'List documentation pages, or return one page as markdown.',
    description:
        'Reads the engine\'s `docs/` tree pointed at by the server\'s docs root (`engine_api --docs-root`, or '
        '`OpContext.docsRoot`). Without a docs root the call returns `unsupported` — the markdown is not '
        'bundled inside the package yet. Omitting `page` lists every readable `.md` (drafts under `proposals/` '
        'and the studio QA checklist are excluded, matching the published site). With `page` (e.g. '
        '`concepts/ecs.md` or `concepts/ecs`) returns `{page, markdown}`.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'page',
        ParamType.string,
        positional: true,
        description: 'Docs-relative path (`.md` optional), e.g. concepts/ecs.',
      ),
    ],
    errors: {
      ErrorCode.unsupported: 'No docs root is configured on this server.',
      ErrorCode.notFound: 'That page is missing or excluded.',
    },
    handler: (ctx, a) {
      final root = ctx.docsRoot;
      if (root == null || root.isEmpty) {
        throw OpError(
          ErrorCode.unsupported,
          'No documentation root is configured.',
          hint: 'Start engine_api with --docs-root pointing at the repo docs/ folder.',
        );
      }
      final page = a['page'] as String?;
      if (page == null || page.isEmpty) {
        final files = ctx.files.list(root, recursive: true);
        final pages = [
          for (final abs in files)
            if (_docsPageAllowed(_docsRel(abs, root))) _docsRel(abs, root),
        ]..sort();
        return OpOutcome.data({
          'root': root,
          'pages': pages,
          'count': pages.length,
        });
      }
      var rel = page.replaceAll('\\', '/');
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (!rel.endsWith('.md')) rel = '$rel.md';
      if (!_docsPageAllowed(rel) || rel.contains('..')) {
        throw OpError(ErrorCode.notFound, 'No documentation page "$page".');
      }
      final abs = p.normalize(p.join(root, rel));
      if (!p.isWithin(root, abs) && abs != p.normalize(root)) {
        throw OpError(ErrorCode.notFound, 'No documentation page "$page".');
      }
      final text = ctx.files.read(abs);
      if (text == null) {
        throw OpError(ErrorCode.notFound, 'No documentation page "$page".');
      }
      return OpOutcome.data({'page': rel, 'markdown': text});
    },
    // No registry examples: without a docsRoot the op returns unsupported, and
    // the dedicated engine_docs_test covers list/read with a fixture tree.
  ),
];

/// JSON Schema of every operation's input, keyed by name (documentation generators use it).
Map<String, Object?> allInputSchemas(OperationRegistry r) => {
  for (final o in r.all) o.name: inputSchemaFor(o),
};
