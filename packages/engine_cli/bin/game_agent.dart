import 'package:args/command_runner.dart';
import 'package:engine_cli/src/create_command.dart';
import 'package:engine_cli/src/upgrade_command.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'game_agent',
    'CLI for the agentic-game-engine: scaffold and update Flutter games.',
  )
    ..addCommand(CreateCommand())
    ..addCommand(UpgradeCommand());

  final code = await runner.run(arguments);
  if (code != null && code != 0) {
    // ignore: avoid_print
    print('Exited with code $code');
  }
}
