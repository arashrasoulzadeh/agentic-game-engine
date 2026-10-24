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
      'prefabs': count('prefabs', '.json'),
      'codeFiles': project.codeFiles().length,
    },
  };
}

/// `project.*`: opening a project and looking at it.
List<Operation> projectOperations() => [
  Operation(
    name: 'project.create',
    summary:
        'Generate a new game project from a starter template (needs the Flutter SDK; available from the CLI).',
    description:
        'Implemented by `game_agent create` because it runs `flutter create` and `pub get`; servers without Flutter '
        'list it under `engine.capabilities.unsupported`.',
    kind: OperationKind.write,
    scope: OperationScope.pure,
    requiresFlutter: true,
    params: const [
      Param('name', ParamType.string, required: true, positional: true),
      Param(
        'template',
        ParamType.enumeration,
        options: ['default_game', 'strategy_game', 'idle_game'],
        defaultValue: 'default_game',
      ),
      Param('org', ParamType.string, defaultValue: 'com.example'),
      Param('outputDir', ParamType.string, defaultValue: '.'),
      Param('ref', ParamType.string, defaultValue: 'main'),
    ],
    handler: (ctx, a) => throw OpError(
      ErrorCode.unsupported,
      'project.create needs the Flutter SDK; run game_agent create.',
    ),
  ),
  Operation(
    name: 'project.upgrade',
    summary:
        'Upgrade a project to the current engine version (needs the Flutter SDK; available from the CLI).',
    description:
        'Implemented by `game_agent upgrade` because it runs `flutter pub upgrade`.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    requiresFlutter: true,
    handler: (ctx, a) => throw OpError(
      ErrorCode.unsupported,
      'project.upgrade needs the Flutter SDK; run game_agent upgrade.',
    ),
  ),
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
      if (ctx.allowOpen.isNotEmpty) {
        final abs = ProjectRoot(a['path']! as String).root;
        final allowed = ctx.allowOpen.any(
          (g) => RegExp(
            '^${g.split('*').map(RegExp.escape).join('.*')}\$',
          ).hasMatch(abs),
        );
        if (!allowed) {
          throw OpError(
            ErrorCode.forbidden,
            'This server may not open $abs.',
            hint: 'Allowed: ${ctx.allowOpen.join(', ')}',
          );
        }
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
    errors: {ErrorCode.forbidden: 'This server is fixed to one project.'},
    handler: (ctx, a) {
      if (!ctx.allowProjectSwitch) {
        throw OpError(
          ErrorCode.forbidden,
          'This server is fixed to its project and cannot close it.',
        );
      }
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
    name: 'project.read_file',
    summary: 'Read one text file of the project.',
    description:
        'Any UTF-8 text file inside the project, up to 1 MiB. Binary files are refused, and so is the API token '
        '(`.studio/api-token`).',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
    ],
    errors: {
      ErrorCode.notFound: 'No such file.',
      ErrorCode.tooLarge: 'Over 1 MiB.',
      ErrorCode.forbidden: 'The file is withheld or not text.',
    },
    handler: (ctx, a) {
      final rel = (a['path']! as String).replaceAll('\\', '/');
      final abs = ctx.project!.resolve(rel);
      if (rel == '.studio/api-token' || rel.endsWith('/.studio/api-token')) {
        throw OpError(ErrorCode.forbidden, 'That file is never served.');
      }
      final String? text;
      try {
        text = ctx.files.read(abs);
      } on Exception {
        throw OpError(
          ErrorCode.forbidden,
          '$rel is not readable as UTF-8 text.',
        );
      }
      if (text == null) throw OpError(ErrorCode.notFound, 'No file at $rel.');
      if (text.length > 1024 * 1024) {
        throw OpError(ErrorCode.tooLarge, '$rel is larger than 1 MiB.');
      }
      if (text.contains('\u0000') || text.contains('\uFFFD')) {
        throw OpError(ErrorCode.forbidden, '$rel is not a UTF-8 text file.');
      }
      return OpOutcome.data({'path': rel, 'text': text, 'bytes': text.length});
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
