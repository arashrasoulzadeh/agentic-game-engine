import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

import 'studio_command.dart' show canonicalJson;
import 'studio_edit_commands.dart';

/// `game_agent studio export-tmx|save-prefab|place-prefab`: the asset-pipeline half
/// of the studio, headless - the same operations the GUI performs, for scripts and
/// agents.
void addStudioAssetCommands(Command<int> studio) {
  studio
    ..addSubcommand(StudioExportTmxCommand())
    ..addSubcommand(StudioSavePrefabCommand())
    ..addSubcommand(StudioPlacePrefabCommand());
}

/// `game_agent studio export-tmx <level> [--entity name] [--out file.tmx] [--image tiles.png]`:
/// writes the level's tile map as a Tiled map, so it can be opened and edited in Tiled
/// and brought back with `import-tmx`. Only tiles and the four collision sets survive
/// (see `tileMapToTmx`); the command says so when the level uses more.
class StudioExportTmxCommand extends Command<int> {
  @override
  final name = 'export-tmx';
  @override
  final description = "Export a level's tile map as a Tiled .tmx file.";

  StudioExportTmxCommand() {
    argParser
      ..addOption(
        'entity',
        help:
            'The entity holding the tileMap. Default: the first one that has one.',
      )
      ..addOption(
        'out',
        help: 'File to write. Default: <level name>.tmx next to the level.',
      )
      ..addOption(
        'image',
        defaultsTo: 'tiles.png',
        help: 'Tileset image path to record in the .tmx.',
      )
      ..addOption('tileset', defaultsTo: 'tiles', help: 'Tileset name.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 64;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final wanted = argResults!['entity'] as String?;
    LevelEntity? holder;
    for (final e in document.entities) {
      if (e.components.containsKey('tileMap') &&
          (wanted == null || e.name == wanted)) {
        holder = e;
        break;
      }
    }
    if (holder == null) {
      stderr.writeln(
        wanted == null
            ? 'Error: $path has no entity with a tileMap.'
            : 'Error: no entity named "$wanted" with a tileMap in $path.',
      );
      return 1;
    }

    final TileMap map;
    try {
      map = TileMap.fromJson(holder.components['tileMap']!);
    } on Object catch (e) {
      stderr.writeln('Error: the tileMap in $path is not loadable ($e).');
      return 1;
    }

    final lossy = <String>[
      if (map.ladderTileIds.isNotEmpty) 'ladders',
      if (map.conveyorSpeedByTileId.isNotEmpty) 'conveyors',
      if (map.frictionByTileId.isNotEmpty) 'friction',
      if (map.backgroundTiles != null || map.foregroundTiles != null)
        'extra layers',
      if (map.tileAnimations.isNotEmpty) 'tile animations',
      if (map.atlasId != null) 'atlas/art binding',
    ];
    final out =
        argResults!['out'] as String? ??
        p.setExtension(path, '.tmx').replaceAll('.level.tmx', '.tmx');
    File(out)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        tileMapToTmx(
          map,
          tilesetName: argResults!['tileset'] as String,
          imageSource: argResults!['image'] as String,
        ),
      );
    stdout.writeln('Wrote $out (${map.cols}x${map.rows} tiles).');
    if (lossy.isNotEmpty) {
      stdout.writeln(
        'Note: Tiled has no place for ${lossy.join(', ')}; they are not in the .tmx.',
      );
    }
    return 0;
  }
}

/// `game_agent studio save-prefab <level> --name torch --entities a,b [--project dir]`:
/// captures the named entities as `prefabs/<name>.json`, positions relative to the
/// group's top-left corner.
class StudioSavePrefabCommand extends Command<int> {
  @override
  final name = 'save-prefab';
  @override
  final description =
      'Save entities of a level as a reusable prefab in prefabs/.';

  StudioSavePrefabCommand() {
    argParser
      ..addOption(
        'name',
        mandatory: true,
        help: 'The prefab name (also its file name).',
      )
      ..addOption(
        'entities',
        mandatory: true,
        help: 'Comma-separated entity names to capture.',
      )
      ..addOption(
        'project',
        defaultsTo: '.',
        help: 'The game project to write into.',
      );
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 64;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final name = argResults!['name'] as String;
    if (!RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(name)) {
      stderr.writeln(
        'Error: a prefab name may only use letters, digits, "_" and "-".',
      );
      return 1;
    }
    final members = <LevelEntity>[];
    for (final wanted
        in (argResults!['entities'] as String)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)) {
      final entity = entityNamedOrNull(document, wanted);
      if (entity == null) return 1;
      members.add(entity);
    }
    if (members.isEmpty) {
      stderr.writeln('Error: --entities names no entities.');
      return 1;
    }
    final out =
        File(p.join(argResults!['project'] as String, 'prefabs', '$name.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            canonicalJson(Prefab.fromEntities(name, members).toJson()),
          );
    stdout.writeln('Wrote ${out.path} (${members.length} entities).');
    return 0;
  }
}

/// `game_agent studio place-prefab <level> --prefab torch --x 64 --y 32 [--project dir]`:
/// places a saved prefab into the level with its top-left at (x, y). Names are made
/// unique; the result is validated before it is written.
class StudioPlacePrefabCommand extends Command<int> {
  @override
  final name = 'place-prefab';
  @override
  final description = 'Place a saved prefab into a level at a position.';

  StudioPlacePrefabCommand() {
    argParser
      ..addOption(
        'prefab',
        mandatory: true,
        help: 'The prefab name, from prefabs/<name>.json.',
      )
      ..addOption(
        'x',
        mandatory: true,
        help: 'World x of the prefab\'s top-left corner.',
      )
      ..addOption(
        'y',
        mandatory: true,
        help: 'World y of the prefab\'s top-left corner.',
      )
      ..addOption(
        'project',
        defaultsTo: '.',
        help: 'The game project the prefab lives in.',
      );
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 64;
    final x = parseDoubleOption('x', argResults!['x'] as String?);
    final y = parseDoubleOption('y', argResults!['y'] as String?);
    if (x == null || y == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final prefabFile = File(
      p.join(
        argResults!['project'] as String,
        'prefabs',
        '${argResults!['prefab']}.json',
      ),
    );
    if (!prefabFile.existsSync()) {
      stderr.writeln('Error: ${prefabFile.path} does not exist.');
      return 1;
    }
    final Prefab prefab;
    try {
      prefab = Prefab.fromJson(
        jsonDecode(prefabFile.readAsStringSync()) as Map<String, dynamic>,
      );
    } on Object catch (e) {
      stderr.writeln(
        'Error: ${prefabFile.path} is not a loadable prefab ($e).',
      );
      return 1;
    }
    final command = InstantiatePrefabCommand(prefab, x: x, y: y);
    command.apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln(
      'Placed ${command.placed.length} entities from "${prefab.name}" at ($x, $y).',
    );
    return 0;
  }
}
