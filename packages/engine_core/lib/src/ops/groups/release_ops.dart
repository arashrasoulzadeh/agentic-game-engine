import '../operation.dart';
import '../param.dart';
import '../release_plan.dart';
import '../result.dart';

/// `release.*`: planning a store build. The build itself needs the Flutter SDK and is `release.build`, a
/// `requiresFlutter` operation implemented by the CLI.
List<Operation> releaseOperations() => [
  Operation(
    name: 'release.plan',
    summary:
        'Plan an Android or iOS release build (command, files, problems) without running it.',
    description:
        'The same planning `game_agent build-release` does: the exact `flutter build` command line, the files it would '
        'create (their paths only; contents can hold secrets and are never returned), errors such as a missing '
        'signing setup and warnings. Pass the android or ios fields that apply.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param(
        'platform',
        ParamType.enumeration,
        options: ['android', 'ios'],
        required: true,
        positional: true,
      ),
      Param('target', ParamType.string, defaultValue: 'lib/main.dart'),
      Param('buildName', ParamType.string, defaultValue: '1.0.0'),
      Param('buildNumber', ParamType.string, defaultValue: '1'),
      Param('flavor', ParamType.string),
      Param('keystorePath', ParamType.string),
      Param('keystorePassword', ParamType.string, secret: true),
      Param('keyAlias', ParamType.string),
      Param('keyPassword', ParamType.string, secret: true),
      Param(
        'gradleText',
        ParamType.string,
        description:
            'Contents of android/app/build.gradle(.kts); checked for key.properties.',
      ),
      Param('teamId', ParamType.string),
      Param('exportOptionsPlist', ParamType.string),
      Param('noCodesign', ParamType.boolean, defaultValue: false),
    ],
    handler: (ctx, a) {
      final android = a['platform'] == 'android';
      final plan = android
          ? planAndroid(
              target: a['target']! as String,
              buildName: a['buildName']! as String,
              buildNumber: a['buildNumber']! as String,
              flavor: a['flavor'] as String?,
              keystorePath: a['keystorePath'] as String?,
              keystorePassword: a['keystorePassword'] as String?,
              keyAlias: a['keyAlias'] as String?,
              keyPassword: a['keyPassword'] as String?,
              gradleText: a['gradleText'] as String?,
            )
          : planIos(
              target: a['target']! as String,
              buildName: a['buildName']! as String,
              buildNumber: a['buildNumber']! as String,
              flavor: a['flavor'] as String?,
              teamId: a['teamId'] as String?,
              exportOptionsPlist: a['exportOptionsPlist'] as String?,
              noCodesign: a['noCodesign'] == true,
            );
      return OpOutcome.data({
        'ok': plan.ok,
        'command': plan.command,
        'writes': [
          for (final path in plan.writes.keys)
            {'path': path, 'contents': 'withheld (may hold secrets)'},
        ],
        'errors': plan.errors,
        'warnings': plan.warnings,
      });
    },
    examples: const [
      Example(
        'Android without signing',
        {'platform': 'android'},
        expect: {'ok': true},
      ),
    ],
  ),
  Operation(
    name: 'release.build',
    summary:
        'Build a signed Android AAB and/or iOS IPA (needs the Flutter SDK; available from the CLI).',
    description:
        'Runs `flutter build`. Implemented by `game_agent build-release` because it needs the Flutter SDK and runs for '
        'minutes; servers without Flutter list it under `engine.capabilities.unsupported`.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    requiresFlutter: true,
    handler: (ctx, a) => throw OpError(
      ErrorCode.unsupported,
      'release.build needs the Flutter SDK; run game_agent build-release.',
    ),
  ),
];
