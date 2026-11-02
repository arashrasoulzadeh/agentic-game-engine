import 'dart:convert';

import '../../idle/definition.dart';
import '../context.dart';
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
      final out = _collectProblems(ctx);
      return OpOutcome.data({
        'ok': !out.any((p) => p['severity'] == 'error'),
        'problems': out,
      });
    },
  ),
  Operation(
    name: 'project.doctor',
    summary:
        'A health check of the project: content problems and engine dependency wiring.',
    description:
        'Runs the checks that can be made without running the game: every level, graph and the idle game '
        '(the same findings as `project.problems`), the project folder layout, and whether the `engine_*` '
        'dependencies in `pubspec.yaml` agree (same git url and ref, no mix of git and path). Returns a list of '
        'checks with `status` `ok`, `warn` or `error`; `ok` is true when none is an error. Checks that need the '
        'game\'s code (such as `World.validateSystemOrder`) belong in a test of your game: see '
        '`GameTester` in `engine_core_testing`.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final checks = <Map<String, Object?>>[];
      void add(String name, String status, String detail) =>
          checks.add({'name': name, 'status': status, 'detail': detail});

      final problems = _collectProblems(ctx);
      final errors = problems.where((p) => p['severity'] == 'error').length;
      final warnings = problems.length - errors;
      add(
        'content',
        errors > 0 ? 'error' : (warnings > 0 ? 'warn' : 'ok'),
        errors + warnings == 0
            ? 'levels, graphs and idle game are clean'
            : '$errors error(s), $warnings warning(s): run project.problems for the list',
      );

      final project = ctx.project!;
      final levels = StudioProject.open(project.root).levelPaths();
      add(
        'layout',
        levels.isEmpty ? 'warn' : 'ok',
        levels.isEmpty
            ? 'no levels under assets/levels'
            : '${levels.length} level file(s) under assets/levels',
      );

      final pubspec = ctx.files.read(project.resolve('pubspec.yaml'));
      if (pubspec == null) {
        add('dependencies', 'warn', 'no pubspec.yaml in the project root');
      } else {
        final (status, detail) = checkEngineDependencies(pubspec);
        add('dependencies', status, detail);
      }
      return OpOutcome.data({
        'ok': !checks.any((c) => c['status'] == 'error'),
        'checks': checks,
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

/// Every problem in the open project's levels, graphs and idle game, as flat
/// `{file, severity, message}` entries. Shared by `project.problems` and
/// `project.doctor` so both always agree.
List<Map<String, Object?>> _collectProblems(OpContext ctx) {
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
  return out;
}

/// Judges the `engine_*` dependencies of a pubspec: returns `(status, detail)`
/// with status `ok`, `warn` or `error`.
///
/// pub cannot solve a project whose engine packages are fetched from different
/// git urls or refs (they depend on each other through the same self-referencing
/// git dependency), so a mismatch is an error. Local `path:` dependencies work
/// but break for anyone else fetching the project, so they warn.
(String, String) checkEngineDependencies(String pubspec) {
  final deps = <String, Map<String, String>>{};
  String? section;
  String? dep;
  var inGit = false;
  for (final raw in pubspec.split('\n')) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final indent = raw.length - raw.trimLeft().length;
    final line = raw.trim();
    if (indent == 0) {
      section = line.endsWith(':') ? line.substring(0, line.length - 1) : null;
      dep = null;
      continue;
    }
    if (section != 'dependencies' && section != 'dev_dependencies') continue;
    if (indent == 2) {
      final m = RegExp(r'^(engine_\w+):\s*(.*)$').firstMatch(line);
      dep = m?.group(1);
      inGit = false;
      if (dep != null) {
        deps[dep] = {};
        final inline = m!.group(2)!.trim();
        if (inline.isNotEmpty) deps[dep]!['kind'] = 'hosted';
      }
      continue;
    }
    if (dep == null) continue;
    final kv = RegExp(r'^(\w+):\s*(.*)$').firstMatch(line);
    if (kv == null) continue;
    final key = kv.group(1)!;
    final value = kv.group(2)!.trim();
    if (key == 'git') {
      deps[dep]!['kind'] = 'git';
      inGit = true;
      if (value.isNotEmpty) deps[dep]!['url'] = value;
    } else if (key == 'path' && !inGit) {
      deps[dep]!['kind'] = 'path';
    } else if (key == 'url' && inGit) {
      deps[dep]!['url'] = value;
    } else if (key == 'ref' && inGit) {
      deps[dep]!['ref'] = value;
    }
  }
  if (deps.isEmpty) {
    return ('warn', 'no engine_* dependencies in pubspec.yaml');
  }
  final paths = [
    for (final e in deps.entries)
      if (e.value['kind'] == 'path') e.key,
  ];
  final git = {
    for (final e in deps.entries)
      if (e.value['kind'] == 'git') e.key: e.value,
  };
  final urls = {for (final g in git.values) g['url'] ?? '(none)'};
  final refs = {for (final g in git.values) g['ref'] ?? '(default branch)'};
  if (urls.length > 1 || refs.length > 1) {
    final detail = [
      for (final e in git.entries)
        '${e.key}: ${e.value['url'] ?? '(none)'} @ ${e.value['ref'] ?? '(default branch)'}',
    ].join('; ');
    return (
      'error',
      'engine packages come from different git urls or refs, which pub cannot '
          'solve together ($detail). Use one url and one ref for all of them.',
    );
  }
  if (paths.isNotEmpty) {
    return (
      'warn',
      '${paths.join(', ')} use a local path: dependency, which works only on '
          'this machine. Fine for development; use the git dependency before sharing.',
    );
  }
  if (git.isEmpty) {
    return ('ok', '${deps.length} engine package(s) from a hosted version');
  }
  return (
    'ok',
    '${git.length} engine package(s), all from ${urls.single} @ ${refs.single}',
  );
}
