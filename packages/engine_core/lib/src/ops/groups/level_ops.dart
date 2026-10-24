import 'dart:convert';

import 'package:engine_schema/engine_schema.dart';

import '../../content/level_diff.dart';
import '../../content/level_document.dart';
import '../../io/file_lock.dart';
import '../context.dart';
import '../files.dart';
import '../level_check.dart';
import '../operation.dart';
import '../param.dart';
import '../project/studio_project.dart';
import '../result.dart';

/// The level text for either a project-relative [path] or inline [json].
String levelText(
  OpContext ctx,
  Map<String, Object?> a, {
  String path = 'path',
  String json = 'json',
}) {
  final inline = a[json];
  if (inline != null) return jsonEncode(inline);
  final rel = a[path] as String?;
  if (rel == null) {
    throw OpError(
      ErrorCode.invalidParams,
      'Give "$path" (a project file) or "$json" (inline content).',
    );
  }
  if (ctx.project == null) {
    throw OpError(
      ErrorCode.notFound,
      'No project is open.',
      hint: 'Call project.open first.',
    );
  }
  final text = ctx.files.read(ctx.project!.resolve(rel));
  if (text == null) throw OpError(ErrorCode.notFound, 'No file at $rel.');
  return text;
}

LevelDocument parseLevel(String text, {String what = 'level'}) {
  try {
    return LevelDocument.fromJson(jsonDecode(text) as Map<String, dynamic>);
  } on Object catch (e) {
    throw OpError(
      ErrorCode.validationFailed,
      'The $what is not a loadable level ($e).',
    );
  }
}

/// `level.*` reads (the writes are added alongside, in phase 4).
List<Operation> levelReadOperations() => [
  Operation(
    name: 'level.list',
    summary:
        'List the project\'s level files with their entity count and lock state.',
    description:
        'Every `.json` under `assets/levels` except the play-test snapshot. `lockedBy` appears when someone holds the advisory lock.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final project = StudioProject.open(ctx.project!.root);
      return OpOutcome.data([
        for (final rel in project.levelPaths()) _levelSummary(ctx, rel),
      ]);
    },
  ),
  Operation(
    name: 'level.read',
    summary: 'Read a level, one entity of it, or selected components.',
    description:
        'Returns the level JSON. `entity` narrows to one named entity; `components` keeps only those components of each '
        'returned entity. Large levels can be paged with `entityOffset` and `entityLimit`.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
      Param(
        'entity',
        ParamType.string,
        description: 'Only the entity with this name.',
      ),
      Param(
        'components',
        ParamType.array,
        items: Param.string(),
        description: 'Only these components.',
      ),
      Param('entityOffset', ParamType.integer, min: 0, defaultValue: 0),
      Param(
        'entityLimit',
        ParamType.integer,
        min: 1,
        max: 5000,
        defaultValue: 1000,
      ),
    ],
    errors: {
      ErrorCode.notFound: 'The file or the named entity does not exist.',
    },
    handler: (ctx, a) {
      final doc = parseLevel(levelText(ctx, a));
      var entities = doc.entities;
      final only = a['entity'] as String?;
      if (only != null) {
        entities = [
          for (final e in entities)
            if (e.name == only) e,
        ];
        if (entities.isEmpty)
          throw OpError(ErrorCode.notFound, 'No entity named "$only".');
      }
      final total = entities.length;
      final offset = a['entityOffset']! as int;
      entities = entities.skip(offset).take(a['entityLimit']! as int).toList();
      final keep = (a['components'] as List?)?.cast<String>();
      final json = doc.toJson();
      final rendered = [
        for (final e in entities)
          {
            ...e.toJson(),
            if (keep != null && e.toJson()['components'] is Map)
              'components': {
                for (final c in (e.toJson()['components'] as Map).entries)
                  if (keep.contains(c.key)) c.key: c.value,
              },
          },
      ];
      return OpOutcome.data({
        ...json,
        'entities': rendered,
        'total': total,
        'offset': offset,
      });
    },
    examples: const [
      Example('One entity', {
        'path': 'assets/levels/level1.json',
        'entity': 'player',
      }),
    ],
  ),
  Operation(
    name: 'level.validate',
    summary:
        'Check a level (a project file or inline JSON) against the component schemas.',
    description:
        'Reports schema errors and warnings. Give either `path` or `json`. Nothing is written. Use `project.validate` '
        'for every level at once.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param(
        'json',
        ParamType.json,
        description: 'The level content, instead of a file.',
      ),
    ],
    handler: (ctx, a) =>
        OpOutcome.data(checkLevelText(levelText(ctx, a)).toJson()),
    examples: const [
      Example(
        'Inline',
        {
          'json': {'entities': []},
        },
        expect: {'ok': true},
      ),
    ],
  ),
  Operation(
    name: 'level.diff',
    summary: 'What differs between two levels, by entity and component.',
    description:
        'Entities are matched by name. Each side is a project file (`a`, `b`) or inline JSON (`aJson`, `bJson`). '
        'The result has the structured diff and the same text `game_agent studio diff` prints.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('a', ParamType.path, positional: true),
      Param('b', ParamType.path, positional: true),
      Param('aJson', ParamType.json),
      Param('bJson', ParamType.json),
    ],
    handler: (ctx, a) {
      final before = parseLevel(
        levelText(ctx, a, path: 'a', json: 'aJson'),
        what: 'first level',
      );
      final after = parseLevel(
        levelText(ctx, a, path: 'b', json: 'bJson'),
        what: 'second level',
      );
      final d = diffLevels(before, after);
      return OpOutcome.data({
        'isEmpty': d.isEmpty,
        'diff': d.toJson(),
        'text': d.format(),
      });
    },
    examples: const [
      Example(
        'Added entity',
        {
          'aJson': {'entities': []},
          'bJson': {
            'entities': [
              {'name': 'x', 'components': {}},
            ],
          },
        },
        expect: {'isEmpty': false},
      ),
    ],
  ),
  Operation(
    name: 'level.lock_status',
    summary: 'Who holds the advisory lock on a level, if anyone.',
    description:
        'Reads `<level>.lock`. A lock older than two hours is treated as abandoned and reported as unlocked.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
    ],
    handler: (ctx, a) => OpOutcome.data(_lockJson(ctx, a['path']! as String)),
  ),
];

Map<String, Object?> _lockJson(OpContext ctx, String rel) {
  if (ctx.files is! DiskFiles) return {'locked': false};
  final info = FileLock(ctx.project!.resolve(rel)).inspect();
  return info == null
      ? {'locked': false}
      : {
          'locked': true,
          'owner': info.owner,
          'since': info.acquiredAt.toUtc().toIso8601String(),
        };
}

Map<String, Object?> _levelSummary(OpContext ctx, String rel) {
  final text = ctx.files.read(ctx.project!.resolve(rel));
  var entities = 0;
  var hasTileMap = false;
  String? problem;
  try {
    final doc = LevelDocument.fromJson(
      jsonDecode(text ?? '') as Map<String, dynamic>,
    );
    entities = doc.entities.length;
    hasTileMap = doc.entities.any(
      (e) =>
          e.toJson()['components'] is Map &&
          (e.toJson()['components'] as Map).containsKey('tileMap'),
    );
  } on Object catch (e) {
    problem = '$e';
  }
  final lock = _lockJson(ctx, rel);
  return {
    'path': rel,
    'entities': entities,
    'hasTileMap': hasTileMap,
    if (problem != null) 'problem': problem,
    if (lock['locked'] == true) 'lockedBy': lock['owner'],
  };
}

/// Helper for tests and other groups: the component names the schemas know.
List<String> knownComponents() => allComponentSchemas.keys.toList()..sort();
