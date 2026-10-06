import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/studio_command.dart';

/// Runs `game_agent studio ...` and returns its exit code. Output is discarded:
/// the tests check exit codes and the files written, which CI relies on.
Future<int> runStudio(List<String> args) async {
  final runner = CommandRunner<int>('game_agent', 'test')
    ..addCommand(StudioCommand());
  return await IOOverrides.runZoned(
    () async => (await runner.run(['studio', ...args])) ?? 0,
    stdout: () => _NullStdout(),
  );
}

class _NullStdout implements Stdout {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void writeln([Object? object = '']) {}
  @override
  void write(Object? object) {}
}
