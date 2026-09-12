import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/create_command.dart';
import 'package:engine_cli/src/lint_command.dart';
import 'package:engine_cli/src/upgrade_command.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'game_agent',
    'CLI for the agentic-game-engine: scaffold and update Flutter games.',
  )
    ..addCommand(CreateCommand())
    ..addCommand(UpgradeCommand())
    ..addCommand(LintCommand());

  // CommandRunner.run resolves the exit code but never applies it to the
  // process on its own — without this, every command "succeeds" from a
  // shell/CI script's point of view regardless of what it returned. This
  // was invisible for create/upgrade (their failures already throw and
  // crash the process) but would have silently broken `lint`, whose
  // entire purpose is a scriptable pass/fail exit code.
  final code = await runner.run(arguments);
  exit(code ?? 0);
}
