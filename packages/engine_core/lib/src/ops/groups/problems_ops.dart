import 'dart:convert';

import '../../idle/definition.dart';
import '../level_check.dart';
import '../operation.dart';
import '../param.dart';
import '../project/project_symbols.dart';
import '../project/studio_project.dart';
import '../result.dart';
import 'graph_ops.dart';

/// `project.problems`: everything wrong in the project, flattened into one list an agent can work through.
List<Operation> problemOperations() => [
  Operation(
    name: 'project.problems',
    summary:
        'Every problem in the project\'s levels, graphs and idle game as one flat list.',
    description:
        'Combines `project.validate` (levels), the graph validators and the idle definition check. Each entry has the '
        'file, a severity (`error` or `warning`) and a message; fix errors first. Empty means the project is clean.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final project = StudioProject.open(ctx.project!.root);
      final out = <Map<String, Object?>>[];
      void add(String file, String severity, String message) =>
          out.add({'file': file, 'severity': severity, 'message': message});

      for (final rel in project.levelPaths()) {
        final text = ctx.files.read(ctx.project!.resolve(rel));
        final check = text == null
            ? const LevelCheck(fatal: 'unreadable')
            : checkLevelText(text);
        if (check.fatal != null) add(rel, 'error', check.fatal!);
        for (final e in check.errors) {
          add(rel, 'error', e);
        }
        for (final w in check.warnings) {
          add(rel, 'warning', w);
        }
      }
      for (final rel in project.graphPaths()) {
        final text = ctx.files.read(ctx.project!.resolve(rel));
        if (text == null) continue;
        final r = checkGraphText(text);
        if (r.fatal != null) add(rel, 'error', r.fatal!);
        for (final i in r.issues) {
          add(rel, 'error', i.message);
        }
      }
      const idleRel = 'assets/idle_game.json';
      final idleText = ctx.files.read(ctx.project!.resolve(idleRel));
      if (idleText != null) {
        try {
          for (final p in validateIdleDefinition(
            (jsonDecode(idleText) as Map).cast<String, dynamic>(),
          )) {
            add(idleRel, 'error', p);
          }
        } on Object catch (e) {
          add(idleRel, 'error', 'not a JSON object ($e)');
        }
      }
      return OpOutcome.data({
        'ok': !out.any((p) => p['severity'] == 'error'),
        'problems': out,
      });
    },
  ),
  Operation(
    name: 'project.symbols',
    summary:
        'The names a project defines: its classes, atlas ids, entity names and the engine\'s components.',
    description:
        'Found by scanning `lib/*.dart` for class declarations, `assets/studio_atlases.json`, the entity names of every '
        'level and the component schemas. Use `prefix` to get completions (case-sensitive) instead of the full lists.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param(
        'prefix',
        ParamType.string,
        description: 'Only names starting with this.',
      ),
    ],
    handler: (ctx, a) {
      final symbols = ProjectSymbols.scan(ctx.project!.root);
      final prefix = a['prefix'] as String?;
      if (prefix != null) {
        return OpOutcome.data({
          'completions': [
            for (final (name, kind) in symbols.completionsFor(prefix))
              {'name': name, 'kind': kind},
          ],
        });
      }
      return OpOutcome.data({
        'classes': symbols.classes.toList()..sort(),
        'atlasIds': symbols.atlasIds.toList()..sort(),
        'entityNames': symbols.entityNames.toList()..sort(),
        'components': symbols.components.toList()..sort(),
      });
    },
  ),
];
