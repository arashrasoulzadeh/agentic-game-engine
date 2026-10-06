import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// `game_agent studio ...`: headless tools for the level editor's data, so CI
/// and agents can check the same levels a designer edits in the studio.
class StudioCommand extends Command<int> {
  @override
  final name = 'studio';
  @override
  final description =
      'Tools for the level editor: validate and inspect level data.';

  StudioCommand() {
    addSubcommand(StudioValidateCommand());
    addSubcommand(StudioImportTmxCommand());
    addSubcommand(StudioExportLevelsCommand());
    addSubcommand(StudioProjectManifestCommand());
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
  final description =
      'Validate the levels in a game project against the engine component schemas.';

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

    final files = _levelFiles(projectDir);
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
        final label = issue.severity == IssueSeverity.error
            ? 'error'
            : 'warning';
        stdout.writeln('  $label: $issue');
        if (issue.severity == IssueSeverity.error) {
          errors++;
        } else {
          warnings++;
        }
      }
    }

    stdout.writeln(
      '${files.length} level(s): $errors error(s), $warnings warning(s).',
    );
    final strict = argResults!['strict'] as bool;
    return errors > 0 || (strict && warnings > 0) ? 1 : 0;
  }
}

/// `game_agent studio import-tmx <map.tmx> [--project dir] [--out file]`:
/// converts a Tiled map (embedded tileset, CSV layer) into a level file under
/// the project's `assets/levels`, so a level built in Tiled is editable in the
/// studio and loadable by the engine. The result is validated before it is
/// written, so an import that the engine would reject never reaches disk.
class StudioImportTmxCommand extends Command<int> {
  @override
  final name = 'import-tmx';
  @override
  final description =
      'Convert a Tiled .tmx map into a level file in a game project.';

  StudioImportTmxCommand() {
    argParser
      ..addOption(
        'project',
        defaultsTo: '.',
        help: 'The game project to write into.',
      )
      ..addOption(
        'out',
        help:
            'Level file to write. Defaults to assets/levels/<map name>.level.json.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException(
        'Missing the .tmx file, e.g. `game_agent studio import-tmx level1.tmx`',
      );
    }
    final source = File(rest.first);
    if (!source.existsSync()) {
      stderr.writeln('Error: ${source.path} does not exist.');
      return 1;
    }

    final TileMap map;
    try {
      map = tileMapFromTmx(source.readAsStringSync());
    } on UnsupportedError catch (e) {
      stderr.writeln('${source.path}: ${e.message}');
      return 1;
    } on Object catch (e) {
      stderr.writeln('${source.path}: not a readable Tiled map ($e)');
      return 1;
    }

    final document = LevelDocument(
      entities: [
        LevelEntity(
          name: 'map',
          components: {
            'position': {'x': 0.0, 'y': 0.0},
            'tileMap': map.toJson(),
          },
        ),
      ],
    );

    final issues = LevelValidator.forSchemas(
      allComponentSchemas,
    ).validate(document);
    final errors = issues
        .where((i) => i.severity == IssueSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      stderr.writeln('${source.path}: the imported map is not a valid level:');
      for (final issue in errors) {
        stderr.writeln('  $issue');
      }
      return 1;
    }

    final projectDir = argResults!['project'] as String;
    final defaultName = p.basenameWithoutExtension(source.path);
    final outPath =
        (argResults!['out'] as String?) ??
        p.join(projectDir, 'assets', 'levels', '$defaultName.level.json');
    final out = File(outPath)..createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
    );
    stdout.writeln('Wrote ${out.path} (${map.cols}x${map.rows} tiles).');
    return 0;
  }
}

/// The engine-owned level files under a project's `assets/levels` folder, sorted
/// so every command reads them in the same order.
List<File> _levelFiles(String projectDir) {
  final dir = Directory(p.join(projectDir, 'assets', 'levels'));
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Canonical JSON for engine data: two-space indent, one key per line, keys in
/// the order they were written. Every studio save uses this, so a level always
/// looks the same whichever tool last wrote it.
String canonicalJson(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);

/// `game_agent studio export-levels [project] [--out dir]`: re-writes every level
/// in canonical form. Each level is validated first, and a level with errors is
/// reported and left alone, so this never writes a file the engine would reject.
/// Data is unchanged; only the formatting is normalized. Without --out, levels
/// are rewritten in place.
class StudioExportLevelsCommand extends Command<int> {
  @override
  final name = 'export-levels';
  @override
  final description =
      'Re-write the level files in a project in canonical form (validated first).';

  StudioExportLevelsCommand() {
    argParser.addOption(
      'out',
      help:
          'Directory to write the canonical levels to. Defaults to rewriting them in place.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final projectDir = rest.isEmpty ? '.' : rest.first;
    final files = _levelFiles(projectDir);
    if (files.isEmpty) {
      stderr.writeln(
        'Error: no level files found under $projectDir/assets/levels.',
      );
      return 1;
    }

    final validator = LevelValidator.forSchemas(allComponentSchemas);
    final outDir = argResults!['out'] as String?;
    var failed = 0;
    for (final file in files) {
      final relative = p.relative(file.path, from: projectDir);
      final LevelDocument document;
      try {
        document = LevelDocument.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
      } on Object catch (e) {
        stderr.writeln('$relative: not a loadable level ($e); left unchanged.');
        failed++;
        continue;
      }
      final errors = validator
          .validate(document)
          .where((i) => i.severity == IssueSeverity.error)
          .toList();
      if (errors.isNotEmpty) {
        stderr.writeln(
          '$relative: has ${errors.length} error(s); left unchanged.',
        );
        failed++;
        continue;
      }

      final target =
          outDir == null
                ? file
                : File(
                    p.join(
                      outDir,
                      p.relative(
                        file.path,
                        from: p.join(projectDir, 'assets', 'levels'),
                      ),
                    ),
                  )
            ..createSync(recursive: true);
      target.writeAsStringSync(canonicalJson(document.toJson()));
      stdout.writeln('$relative: written in canonical form.');
    }
    return failed == 0 ? 0 : 1;
  }
}

/// `game_agent studio project-manifest [project]`: writes `project.json`, which
/// records the project's name, the engine version it targets, and its levels.
/// The name and engine version come from `pubspec.yaml`. Keys the manifest does
/// not own are kept, so a human can add notes without losing them on the next
/// run.
class StudioProjectManifestCommand extends Command<int> {
  @override
  final name = 'project-manifest';
  @override
  final description =
      'Write or update project.json (name, engine version, levels).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final projectDir = rest.isEmpty ? '.' : rest.first;
    final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      stderr.writeln(
        'Error: no pubspec.yaml in $projectDir, so this is not a game project.',
      );
      return 1;
    }
    final spec = loadYaml(pubspec.readAsStringSync()) as YamlMap;

    final manifestFile = File(p.join(projectDir, 'project.json'));
    final existing = manifestFile.existsSync()
        ? jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};

    final levels = [
      for (final file in _levelFiles(projectDir))
        p.relative(file.path, from: projectDir).replaceAll(p.separator, '/'),
    ];

    final manifest = {
      ...existing,
      'name': spec['name'] as String? ?? 'unnamed',
      'engineVersion': _engineRef(spec),
      'levels': levels,
    };
    manifestFile.writeAsStringSync('${canonicalJson(manifest)}\n');
    stdout.writeln('Wrote ${manifestFile.path} (${levels.length} level(s)).');
    return 0;
  }

  /// The engine ref the project's `engine_core` dependency pins, e.g. `main` or
  /// `v0.1.0`. "unknown" when the project does not depend on it by git ref.
  String _engineRef(YamlMap spec) {
    final deps = spec['dependencies'];
    if (deps is! YamlMap) return 'unknown';
    final core = deps['engine_core'];
    if (core is YamlMap && core['git'] is YamlMap) {
      return (core['git'] as YamlMap)['ref'] as String? ?? 'unknown';
    }
    return 'unknown';
  }
}
