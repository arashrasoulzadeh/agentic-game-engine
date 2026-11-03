import 'dart:convert';

import '../../command/prefab_commands.dart';
import '../../content/level_format.dart';
import '../../content/prefab.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../project/studio_project.dart';
import '../result.dart';
import 'level_ops.dart';
import 'level_write_ops.dart';

final _validName = RegExp(r'^[A-Za-z0-9_\-]+$');

String _pathFor(String name) {
  if (!_validName.hasMatch(name)) {
    throw OpError(
      ErrorCode.invalidParams,
      'A prefab name may only use letters, digits, "_" and "-".',
    );
  }
  return 'prefabs/$name.json';
}

Prefab _load(OpContext ctx, String name) {
  final text = ctx.files.read(ctx.project!.resolve(_pathFor(name)));
  if (text == null)
    throw OpError(ErrorCode.notFound, 'No prefab named "$name".');
  try {
    return Prefab.fromJson(jsonDecode(text) as Map<String, dynamic>);
  } on Object catch (e) {
    throw OpError(
      ErrorCode.validationFailed,
      'Prefab "$name" is unreadable ($e).',
    );
  }
}

/// `prefab.*`: reusable groups of entities stored as `prefabs/<name>.json`.
List<Operation> prefabOperations() => [
  Operation(
    name: 'prefab.list',
    summary: 'List the project\'s prefabs.',
    description: 'Every `prefabs/*.json`, with its entity count.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final project = StudioProject.open(ctx.project!.root);
      return OpOutcome.data([
        for (final rel in project.prefabPaths())
          {
            'path': rel,
            'name': rel.substring(
              'prefabs/'.length,
              rel.length - '.json'.length,
            ),
          },
      ]);
    },
  ),
  Operation(
    name: 'prefab.read',
    summary: 'Read one prefab.',
    description:
        'The prefab JSON: its name and entities, positions relative to its origin.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('name', ParamType.string, required: true, positional: true),
    ],
    errors: {ErrorCode.notFound: 'No such prefab.'},
    handler: (ctx, a) =>
        OpOutcome.data(_load(ctx, a['name']! as String).toJson()),
  ),
  Operation(
    name: 'prefab.save',
    summary: 'Capture named entities of a level as a prefab.',
    description:
        'Positions are stored relative to the group\'s top-left corner so the prefab can be placed anywhere. '
        'An existing prefab of the same name is replaced (undoable).',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
      Param('name', ParamType.string, required: true),
      Param('entities', ParamType.array, items: Param.string(), required: true),
    ],
    handler: (ctx, a) {
      final name = a['name']! as String;
      final rel = _pathFor(name);
      final doc = parseLevel(levelText(ctx, a));
      final wanted = (a['entities']! as List).cast<String>();
      final picked = [
        for (final n in wanted)
          doc.entityNamed(n) ??
              (throw OpError(
                ErrorCode.notFound,
                'No entity named "$n" in this level.',
              )),
      ];
      final prefab = Prefab.fromEntities(name, picked);
      return OpOutcome.proposal(
        Proposal([
          FileChange(
            path: rel,
            before: ctx.files.read(ctx.project!.resolve(rel)),
            after: encodeLevelJson(prefab.toJson()),
          ),
        ]),
        data: {'path': rel, 'entities': picked.length},
      );
    },
  ),
  Operation(
    name: 'prefab.place',
    summary: 'Place a prefab into a level at x,y.',
    description:
        'Fresh copies are added at the end of the level; entity names are made unique (`torch` becomes `torch2`).',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
      Param('prefab', ParamType.string, required: true),
      Param('x', ParamType.number, defaultValue: 0),
      Param('y', ParamType.number, defaultValue: 0),
    ],
    handler: (ctx, a) => editLevel(ctx, a, (doc, _) {
      final command = InstantiatePrefabCommand(
        _load(ctx, a['prefab']! as String),
        x: (a['x']! as num).toDouble(),
        y: (a['y']! as num).toDouble(),
      )..apply(doc);
      return {
        'entities': [for (final e in command.placed) e.toJson()],
      };
    }),
  ),
];
