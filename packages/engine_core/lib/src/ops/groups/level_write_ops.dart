import 'package:engine_schema/engine_schema.dart';

import '../../command/edit_command.dart';
import '../../command/entity_commands.dart';
import '../../command/tile_commands.dart';
import '../../content/level_document.dart';
import '../../content/level_format.dart';
import '../../validation/level_validator.dart';
import '../../io/file_lock.dart';
import '../context.dart';
import '../project/studio_project.dart';
import '../../content/level_diff.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import 'level_ops.dart';

const _path = Param('path', ParamType.path, required: true, positional: true);

/// Loads [path], lets [edit] mutate the document through an [EditCommand], and proposes the validated result.
///
/// Validating the *edited* document is what stops an agent from writing a level the engine would refuse to load;
/// the same check guards the studio's CLI edits.
OpOutcome _edit(
  OpContext ctx,
  Map<String, Object?> a,
  Object? Function(LevelDocument doc, List<String> warnings) edit,
) {
  final rel = a['path']! as String;
  final before = levelText(ctx, a);
  final doc = parseLevel(before);
  final warnings = <String>[];
  final data = edit(doc, warnings);
  final errors = _errors(doc);
  if (errors.isNotEmpty) {
    throw OpError(
      ErrorCode.validationFailed,
      'This would make $rel invalid.',
      details: {'errors': errors},
    );
  }
  return OpOutcome.proposal(
    Proposal([
      FileChange(
        path: rel,
        before: before,
        after: encodeLevelJson(doc.toJson()),
      ),
    ]),
    data: data,
    warnings: warnings,
  );
}

List<String> _errors(LevelDocument doc) =>
    LevelValidator.forSchemas(allComponentSchemas)
        .validate(doc)
        .where((i) => i.severity == IssueSeverity.error)
        .map((i) => i.toString())
        .toList();

LevelEntity _entity(LevelDocument doc, String name) =>
    doc.entityNamed(name) ??
    (throw OpError(
      ErrorCode.notFound,
      'No entity named "$name" in this level.',
    ));

Map<String, dynamic> _template(String component) {
  final schema = allComponentSchemas[component];
  if (schema == null) {
    throw OpError(
      ErrorCode.invalidParams,
      'Unknown component "$component".',
      hint: 'schema.components lists the known ones.',
    );
  }
  return Map<String, dynamic>.of(schema.template);
}

void _apply(EditCommand c, LevelDocument doc) => c.apply(doc);

/// `level.*` writes. Handlers only propose file changes; the safety pipeline applies them.
List<Operation> levelWriteOperations() => [
  Operation(
    name: 'level.create',
    summary: 'Create a new level file, empty or from inline entities.',
    description:
        'Fails with `conflict` when the file exists. `entities` is the level\'s entity list; omit it for an empty level.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('entities', ParamType.json, description: 'Entity list.'),
    ],
    errors: {ErrorCode.conflict: 'A file already exists at the path.'},
    handler: (ctx, a) {
      final rel = a['path']! as String;
      if (ctx.files.read(ctx.project!.resolve(rel)) != null) {
        throw OpError(ErrorCode.conflict, '$rel already exists.');
      }
      final json = {'entities': a['entities'] ?? <Object?>[]};
      final doc = parseLevel(encodeLevelJson(json));
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, after: encodeLevelJson(doc.toJson()))]),
        data: {'path': rel, 'entities': doc.entities.length},
      );
    },
  ),
  Operation(
    name: 'level.lock',
    summary: 'Take the advisory edit lock on a level.',
    description:
        'Writes `<level>.lock` naming this session as owner. Other writers are refused while a live lock is held; '
        'a lock older than two hours counts as abandoned. Conflicts when someone else holds it.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [_path],
    errors: {ErrorCode.locked: 'Someone else holds the lock.'},
    handler: (ctx, a) {
      final lock = FileLock(ctx.project!.resolve(a['path']! as String));
      final r = lock.acquire(ctx.lockOwner);
      if (!r.acquired) {
        throw OpError(
          ErrorCode.locked,
          '${a['path']} is locked by ${r.holder.owner}.',
          details: {'owner': r.holder.owner},
        );
      }
      return OpOutcome.data({
        'owner': r.holder.owner,
        'acquiredAt': r.holder.acquiredAt.toUtc().toIso8601String(),
      });
    },
  ),
  Operation(
    name: 'level.unlock',
    summary: 'Release the advisory edit lock on a level.',
    description: 'Only the owner releases a live lock unless `force` is true.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('force', ParamType.boolean, defaultValue: false),
    ],
    errors: {ErrorCode.locked: 'Someone else holds a live lock.'},
    handler: (ctx, a) {
      final lock = FileLock(ctx.project!.resolve(a['path']! as String));
      final holder = lock.inspect();
      if (!lock.release(ctx.lockOwner, force: a['force'] == true)) {
        throw OpError(
          ErrorCode.locked,
          '${a['path']} is locked by ${holder?.owner}.',
          hint: 'Pass force:true to break it.',
        );
      }
      return OpOutcome.data({'released': true});
    },
  ),
  Operation(
    name: 'level.export_canonical',
    summary: 'Rewrite levels in the canonical format (indent, key order).',
    description:
        'Only formatting changes. A level that does not load is skipped and listed under `skipped`. '
        'Without `paths` every level of the project is processed.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [Param('paths', ParamType.array, items: Param.string())],
    handler: (ctx, a) {
      final rels =
          (a['paths'] as List?)?.cast<String>() ??
          StudioProject.open(ctx.project!.root).levelPaths();
      final changes = <FileChange>[];
      final skipped = <String>[];
      for (final rel in rels) {
        final before = ctx.files.read(ctx.project!.resolve(rel));
        if (before == null) {
          throw OpError(ErrorCode.notFound, 'No file at $rel.');
        }
        try {
          final doc = parseLevel(before);
          if (_errors(doc).isNotEmpty) {
            skipped.add(rel);
            continue;
          }
          final after = encodeLevelJson(doc.toJson());
          if (after != before) {
            changes.add(FileChange(path: rel, before: before, after: after));
          }
        } on OpError {
          skipped.add(rel);
        }
      }
      return OpOutcome.proposal(
        Proposal(changes),
        data: {
          'rewritten': [for (final c in changes) c.path],
          'skipped': skipped,
        },
      );
    },
  ),
  Operation(
    name: 'level.merge',
    summary: 'Three-way merge two edits of a level.',
    description:
        'Per entity and component: one-sided changes win, identical changes apply once, differing ones are conflicts '
        '(ours is kept in the result). Without `output` only the merged level is returned. With `output` it is written, '
        'but never while conflicts remain.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param('base', ParamType.path, required: true),
      Param('ours', ParamType.path, required: true),
      Param('theirs', ParamType.path, required: true),
      Param('output', ParamType.path),
    ],
    errors: {
      ErrorCode.conflict: 'Both sides changed the same thing differently.',
    },
    handler: (ctx, a) {
      LevelDocument load(String key) =>
          parseLevel(levelText(ctx, a, path: key), what: key);
      final merge = mergeLevels(load('base'), load('ours'), load('theirs'));
      final conflicts = [
        for (final c in merge.conflicts)
          {
            'entity': c.entity,
            if (c.component != null) 'component': c.component,
            'base': c.base,
            'ours': c.ours,
            'theirs': c.theirs,
          },
      ];
      final merged = merge.merged.toJson();
      final out = a['output'] as String?;
      if (out == null) {
        return OpOutcome.data({'merged': merged, 'conflicts': conflicts});
      }
      if (merge.hasConflicts) {
        throw OpError(
          ErrorCode.conflict,
          '${conflicts.length} conflict(s); resolve them before writing $out.',
          details: {'conflicts': conflicts},
        );
      }
      return OpOutcome.proposal(
        Proposal([
          FileChange(
            path: out,
            before: ctx.files.read(ctx.project!.resolve(out)),
            after: encodeLevelJson(merged),
          ),
        ]),
        data: {'merged': merged, 'conflicts': conflicts},
      );
    },
  ),
  Operation(
    name: 'level.add_entity',
    summary: 'Add an entity whose components start at their schema defaults.',
    description:
        '`components` names components to attach at their template values; `values` overrides fields as '
        '`{component: {field: value}}`. `index` inserts at a position, default is the end.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('name', ParamType.string),
      Param('components', ParamType.array, items: Param.string()),
      Param('index', ParamType.integer, min: 0),
      Param('values', ParamType.object),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final components = <String, Map<String, dynamic>>{
        for (final c in (a['components'] as List? ?? const []).cast<String>())
          c: _template(c),
      };
      final values = a['values'] as Map? ?? const {};
      for (final e in values.entries) {
        components
            .putIfAbsent(e.key as String, () => _template(e.key as String))
            .addAll(Map<String, dynamic>.from(e.value as Map));
      }
      final index = a['index'] as int?;
      if (index != null && index > doc.entities.length) {
        throw OpError(
          ErrorCode.invalidParams,
          '"index" is beyond the ${doc.entities.length} entities.',
        );
      }
      final entity = LevelEntity(
        name: a['name'] as String?,
        components: components,
      );
      _apply(AddEntityCommand(entity, index: index), doc);
      return {
        'index': index ?? doc.entities.length - 1,
        'entity': entity.toJson(),
      };
    }),
  ),
  Operation(
    name: 'level.remove_entity',
    summary: 'Remove a named entity from a level.',
    description:
        'Destructive: previews first and needs `apply` plus the confirmation token.',
    kind: OperationKind.destructive,
    scope: OperationScope.project,
    params: const [_path, Param('name', ParamType.string, required: true)],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['name']! as String);
      _apply(RemoveEntityCommand(e), doc);
      return {'removed': e.toJson()};
    }),
  ),
  Operation(
    name: 'level.move_entity',
    summary: 'Set an entity\'s position.',
    description: 'Writes the `position` component (created when absent).',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('name', ParamType.string, required: true),
      Param('x', ParamType.number, required: true),
      Param('y', ParamType.number, required: true),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['name']! as String);
      _apply(
        MoveEntityCommand(
          entity: e,
          x: (a['x']! as num).toDouble(),
          y: (a['y']! as num).toDouble(),
        ),
        doc,
      );
      return {'entity': e.toJson()};
    }),
  ),
  Operation(
    name: 'level.set_field',
    summary: 'Set one field of one component of an entity.',
    description:
        'Creates the component when absent. The edited level must still validate.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('component', ParamType.string, required: true),
      Param('field', ParamType.string, required: true),
      Param('value', ParamType.json, required: true),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['entity']! as String);
      final component = a['component']! as String;
      final field = a['field']! as String;
      final before = e.components[component]?[field];
      _apply(
        SetComponentFieldCommand(
          entity: e,
          component: component,
          field: field,
          value: a['value'],
        ),
        doc,
      );
      return {'before': before, 'after': a['value']};
    }),
  ),
  Operation(
    name: 'level.set_layer',
    summary: 'Set the draw order (zIndex) of one component of an entity.',
    description: 'The component must already exist on the entity.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('component', ParamType.string, required: true),
      Param('z', ParamType.integer, required: true),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['entity']! as String);
      final component = a['component']! as String;
      if (!e.components.containsKey(component)) {
        throw OpError(
          ErrorCode.notFound,
          '"${a['entity']}" has no $component component.',
        );
      }
      _apply(
        SetLayerCommand(
          entity: e,
          component: component,
          zIndex: a['z']! as int,
        ),
        doc,
      );
      return {'entity': e.toJson()};
    }),
  ),
  Operation(
    name: 'level.add_component',
    summary:
        'Attach a component at its schema defaults, optionally overriding fields.',
    description:
        'Conflicts when the entity already has the component; use level.set_field to change one.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('component', ParamType.string, required: true),
      Param('values', ParamType.object),
    ],
    errors: {ErrorCode.conflict: 'The entity already has the component.'},
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['entity']! as String);
      final name = a['component']! as String;
      if (e.components.containsKey(name)) {
        throw OpError(
          ErrorCode.conflict,
          '"${a['entity']}" already has $name.',
        );
      }
      final fields = _template(name)
        ..addAll(Map<String, dynamic>.from(a['values'] as Map? ?? const {}));
      e.components[name] = fields;
      return {'component': fields};
    }),
  ),
  Operation(
    name: 'level.remove_component',
    summary: 'Detach a component from an entity.',
    description:
        'Destructive: previews first and needs `apply` plus the confirmation token.',
    kind: OperationKind.destructive,
    scope: OperationScope.project,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('component', ParamType.string, required: true),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _entity(doc, a['entity']! as String);
      final removed = e.components.remove(a['component']! as String);
      if (removed == null) {
        throw OpError(
          ErrorCode.notFound,
          '"${a['entity']}" has no ${a['component']} component.',
        );
      }
      return {'removed': removed};
    }),
  ),
  Operation(
    name: 'level.paint_tile',
    summary: 'Set one tile of an entity\'s tileMap (0 erases).',
    description:
        'The entity needs a `tileMap` component; `col`/`row` must be inside its grid.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('col', ParamType.integer, required: true, min: 0),
      Param('row', ParamType.integer, required: true, min: 0),
      Param('tileId', ParamType.integer, required: true, min: 0),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _tileEntity(doc, a);
      _inGrid(e, a);
      _apply(
        SetTileCommand(
          entity: e,
          col: a['col']! as int,
          row: a['row']! as int,
          tileId: a['tileId']! as int,
        ),
        doc,
      );
      return {'changed': 1};
    }),
  ),
  Operation(
    name: 'level.fill_region',
    summary: 'Flood-fill the connected tiles matching the tile at col,row.',
    description:
        'Four-connected fill, like the studio\'s bucket tool. Returns how many tiles changed.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      _path,
      Param('entity', ParamType.string, required: true),
      Param('col', ParamType.integer, required: true, min: 0),
      Param('row', ParamType.integer, required: true, min: 0),
      Param('tileId', ParamType.integer, required: true, min: 0),
    ],
    handler: (ctx, a) => _edit(ctx, a, (doc, _) {
      final e = _tileEntity(doc, a);
      _inGrid(e, a);
      final tiles = List<Object?>.of(e.components['tileMap']!['tiles'] as List);
      _apply(
        FillRegionCommand(
          entity: e,
          col: a['col']! as int,
          row: a['row']! as int,
          tileId: a['tileId']! as int,
        ),
        doc,
      );
      final now = e.components['tileMap']!['tiles'] as List;
      var filled = 0;
      for (var i = 0; i < tiles.length; i++) {
        if (tiles[i] != now[i]) filled++;
      }
      return {'filled': filled};
    }),
  ),
];

LevelEntity _tileEntity(LevelDocument doc, Map<String, Object?> a) {
  final e = _entity(doc, a['entity']! as String);
  if (e.components['tileMap'] == null) {
    throw OpError(
      ErrorCode.invalidParams,
      '"${a['entity']}" has no tileMap component.',
    );
  }
  return e;
}

void _inGrid(LevelEntity e, Map<String, Object?> a) {
  final map = e.components['tileMap']!;
  final col = a['col']! as int, row = a['row']! as int;
  if (col >= (map['cols'] as int) || row >= (map['rows'] as int)) {
    throw OpError(
      ErrorCode.invalidParams,
      '($col, $row) is outside the ${map['cols']}x${map['rows']} grid.',
    );
  }
}
