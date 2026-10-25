import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;

import 'image_codec.dart';

/// Thin CLI adapter over `level.lint`: keeps the historical `game_agent lint`
/// invocation (including `--render <png>`) while loadability, reachability and
/// the structural PNG live in `engine_core`.
class LintCommand extends Command<int> {
  @override
  final name = 'lint';
  @override
  final description =
      'Validate a level/content JSON file without running the game.';

  LintCommand() {
    argParser.addOption(
      'render',
      help:
          'Also rasterize the level\'s TileMap (plus a marker per '
          'entity with a position) to a PNG at this path, so a human or '
          'agent can see the level\'s shape without running the game. '
          'Errors if the level has no tileMap component.',
    );
    argParser.addFlag(
      'playable',
      help:
          'Also check that every positioned entity is reachable from the '
          'spawn point (an entity whose name contains "player" or "spawn", '
          'case-insensitive) by walking, falling, and jumping over the '
          'TileMap -- the same heuristic the studio\'s own validator uses, '
          'so this and the validator never disagree. A conservative model, '
          'not a physics simulation: it can pass a level that needs a '
          'mechanic it does not know about (wall jumps, ladders, double '
          'jumps). Errors if the level has no tileMap component or no '
          'spawn entity.',
    );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      usageException(
        'Missing file path, e.g. `game_agent lint assets/level1.json`',
      );
    }

    final file = File(p.normalize(p.absolute(args.rest.first)));
    if (!file.existsSync()) {
      stderr.writeln('Error: ${file.path} does not exist.');
      return 1;
    }

    final renderPath = args['render'] as String?;
    final root = p.dirname(file.path);
    final result = await buildRegistry().call(
      'level.lint',
      {
        'path': p.basename(file.path),
        'playable': args['playable'] as bool,
        'includeRender': renderPath != null,
      },
      OpContext(
        project: ProjectRoot(root),
        actor: 'cli',
        imageCodec: const PackageImageCodec(),
      ),
    );

    if (!result.ok) {
      stderr.writeln('Error: ${result.error!.message}');
      if (result.error!.hint != null) stderr.writeln(result.error!.hint);
      return 1;
    }

    final data = (result.data as Map).cast<String, Object?>();
    final problems = (data['problems'] as List?)?.cast<String>() ?? const [];
    final ok = data['ok'] == true;
    final entities = data['entities'];

    if (entities is int) {
      stdout.writeln('${file.path}: OK ($entities entities)');
    }

    if (args['playable'] as bool) {
      if (ok || problems.any((p) => p.contains('unreachable'))) {
        final message = data['message'] as String? ?? '';
        if (message.contains('reachable') &&
            !problems.any((p) => p.contains('unreachable'))) {
          stdout.writeln('--playable: $message');
        }
      }
      for (final problem in problems.where(_isPlayableProblem)) {
        stderr.writeln(
          problem.contains('unreachable')
              ? '--playable: $problem'
              : 'Error: $problem',
        );
      }
    }

    for (final problem in problems.where((p) => !_isPlayableProblem(p))) {
      if (problem.startsWith('Not valid JSON: ')) {
        stderr.writeln(
          'Error: ${file.path} is not valid JSON: '
          '${problem.substring('Not valid JSON: '.length)}',
        );
      } else if (problem.startsWith('includeRender')) {
        stderr.writeln(
          'Error: ${problem.replaceFirst('includeRender', '--render')}',
        );
      } else {
        stderr.writeln(
          entities is int ? 'Error: $problem' : '${file.path}: $problem',
        );
      }
    }

    if (renderPath != null) {
      final b64 = data['pngBase64'] as String?;
      final meta = data['render'] as Map?;
      if (b64 == null) return 1;
      final out = File(p.normalize(p.absolute(renderPath)));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(base64Decode(b64));
      stdout.writeln(
        '${out.path}: rendered (${meta?['cols']}x${meta?['rows']} tiles, '
        '${meta?['markers']} entity markers)',
      );
    }

    return ok ? 0 : 1;
  }
}

bool _isPlayableProblem(String problem) =>
    problem.contains('playable') ||
    problem.contains('unreachable') ||
    problem.contains('spawn') ||
    problem.contains('solid tile');
