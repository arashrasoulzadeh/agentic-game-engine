import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/build_release_command.dart';
import 'package:engine_cli/src/release_plan.dart';
import 'package:test/test.dart';

const _gradleReadingKeys =
    'val keystoreProperties = Properties(); rootProject.file("key.properties")';

ReleasePlan _android({
  String? keystore = '/k/release.jks',
  String? storePw = 'sp',
  String? alias = 'upload',
  String? keyPw = 'kp',
  String? gradle = _gradleReadingKeys,
  bool exists = true,
}) => planAndroid(
  target: 'lib/main.dart',
  buildName: '1.2.3',
  buildNumber: '45',
  keystorePath: keystore,
  keystorePassword: storePw,
  keyAlias: alias,
  keyPassword: keyPw,
  gradleText: gradle,
  keystoreExists: exists,
);

void main() {
  group('Android', () {
    test(
      'uses only flags `flutter build appbundle` actually has - never --keystore',
      () {
        final plan = _android();
        expect(plan.ok, isTrue);
        expect(plan.command, [
          'flutter',
          'build',
          'appbundle',
          '--target=lib/main.dart',
          '--build-name=1.2.3',
          '--build-number=45',
          '--release',
        ]);
        expect(
          plan.command.any((a) => a.contains('keystore') || a.contains('key-')),
          isFalse,
        );
      },
    );

    test(
      'signing goes through android/key.properties, with the four values',
      () {
        final plan = _android();
        expect(plan.writes.keys, ['android/key.properties']);
        final props = plan.writes['android/key.properties']!;
        expect(props, contains('storeFile=/k/release.jks'));
        expect(props, contains('keyAlias=upload'));
        expect(props, contains('storePassword=sp'));
        expect(props, contains('keyPassword=kp'));
      },
    );

    test(
      'a project whose Gradle ignores key.properties is refused with the fix, not silently built',
      () {
        final plan = _android(gradle: 'android { }');
        expect(plan.ok, isFalse);
        expect(plan.errors.single, contains('key.properties'));
        expect(plan.errors.single, contains('signingConfigs'));
        expect(_android(gradle: null).ok, isFalse);
      },
    );

    test(
      'incomplete or missing keystore details are errors; none at all warns about the debug key',
      () {
        expect(_android(keyPw: null).errors.single, contains('all of'));
        expect(_android(exists: false).errors.single, contains('not found'));

        final none = _android(
          keystore: null,
          storePw: null,
          alias: null,
          keyPw: null,
        );
        expect(none.ok, isTrue);
        expect(none.writes, isEmpty);
        expect(none.warnings.single, contains('DEBUG key'));
      },
    );

    test('flavor, split-per-abi and verbose are passed through', () {
      final plan = planAndroid(
        target: 't.dart',
        buildName: '1',
        buildNumber: '1',
        flavor: 'prod',
        splitPerAbi: true,
        verbose: true,
      );
      expect(
        plan.command,
        containsAll(['--flavor=prod', '--split-per-abi', '-v']),
      );
    });
  });

  group('iOS', () {
    ReleasePlan ios({
      String? team,
      String? profile,
      String? identity,
      String? plist,
      bool noCodesign = false,
    }) => planIos(
      target: 'lib/main.dart',
      buildName: '1.0.0',
      buildNumber: '1',
      teamId: team,
      provisioningProfile: profile,
      codesignIdentity: identity,
      exportOptionsPlist: plist,
      noCodesign: noCodesign,
    );

    test('never passes flags `flutter build ipa` lacks', () {
      for (final plan in [
        ios(team: 'ABCDE12345'),
        ios(plist: 'x.plist'),
        ios(noCodesign: true),
        ios(),
      ]) {
        expect(
          plan.command.any(
            (a) =>
                a.startsWith('--team-id') ||
                a.contains('provisioning') ||
                a.contains('codesign-identity'),
          ),
          isFalse,
        );
      }
    });

    test(
      '--team-id generates an automatic-signing ExportOptions.plist and uses it',
      () {
        final plan = ios(team: 'ABCDE12345');
        expect(
          plan.command,
          contains('--export-options-plist=ios/ExportOptions.generated.plist'),
        );
        final plist = plan.writes['ios/ExportOptions.generated.plist']!;
        expect(plist, contains('<string>ABCDE12345</string>'));
        expect(plist, contains('automatic'));
      },
    );

    test(
      'an explicit plist wins, and ignored signing flags are called out',
      () {
        final plan = ios(plist: 'my.plist', team: 'T');
        expect(plan.command, contains('--export-options-plist=my.plist'));
        expect(plan.writes, isEmpty);
        expect(plan.warnings.single, contains('ignored'));
      },
    );

    test(
      'a profile or identity without a plist is an error, not silently dropped',
      () {
        expect(ios(profile: 'p.mobileprovision').ok, isFalse);
        expect(ios(identity: 'Apple Distribution: X').ok, isFalse);
      },
    );

    test('--no-codesign builds an unsigned test IPA', () {
      expect(ios(noCodesign: true).command, contains('--no-codesign'));
    });

    test('nothing given warns that signing is whatever Xcode has', () {
      final plan = ios();
      expect(plan.ok, isTrue);
      expect(plan.warnings.single, contains('Xcode'));
    });
  });

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
