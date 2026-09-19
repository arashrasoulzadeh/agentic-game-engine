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

  Future<void> runProcess(String executable, List<String> args,
      {String? workingDirectory}) async {
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
    ..addCommand(CreateCommand(
      runProcess: runProcess,
      findTemplate: (name) {
        expect(name, 'default_game');
        return templates;
      },
    ))
    ..addCommand(UpgradeCommand(runProcess: runProcess));

  test('create validates names before running external commands', () async {
    for (final args in [<String>[], ['Bad-name']]) {
      await expectLater(runner().run(['create', ...args]), throwsA(isA<UsageException>()));
    }
    expect(calls, isEmpty);
  });

  test('create refuses to overwrite an existing directory', () async {
    Directory('${tmp.path}/my_game').createSync();
    expect(await runner().run(['create', 'my_game', '--output-dir', tmp.path]), 1);
    expect(calls, isEmpty);
  });

  test('create writes real templates and fetches from the generated directory', () async {
    expect(await runner().run([
      'create', 'my_game', '--output-dir', tmp.path,
      '--org', 'org.test', '--engine-repo', 'https://example.com/engine.git',
      '--ref', 'test-ref',
    ]), 0);
    expect(calls, [
      ['flutter', ['create', '--platforms=android,ios,web', '--org', 'org.test', 'my_game'], tmp.path],
      ['flutter', ['pub', 'get'], '${tmp.path}/my_game'],
    ]);
    final pubspec = File('${tmp.path}/my_game/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: my_game'));
    expect(pubspec, contains('https://example.com/engine.git'));
    expect('ref: test-ref'.allMatches(pubspec).length, 3);
    expect(pubspec, isNot(contains('{{')));
    expect(File('${tmp.path}/my_game/lib/main.dart').existsSync(), isTrue);
  });

  test('upgrade reports a missing pubspec or missing engine dependency', () async {
    Directory.current = tmp;
    expect(await runner().run(['upgrade']), 1);
    File('pubspec.yaml').writeAsStringSync('name: unrelated\n');
    expect(await runner().run(['upgrade']), 1);
    expect(calls, isEmpty);
  });

  test('upgrade replaces all engine refs and preserves unrelated content', () async {
    Directory.current = tmp;
    final pubspec = File('pubspec.yaml');
    final original = 'name: game\ndependencies:\n${[
      for (final name in ['engine_core', 'engine_flutter', 'engine_platformer'])
        '  $name:\n    git:\n      url: https://example.com/engine.git\n      path: packages/$name\n      ref: old\n',
    ].join()}  other: ^1.0.0\n';
    pubspec.writeAsStringSync(original);
    expect(await runner().run(['upgrade', '--ref', 'new']), 0);
    expect(pubspec.readAsStringSync(), original.replaceAll('ref: old', 'ref: new'));
    expect(calls, [['flutter', ['pub', 'upgrade'], null]]);
    expect(await runner().run(['upgrade', '--ref', 'new']), 0);
    expect(pubspec.readAsStringSync(), original.replaceAll('ref: old', 'ref: new'));
  });

  test('template lookup resolves bundled paths and diagnoses missing templates', () {
    final script = File('$originalDirectory/bin/game_agent.dart').uri;
    expect(templateRoot('default_game', scriptUri: script).path, templates.path);
    expect(() => templateRoot('missing', scriptUri: script),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('missing'))));
  });

  test('streamed commands wait for output and report nonzero exit codes', () async {
    final script = File('${tmp.path}/child.dart')
      ..writeAsStringSync("import 'dart:io'; void main(List<String> args) { stdout.writeln('child output'); stderr.writeln('child error'); exit(int.parse(args.first)); }");
    await runStreamed(Platform.resolvedExecutable, [script.path, '0'], workingDirectory: tmp.path);
    await expectLater(
      runStreamed(Platform.resolvedExecutable, [script.path, '7']),
      throwsA(isA<ProcessException>().having((e) => e.errorCode, 'exit code', 7)),
    );
  });
}
