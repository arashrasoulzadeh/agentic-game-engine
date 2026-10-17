// End-to-end smoke test (docs/studio/design.md 2.6): create a project with the real
// `game_agent` binary, edit it with the real `studio` subcommands (not an
// in-process CommandRunner — a genuine subprocess, the same way a user or CI
// would run it), validate it, then load the result into a plain `World` and
// tick it for a few frames with no Flutter involved at all — "headless" here
// means no `GameRunner`/rendering, just the ECS doing real work.
//
// Run with `dart run tool/e2e_check.dart` from `packages/engine_cli`. Exits
// non-zero on any failure, so it's safe to wire into CI as a single step.
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final packageRoot = Directory.current.path;
  final binPath = p.join(packageRoot, 'bin', 'game_agent.dart');
  if (!File(binPath).existsSync()) {
    stderr.writeln(
      'Error: could not find $binPath -- run this from packages/engine_cli.',
    );
    exitCode = 1;
    return;
  }

  final tmp = Directory.systemTemp.createTempSync('e2e_check_');
  try {
    await _step('create', [binPath, 'create', 'e2e_game'], cwd: tmp.path);
    final project = p.join(tmp.path, 'e2e_game');
    final levelPath = p.join(project, 'assets', 'levels', 'main.level.json');

    await _step('add-entity', [
      binPath,
      'studio',
      'add-entity',
      levelPath,
      '--name',
      'e2eCoin',
      '--component',
      'pushable',
    ]);
    await _step('move-entity', [
      binPath,
      'studio',
      'move-entity',
      levelPath,
      '--entity',
      'e2eCoin',
      '--x',
      '5',
      '--y',
      '5',
    ]);
    await _step('set-field', [
      binPath,
      'studio',
      'set-field',
      levelPath,
      '--entity',
      'e2eCoin',
      '--component',
      'pushable',
      '--field',
      'pushSpeed',
      '--value',
      '2.5',
    ]);
    await _step('validate', [binPath, 'studio', 'validate', project]);

    print('== headless load ==');
    final json =
        jsonDecode(File(levelPath).readAsStringSync()) as Map<String, dynamic>;
    final world = World(width: 800, height: 480);
    registerCoreComponents(world);
    world.addSystem(MovementSystem());
    final named = Level.loadInto(world, json);

    if (!named.containsKey('e2eCoin')) {
      throw StateError(
        'e2eCoin (added by the CLI above) did not come back out of Level.loadInto',
      );
    }
    final before = world.entities.count;
    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    if (world.entities.count != before) {
      throw StateError(
        'entity count changed while ticking (was $before, now '
        '${world.entities.count}) -- nothing in this level should destroy '
        'entities on its own',
      );
    }
    print(
      'OK: created, edited via studio subcommands, validated, loaded into a '
      'World, and ticked 60 frames with $before entities and no exception.',
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Future<void> _step(String label, List<String> args, {String? cwd}) async {
  print('== $label ==');
  print('\$ dart ${args.join(' ')}');
  final result = await Process.run('dart', args, workingDirectory: cwd);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      'dart',
      args,
      '$label exited with ${result.exitCode}',
      result.exitCode,
    );
  }
}
