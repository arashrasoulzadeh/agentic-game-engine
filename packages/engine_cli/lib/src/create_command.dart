import 'dart:io';

import 'package:args/command_runner.dart';

import 'process_utils.dart';
import 'template.dart';

const defaultEngineRepoUrl =
    'https://github.com/arashrasoulzadeh/agentic-game-engine.git';

class CreateCommand extends Command<int> {
  @override
  final name = 'create';
  @override
  final description = 'Scaffold a new Flutter game wired to engine_core.';

  final CommandProcessRunner _runProcess;
  final Directory Function(String) _findTemplate;

  /// Inject process execution and template lookup for isolated command tests.
  CreateCommand({
    CommandProcessRunner runProcess = runStreamed,
    Directory Function(String) findTemplate = templateRoot,
  }) : _runProcess = runProcess, _findTemplate = findTemplate {
    argParser
      ..addOption('org',
          defaultsTo: 'com.example',
          help: 'Reverse-domain org for Android/iOS bundle ids.')
      ..addOption('output-dir',
          defaultsTo: '.', help: 'Directory to create the project in.')
      ..addOption('engine-repo',
          defaultsTo: defaultEngineRepoUrl,
          help: 'Git URL of the engine repo to depend on.')
      ..addOption('ref',
          defaultsTo: 'v0.1.0',
          help: 'Git ref (branch or tag) of engine_core to pin to.');
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      usageException('Missing project name, e.g. `game_agent create my_game`');
    }
    final projectName = args.rest.first;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(projectName)) {
      usageException(
        'Project name "$projectName" must be lower_snake_case '
        '(letters, digits, underscores; starting with a letter).',
      );
    }

    final outputDir = args['output-dir'] as String;
    final projectDir = Directory('$outputDir/$projectName');
    if (projectDir.existsSync()) {
      stderr.writeln('Error: ${projectDir.path} already exists.');
      return 1;
    }

    stdout.writeln('Running flutter create...');
    await _runProcess(
      'flutter',
      [
        'create',
        '--platforms=android,ios,web',
        '--org',
        args['org'] as String,
        projectName,
      ],
      workingDirectory: outputDir,
    );

    stdout.writeln('Wiring up engine_core...');
    copyTemplate(
      _findTemplate('default_game'),
      projectDir,
      {
        'PROJECT_NAME': projectName,
        'ENGINE_REPO_URL': args['engine-repo'] as String,
        'ENGINE_REF': args['ref'] as String,
      },
    );

    stdout.writeln('Fetching packages...');
    await _runProcess('flutter', ['pub', 'get'],
        workingDirectory: projectDir.path);

    stdout.writeln('''

Done! Your game is ready at ${projectDir.path}

  cd ${projectDir.path}
  flutter run

Run `game_agent upgrade` inside the project later to pull engine updates.''');
    return 0;
  }
}
