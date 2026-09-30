import 'dart:io';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Builds a signed release Android App Bundle (AAB) and/or iOS IPA.
/// Supports both local signing (keystore/provisioning profile) and
/// CI-friendly environment variable-based signing.
class BuildReleaseCommand extends Command<int> {
  @override
  final name = 'build-release';
  @override
  final description =
      'Build a signed release Android AAB and/or iOS IPA. '
      'Runs flutter build with appropriate signing config.';

  BuildReleaseCommand() {
    argParser
      ..addFlag(
        'android',
        abbr: 'a',
        help: 'Build Android AAB (default: true).',
        defaultsTo: true,
      )
      ..addFlag(
        'ios',
        abbr: 'i',
        help: 'Build iOS IPA (default: false, macOS only).',
        defaultsTo: false,
      )
      ..addOption(
        'project-dir',
        abbr: 'd',
        help: 'Path to Flutter project directory (default: current directory).',
        defaultsTo: '.',
      )
      ..addOption(
        'flavor',
        abbr: 'f',
        help: 'Build flavor (e.g., "prod", "staging").',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'Target Dart file (default: lib/main.dart).',
        defaultsTo: 'lib/main.dart',
      )
      ..addOption(
        'build-name',
        help: 'Build name (version name, e.g., "1.0.0"). Reads from pubspec.yaml if not provided.',
      )
      ..addOption(
        'build-number',
        help: 'Build number (version code, e.g., "1"). Reads from pubspec.yaml if not provided.',
      )
      // Android signing options
      ..addOption(
        'keystore-path',
        help: 'Path to Android keystore file (.jks/.keystore).',
      )
      ..addOption(
        'keystore-password',
        help: 'Keystore password.',
      )
      ..addOption(
        'key-alias',
        help: 'Key alias in keystore.',
      )
      ..addOption(
        'key-password',
        help: 'Key password.',
      )
      // iOS signing options
      ..addOption(
        'team-id',
        help: 'Apple Team ID for iOS signing.',
      )
      ..addOption(
        'provisioning-profile',
        help: 'Path to provisioning profile (.mobileprovision).',
      )
      ..addOption(
        'codesign-identity',
        help: 'Code signing identity (e.g., "Apple Distribution: Company Name").',
      )
      ..addOption(
        'export-options-plist',
        help: 'Path to ExportOptions.plist for iOS export.',
      )
      ..addFlag(
        'no-codesign',
        help: 'Skip iOS code signing (unsigned build for testing).',
        defaultsTo: false,
      )
      ..addFlag(
        'split-per-abi',
        help: 'Split Android AAB per ABI (smaller downloads, larger total size).',
        defaultsTo: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Verbose output.',
        defaultsTo: false,
      )
      ..addFlag(
        'dry-run',
        help: 'Print commands without executing.',
        defaultsTo: false,
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final projectDir = Directory(args['project-dir'] as String);
    final buildAndroid = args['android'] as bool;
    final buildIOS = args['ios'] as bool;
    final flavor = args['flavor'] as String?;
    final target = args['target'] as String;
    final buildName = args['build-name'] as String?;
    final buildNumber = args['build-number'] as String?;
    final verbose = args['verbose'] as bool;
    final dryRun = args['dry-run'] as bool;

    if (!projectDir.existsSync()) {
      stderr.writeln('Error: Project directory ${projectDir.path} does not exist.');
      return 1;
    }

    // Read pubspec.yaml for version info
    final pubspecFile = File(p.join(projectDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      stderr.writeln('Error: pubspec.yaml not found in ${projectDir.path}');
      return 1;
    }
    final pubspecContent = pubspecFile.readAsStringSync();
    final pubspec = loadYaml(pubspecContent) as Map<dynamic, dynamic>;
    final pubspecVersion = pubspec['version'] as String? ?? '1.0.0+1';
    final versionParts = pubspecVersion.split('+');
    final pubspecBuildName = versionParts.isNotEmpty ? versionParts[0] : '1.0.0';
    final pubspecBuildNumber = versionParts.length > 1 ? versionParts[1] : '1';

    final resolvedBuildName = buildName ?? pubspecBuildName;
    final resolvedBuildNumber = buildNumber ?? pubspecBuildNumber;

    if (buildAndroid) {
      final result = await _buildAndroid(
        projectDir: projectDir,
        flavor: flavor,
        target: target,
        buildName: resolvedBuildName,
        buildNumber: resolvedBuildNumber,
        keystorePath: args['keystore-path'] as String?,
        keystorePassword: args['keystore-password'] as String?,
        keyAlias: args['key-alias'] as String?,
        keyPassword: args['key-password'] as String?,
        splitPerAbi: args['split-per-abi'] as bool,
        verbose: verbose,
        dryRun: dryRun,
      );
      if (result != 0) return result;
    }

    if (buildIOS) {
      if (!Platform.isMacOS) {
        stderr.writeln('Error: iOS builds require macOS.');
        return 1;
      }
      final result = await _buildIOS(
        projectDir: projectDir,
        flavor: flavor,
        target: target,
        buildName: resolvedBuildName,
        buildNumber: resolvedBuildNumber,
        teamId: args['team-id'] as String?,
        provisioningProfile: args['provisioning-profile'] as String?,
        codesignIdentity: args['codesign-identity'] as String?,
        exportOptionsPlist: args['export-options-plist'] as String?,
        noCodesign: args['no-codesign'] as bool,
        verbose: verbose,
        dryRun: dryRun,
      );
      if (result != 0) return result;
    }

    return 0;
  }

  Future<int> _buildAndroid({
    required Directory projectDir,
    String? flavor,
    required String target,
    required String buildName,
    required String buildNumber,
    String? keystorePath,
    String? keystorePassword,
    String? keyAlias,
    String? keyPassword,
    required bool splitPerAbi,
    required bool verbose,
    required bool dryRun,
  }) async {
    final args = <String>[
      'flutter',
      'build',
      'appbundle',
      '--target=$target',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--release',
    ];

    if (flavor != null) {
      args.add('--flavor=$flavor');
    }

    // Android signing
    final useSigning = keystorePath != null &&
        keystorePassword != null &&
        keyAlias != null &&
        keyPassword != null;

    if (useSigning) {
      final keystoreFile = File(keystorePath!);
      if (!keystoreFile.existsSync()) {
        stderr.writeln('Error: Keystore file not found at $keystorePath');
        return 1;
      }
      args.add('--keystore=$keystorePath');
      args.add('--keystore-password=$keystorePassword');
      args.add('--key-alias=$keyAlias');
      args.add('--key-password=$keyPassword');
    } else if (!dryRun) {
      stdout.writeln('Warning: Android keystore not provided, building unsigned AAB.');
    }

    if (splitPerAbi) {
      args.add('--split-per-abi');
    }

    if (verbose) {
      args.add('-v');
    }

    return _runCommand(projectDir.path, args, dryRun);
  }

  Future<int> _buildIOS({
    required Directory projectDir,
    String? flavor,
    required String target,
    required String buildName,
    required String buildNumber,
    String? teamId,
    String? provisioningProfile,
    String? codesignIdentity,
    String? exportOptionsPlist,
    required bool noCodesign,
    required bool verbose,
    required bool dryRun,
  }) async {
    final args = <String>[
      'flutter',
      'build',
      'ipa',
      '--target=$target',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--release',
    ];

    if (flavor != null) {
      args.add('--flavor=$flavor');
    }

    if (noCodesign) {
      args.add('--no-codesign');
    } else {
      if (teamId != null) args.add('--team-id=$teamId');
      if (provisioningProfile != null) {
        final profileFile = File(provisioningProfile!);
        if (!profileFile.existsSync()) {
          stderr.writeln('Error: Provisioning profile not found at $provisioningProfile');
          return 1;
        }
        args.add('--provisioning-profile=$provisioningProfile');
      }
      if (codesignIdentity != null) args.add('--codesign-identity=$codesignIdentity');
      if (exportOptionsPlist != null) {
        final plistFile = File(exportOptionsPlist!);
        if (!plistFile.existsSync()) {
          stderr.writeln('Error: ExportOptions.plist not found at $exportOptionsPlist');
          return 1;
        }
        args.add('--export-options-plist=$exportOptionsPlist');
      }
    }

    if (verbose) {
      args.add('-v');
    }

    return _runCommand(projectDir.path, args, dryRun);
  }

  Future<int> _runCommand(String workingDir, List<String> args, bool dryRun) async {
    final cmd = args.join(' ');
    stdout.writeln('Running: $cmd');
    if (dryRun) {
      stdout.writeln('[dry-run] Would execute in $workingDir');
      return 0;
    }

    final process = await Process.start(
      args.first,
      args.sublist(1),
      workingDirectory: workingDir,
      runInShell: true,
    );

    final stdoutStream = process.stdout
        .transform(utf8.decoder)
        .listen((line) => stdout.writeln(line));
    final stderrStream = process.stderr
        .transform(utf8.decoder)
        .listen((line) => stderr.writeln(line));

    final exitCode = await process.exitCode;
    await stdoutStream.cancel();
    await stderrStream.cancel();

    if (exitCode != 0) {
      stderr.writeln('Command failed with exit code $exitCode');
    } else {
      stdout.writeln('Command completed successfully.');
    }
    return exitCode;
  }

static int _getExitCode(int? code) => code ?? 1;
}