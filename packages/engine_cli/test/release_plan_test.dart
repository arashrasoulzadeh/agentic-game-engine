import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/build_release_command.dart';
import 'package:test/test.dart';

const _gradleReadingKeys =
    'val keystoreProperties = Properties(); rootProject.file("key.properties")';

void main() {
  group('the command', () {
    late Directory project;
    setUp(() {
      project = Directory.systemTemp.createTempSync('release');
      File(
        '${project.path}/pubspec.yaml',
      ).writeAsStringSync('name: g\nversion: 2.0.0+7\n');
      Directory('${project.path}/android/app').createSync(recursive: true);
    });
    tearDown(() => project.deleteSync(recursive: true));

    Future<int> run(List<String> args) async {
      final runner = CommandRunner<int>('game_agent', 't')
        ..addCommand(BuildReleaseCommand());
      final code = await IOOverrides.runZoned<Future<int?>>(
        () => runner.run([
          'build-release',
          '-d',
          project.path,
          '--dry-run',
          ...args,
        ]),
        stdout: () => _Quiet(),
      );
      return code ?? 0;
    }

    test(
      'a dry run with a good setup succeeds and leaves no key.properties behind',
      () async {
        File(
          '${project.path}/android/app/build.gradle.kts',
        ).writeAsStringSync(_gradleReadingKeys);
        final jks = File('${project.path}/k.jks')..writeAsStringSync('x');
        final code = await run([
          '--keystore-path',
          jks.path,
          '--keystore-password',
          'a',
          '--key-alias',
          'b',
          '--key-password',
          'c',
        ]);
        expect(code, 0);
        expect(
          File('${project.path}/android/key.properties').existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a project whose Gradle does not read key.properties fails with exit code 1',
      () async {
        File(
          '${project.path}/android/app/build.gradle.kts',
        ).writeAsStringSync('android {}');
        final jks = File('${project.path}/k.jks')..writeAsStringSync('x');
        final code = await run([
          '--keystore-path',
          jks.path,
          '--keystore-password',
          'a',
          '--key-alias',
          'b',
          '--key-password',
          'c',
        ]);
        expect(code, 1);
      },
    );

    test('an unsigned dry run still succeeds (with a warning)', () async {
      expect(await run([]), 0);
    });
  });
}

class _Quiet implements Stdout {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void writeln([Object? object = '']) {}
  @override
  void write(Object? object) {}
}
