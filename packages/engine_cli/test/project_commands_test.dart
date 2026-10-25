import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/create_command.dart';
import 'package:engine_cli/src/upgrade_command.dart';
import 'package:engine_cli/src/process_utils.dart';
import 'package:engine_cli/src/template.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String originalDirectory;
  late List<List<Object?>> calls;
  final templates = Directory('templates/default_game').absolute;

  Future<void> runProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([executable, args, workingDirectory]);
    if (args.first == 'create') {
      Directory('$workingDirectory/${args.last}').createSync(recursive: true);
    }
  }

  setUp(() {
    originalDirectory = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('project_commands_');
    calls = [];
  });
  tearDown(() {
    Directory.current = originalDirectory;
    tmp.deleteSync(recursive: true);
  });

  CommandRunner<int> runner() => CommandRunner<int>('game_agent', 'test')
    ..addCommand(
      CreateCommand(
        runProcess: runProcess,
        findTemplate: (name) {
          expect(name, 'default_game');
          return templates;
        },
      ),
    )
    ..addCommand(UpgradeCommand(runProcess: runProcess));

  test('create validates names before running external commands', () async {
    for (final args in [
      <String>[],
      ['Bad-name'],
    ]) {
      await expectLater(
        runner().run(['create', ...args]),
        throwsA(isA<UsageException>()),
      );
    }
    expect(calls, isEmpty);
  });

  test('create refuses to overwrite an existing directory', () async {
    Directory('${tmp.path}/my_game').createSync();
    expect(
      await runner().run(['create', 'my_game', '--output-dir', tmp.path]),
      1,
    );
    expect(calls, isEmpty);
  });

  test(
    'create writes real templates and fetches from the generated directory',
    () async {
      expect(
        await runner().run([
          'create',
          'my_game',
          '--output-dir',
          tmp.path,
          '--org',
          'org.test',
          '--engine-repo',
          'https://example.com/engine.git',
          '--ref',
          'test-ref',
        ]),
        0,
      );
      expect(calls, [
        [
          'flutter',
          [
            'create',
            '--platforms=android,ios,web',
            '--org',
            'org.test',
            'my_game',
          ],
          tmp.path,
        ],
        [
          'flutter',
          ['pub', 'get'],
          '${tmp.path}/my_game',
        ],
      ]);
      final pubspec = File(
        '${tmp.path}/my_game/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('name: my_game'));
      expect(pubspec, contains('https://example.com/engine.git'));
      expect('ref: test-ref'.allMatches(pubspec).length, 3);
      expect(pubspec, isNot(contains('{{')));
      final main = File('${tmp.path}/my_game/lib/main.dart').readAsStringSync();
      expect(main, contains('spawnEnemy'));
      expect(main, contains('spawnHealthHudBar'));
      expect(main, contains('dealPickupOnTouch'));
      expect(main, contains('PauseMenu'));
      expect(main, contains('colorblindMode'));
      expect(
        File('${tmp.path}/my_game/assets/i18n/en.json').existsSync(),
        isTrue,
      );
    },
  );

  test(
    'upgrade reports a missing pubspec or missing engine dependency',
    () async {
      Directory.current = tmp;
      expect(await runner().run(['upgrade']), 1);
      File('pubspec.yaml').writeAsStringSync('name: unrelated\n');
      expect(await runner().run(['upgrade']), 1);
      expect(calls, isEmpty);
    },
  );

  test(
    'upgrade replaces all engine refs and preserves unrelated content',
    () async {
      Directory.current = tmp;
      final pubspec = File('pubspec.yaml');
      final original =
          'name: game\ndependencies:\n${[
            for (final name in ['engine_core', 'engine_flutter', 'engine_platformer']) '  $name:\n    git:\n      url: https://example.com/engine.git\n      path: packages/$name\n      ref: old\n',
          ].join()}  other: ^1.0.0\n';
      pubspec.writeAsStringSync(original);
      expect(await runner().run(['upgrade', '--ref', 'new']), 0);
      expect(
        pubspec.readAsStringSync(),
        original.replaceAll('ref: old', 'ref: new'),
      );
      expect(calls, [
        [
          'flutter',
          ['pub', 'upgrade'],
          null,
        ],
      ]);
      expect(await runner().run(['upgrade', '--ref', 'new']), 0);
      expect(
        pubspec.readAsStringSync(),
        original.replaceAll('ref: old', 'ref: new'),
      );
    },
  );

  test(
    'template lookup resolves bundled paths and diagnoses missing templates',
    () {
      final script = File('$originalDirectory/bin/game_agent.dart').uri;
      expect(
        templateRoot('default_game', scriptUri: script).path,
        templates.path,
      );
      expect(
        () => templateRoot('missing', scriptUri: script),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    },
  );

  test(
    'streamed commands wait for output and report nonzero exit codes',
    () async {
      final script = File('${tmp.path}/child.dart')
        ..writeAsStringSync(
          "import 'dart:io'; void main(List<String> args) { stdout.writeln('child output'); stderr.writeln('child error'); exit(int.parse(args.first)); }",
        );
      await runStreamed(Platform.resolvedExecutable, [
        script.path,
        '0',
      ], workingDirectory: tmp.path);
      await expectLater(
        runStreamed(Platform.resolvedExecutable, [script.path, '7']),
        throwsA(
          isA<ProcessException>().having((e) => e.errorCode, 'exit code', 7),
        ),
      );
    },
  );

  test(
    'create --template strategy_game writes the strategy template and rejects unknown ones',
    () async {
      final asked = <String>[];
      final strategyRunner = CommandRunner<int>('game_agent', 'test')
        ..addCommand(
          CreateCommand(
            runProcess: runProcess,
            findTemplate: (name) {
              asked.add(name);
              return Directory('templates/$name').absolute;
            },
          ),
        );
      expect(
        await strategyRunner.run([
          'create',
          'war_game',
          '--output-dir',
          tmp.path,
          '--template',
          'strategy_game',
        ]),
        0,
      );
      expect(asked, ['strategy_game']);
      final pubspec = File(
        '${tmp.path}/war_game/pubspec.yaml',
      ).readAsStringSync();
      expect(pubspec, contains('packages/engine_strategy'));
      expect(pubspec, isNot(contains('engine_platformer')));
      final warMain = File(
        '${tmp.path}/war_game/lib/main.dart',
      ).readAsStringSync();
      expect(warMain, contains('installStrategySystems'));
      expect(warMain, contains('skirmish.level.json'));
      expect(
        File(
          '${tmp.path}/war_game/assets/levels/skirmish.level.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('${tmp.path}/war_game/pubspec.yaml').readAsStringSync(),
        contains('assets/levels/skirmish.level.json'),
      );
      expect(warMain, contains('PauseMenu'));
      expect(
        File('${tmp.path}/war_game/assets/i18n/en.json').existsSync(),
        isTrue,
      );

      await expectLater(
        strategyRunner.run([
          'create',
          'x_game',
          '--output-dir',
          tmp.path,
          '--template',
          'nope',
        ]),
        throwsA(isA<UsageException>()),
      );
    },
  );

  test('upgrade also repins engine_strategy', () async {
    Directory.current = tmp;
    File('pubspec.yaml').writeAsStringSync('''
dependencies:
  engine_strategy:
    git:
      url: https://example.com/e.git
      path: packages/engine_strategy
      ref: main
''');
    expect(await runner().run(['upgrade', '--ref', 'v2']), 0);
    expect(File('pubspec.yaml').readAsStringSync(), contains('ref: v2'));
  });

  test('upgrade also repins engine_idle', () async {
    Directory.current = tmp;
    File('pubspec.yaml').writeAsStringSync('''
dependencies:
  engine_idle:
    git:
      url: https://example.com/e.git
      path: packages/engine_idle
      ref: main
''');
    expect(await runner().run(['upgrade', '--ref', 'v2']), 0);
    expect(File('pubspec.yaml').readAsStringSync(), contains('ref: v2'));
  });

  test('create --template idle_game writes the idle template', () async {
    final asked = <String>[];
    final idleRunner = CommandRunner<int>('game_agent', 'test')
      ..addCommand(
        CreateCommand(
          runProcess: runProcess,
          findTemplate: (name) {
            asked.add(name);
            return Directory('templates/$name').absolute;
          },
        ),
      );
    expect(
      await idleRunner.run([
        'create',
        'cookie_game',
        '--output-dir',
        tmp.path,
        '--template',
        'idle_game',
      ]),
      0,
    );
    expect(asked, ['idle_game']);
    final pubspec = File(
      '${tmp.path}/cookie_game/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('packages/engine_idle'));
    expect(pubspec, isNot(contains('engine_platformer')));
    final main =
        File('${tmp.path}/cookie_game/lib/main.dart').readAsStringSync();
    expect(main, contains('loadIdleDefinition'));
    expect(main, contains('ChallengePanel'));
    expect(main, contains('GoldenOffer'));
    expect(main, contains('StatsPanel'));
    expect(main, contains('FileSaveStore'));
    expect(main, contains('openIdleSaveStore'));
    expect(main, contains('AutoBuySystem'));
    expect(main, contains('onDouble'));
    expect(main, contains('LogReturnNotifier'));
    expect(main, contains('resourceIds'));
    expect(main, contains('showIdlePauseMenu'));
    expect(main, contains('IdleSfx'));
    expect(main, contains('PrestigeShop'));
    expect(pubspec, contains('path_provider'));
    final def = File(
      '${tmp.path}/cookie_game/assets/idle_game.json',
    ).readAsStringSync();
    expect(def, contains('"challenges"'));
    expect(def, contains('"golden"'));
    expect(def, contains('"prestiges"'));
    expect(def, contains('"autoBuyer"'));
    expect(def, contains('"bonusPerOwned"'));
    expect(def, contains('"gems": "5"'));
    expect(
      File('${tmp.path}/cookie_game/test/widget_test.dart').readAsStringSync(),
      contains('cookie_game'),
    );
  });
}
