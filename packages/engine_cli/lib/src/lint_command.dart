import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';

class LintCommand extends Command<int> {
  @override
  final name = 'lint';
  @override
  final description = 'Validate a level/content JSON file without running the game.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      usageException('Missing file path, e.g. `game_agent lint assets/level1.json`');
    }

    final file = File(args.rest.first);
    if (!file.existsSync()) {
      stderr.writeln('Error: ${file.path} does not exist.');
      return 1;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      stderr.writeln('Error: ${file.path} is not valid JSON: ${e.message}');
      return 1;
    }

    try {
      final entities = Level.validate(json);
      stdout.writeln('${file.path}: OK (${entities.length} entities)');
      return 0;
    } on LevelLoadException catch (e) {
      stderr.writeln('${file.path}: ${e.message}');
      return 1;
    }
  }
}
