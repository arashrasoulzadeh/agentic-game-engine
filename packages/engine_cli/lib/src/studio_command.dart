import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:path/path.dart' as p;

/// `game_agent studio ...`: headless tools for the level editor's data, so CI
/// and agents can check the same levels a designer edits in the studio.
class StudioCommand extends Command<int> {
  @override
  final name = 'studio';
  @override
  final description = 'Tools for the level editor: validate and inspect level data.';

  StudioCommand() {
    addSubcommand(StudioValidateCommand());
  }
}

/// `game_agent studio validate [project]`: checks every level JSON under the
/// project's `assets/levels` folder, and exits non-zero if any level has an
/// error. Warnings (such as an exit the player cannot reach) are printed but
/// do not fail the run unless `--strict` is given.
class StudioValidateCommand extends Command<int> {
  @override
  final name = 'validate';
  @override
  final description = 'Validate the levels in a game project against the engine component schemas.';

  StudioValidateCommand() {
    argParser.addFlag(
      'strict',
      negatable: false,
      help: 'Treat warnings as failures too.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final projectDir = rest.isEmpty ? '.' : rest.first;
    final levelsDir = Directory(p.join(projectDir, 'assets', 'levels'));
    if (!levelsDir.existsSync()) {
      stderr.writeln('Error: no assets/levels folder under $projectDir.');
      return 1;
    }

    final files = levelsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      stdout.writeln('No level files found under ${levelsDir.path}.');
      return 0;
    }

    final validator = LevelValidator.forSchemas(allComponentSchemas);
    var errors = 0;
    var warnings = 0;
    for (final file in files) {
      final relative = p.relative(file.path, from: projectDir);
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException catch (e) {
        stdout.writeln('$relative: error: not valid JSON (${e.message})');
        errors++;
        continue;
      }

      final LevelDocument document;
      try {
        document = LevelDocument.fromJson(json);
      } on LevelLoadException catch (e) {
        stdout.writeln('$relative: error: ${e.message}');
        errors++;
        continue;
      }

      final issues = validator.validate(document);
      if (issues.isEmpty) {
        stdout.writeln('$relative: OK (${document.entities.length} entities)');
        continue;
      }
      stdout.writeln('$relative:');
      for (final issue in issues) {
        final label = issue.severity == IssueSeverity.error ? 'error' : 'warning';
        stdout.writeln('  $label: $issue');
        if (issue.severity == IssueSeverity.error) {
          errors++;
        } else {
          warnings++;
        }
      }
    }

    stdout.writeln('${files.length} level(s): $errors error(s), $warnings warning(s).');
    final strict = argResults!['strict'] as bool;
    return errors > 0 || (strict && warnings > 0) ? 1 : 0;
  }
}
