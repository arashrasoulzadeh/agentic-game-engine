import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../level_check.dart';
import '../operation.dart';
import '../param.dart';
import '../paths.dart';
import '../project/git_status.dart';
import '../project/project_search.dart';
import '../project/project_tree.dart';
import '../project/studio_project.dart';
import '../result.dart';

StudioProject _project(OpContext ctx) => StudioProject.open(ctx.project!.root);

String? _pubspecField(String text, String key) => RegExp(
  '^$key:\\s*(.+)\$',
  multiLine: true,
).firstMatch(text)?.group(1)?.trim().replaceAll(RegExp('[\'"]'), '');

Map<String, Object?> _info(ProjectRoot root) {
  final pubspec = File(p.join(root.root, 'pubspec.yaml')).readAsStringSync();
  final project = StudioProject.open(root.root);
  final engine = RegExp(
    r'^\s{2}(engine_\w+):\s*$[\s\S]*?ref:\s*(\S+)',
    multiLine: true,
  );
  final refs = <String, String>{};
  for (final m in engine.allMatches(pubspec)) {
    refs[m.group(1)!] = m.group(2)!;
  }
  int count(String dir, String ext) {
    final d = Directory(p.join(root.root, dir));
    return d.existsSync()
        ? d
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith(ext))
              .length
        : 0;
  }

  return {
    'name': _pubspecField(pubspec, 'name'),
    'root': root.root,
    'version': _pubspecField(pubspec, 'version'),
    'engine': refs,
    'flutterProject': pubspec.contains('flutter:'),
    'counts': {
      'levels': project.levelPaths().length,
      'graphs': project.graphPaths().length,
      'prefabs': count('assets/prefabs', '.json'),
      'codeFiles': project.codeFiles().length,
    },
  };
}

/// `project.*`: opening a project and looking at it.
List<Operation> projectOperations() => [
  Operation(
    name: 'project.open',
    summary:
        'Open a game project folder; every project operation then works inside it.',
    description:
        'Sets the one open project of this session. The folder must contain `pubspec.yaml` and `assets/levels`. '
        'This is the only operation that takes an absolute path. Servers started with a fixed `--project` refuse it.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    params: const [
      Param(
        'path',
        ParamType.string,
        required: true,
        positional: true,
        description: 'Absolute or working-directory-relative project folder.',
      ),
    ],
    errors: {
      ErrorCode.notFound:
          'The folder, its pubspec.yaml or assets/levels is missing.',
      ErrorCode.forbidden: 'This server is fixed to one project.',
    },
    handler: (ctx, a) {
      if (!ctx.allowProjectSwitch && ctx.project != null ||
          !ctx.allowProjectOpen) {
        throw OpError(
          ErrorCode.forbidden,
          'This server cannot open or switch projects.',
        );
      }
      try {
        StudioProject.open(a['path']! as String);
      } on ProjectOpenException catch (e) {
        throw OpError(ErrorCode.notFound, e.message);
      }
      ctx.project = ProjectRoot(a['path']! as String);
      return OpOutcome.data(_info(ctx.project!));
    },
  ),
  Operation(
    name: 'project.close',
    summary: 'Close the open project.',
    description:
        'Forgets the open project; project operations fail until another is opened.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      ctx.project = null;
      return const OpOutcome.data({'closed': true});
    },
  ),
  Operation(
    name: 'project.info',
    summary: 'Name, version, engine refs and counts of the open project.',
    description:
        'Read from `pubspec.yaml` and the project folders. Counts levels, graphs, prefabs and Dart files.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) => OpOutcome.data(_info(ctx.project!)),
  ),
  Operation(
    name: 'project.tree',
    summary:
        'List the project files (generated and hidden folders left out), optionally by kind.',
    description:
        'The same tree the studio shows. `filter` keeps one kind of file: code, level, graph, image, data or other.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param(
        'filter',
        ParamType.enumeration,
        options: ['all', 'code', 'level', 'graph', 'image', 'data', 'other'],
        defaultValue: 'all',
      ),
      Param('limit', ParamType.integer, min: 1, max: 20000, defaultValue: 2000),
    ],
    handler: (ctx, a) {
      final all = listProjectTree(ctx.project!.root);
      final kind = FileKind.values.firstWhere((k) => k.name == a['filter']);
      final shown = kind == FileKind.all ? all : filterFiles(all, kind);
      final limit = a['limit']! as int;
      return OpOutcome.data(
        {
          'entries': [
            for (final e in shown.take(limit))
              {
                'path': e.relativePath,
                'isDirectory': e.isDirectory,
                'kind': kindOf(e).name,
                'depth': e.depth,
              },
          ],
          'truncated': shown.length > limit,
          'total': shown.length,
        },
        warnings: [
          if (shown.length > limit) 'showing $limit of ${shown.length} entries',
        ],
      );
    },
    examples: const [
      Example('Only levels', {'filter': 'level'}),
    ],
  ),
  Operation(
    name: 'project.search',
    summary: 'Find text in the project\'s code, level, graph and data files.',
    description:
        'Case-insensitive substring search, as the studio\'s Find in project. Returns file, line and the line text.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('query', ParamType.string, required: true, positional: true),
      Param('limit', ParamType.integer, min: 1, max: 2000, defaultValue: 200),
    ],
    handler: (ctx, a) {
      final root = ctx.project!.root;
      final found = searchProject(
        root,
        listProjectTree(root),
        a['query']! as String,
      );
      final limit = a['limit']! as int;
      return OpOutcome.data({
        'matches': [
          for (final m in found.take(limit))
            {
              'path': m.relativePath,
              'line': m.line,
              'column': m.character,
              'text': m.lineText,
            },
        ],
        'truncated': found.length > limit,
      });
    },
  ),
  Operation(
    name: 'project.validate',
    summary: 'Check every level in the project against the component schemas.',
    description:
        'Loads each file under `assets/levels` (not the play-test snapshot) and reports schema errors and warnings '
        'per file, like `game_agent studio validate`. `strict` also counts warnings as failures in `ok`.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param(
        'strict',
        ParamType.boolean,
        defaultValue: false,
        description: 'Treat warnings as failures.',
      ),
    ],
    handler: (ctx, a) {
      final project = _project(ctx);
      var errors = 0, warnings = 0;
      final levels = <Map<String, Object?>>[];
      for (final rel in project.levelPaths()) {
        final text = ctx.files.read(ctx.project!.resolve(rel));
        final check = text == null
            ? const LevelCheck(fatal: 'unreadable')
            : checkLevelText(text);
        errors += check.errors.length + (check.fatal == null ? 0 : 1);
        warnings += check.warnings.length;
        levels.add({'path': rel, ...check.toJson()});
      }
      return OpOutcome.data({
        'ok': errors == 0 && !(a['strict'] == true && warnings > 0),
        'levels': levels,
        'errors': errors,
        'warnings': warnings,
      });
    },
  ),
  Operation(
    name: 'project.git_status',
    summary:
        'Which files git sees as changed (empty when the project is not in a git repository).',
    description:
        'M modified, A added, D deleted, R renamed, ? untracked, ! conflicted. Paths are relative to the project.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) async {
      final changes = await readGitStatus(ctx.project!.root);
      return OpOutcome.data({
        'available':
            changes.isNotEmpty ||
            Directory(p.join(ctx.project!.root, '.git')).existsSync(),
        'changes': {for (final e in changes.entries) e.key: e.value.badge},
      });
    },
  ),
];
