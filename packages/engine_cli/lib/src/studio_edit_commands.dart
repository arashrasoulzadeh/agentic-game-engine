import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';

import 'studio_command.dart' show canonicalJson;

/// `game_agent studio ...`: the mutating half of the studio's command model,
/// exposed headlessly so an agent or a script can do everything the GUI's
/// level editor can — add/remove/move an entity, set a field, set a layer,
/// paint a tile, fill a region — without a UI, using the exact same
/// `EditCommand` classes the studio applies (`engine_core/lib/src/command/`).
/// Every edit is validated before it is written, the same way
/// `import-tmx`/`export-levels` already are, so a command that would make
/// the level invalid never reaches disk; the file is left untouched and the
/// run exits non-zero instead.
void addStudioEditCommands(Command<int> studio) {
  studio
    ..addSubcommand(StudioAddEntityCommand())
    ..addSubcommand(StudioRemoveEntityCommand())
    ..addSubcommand(StudioSetFieldCommand())
    ..addSubcommand(StudioMoveEntityCommand())
    ..addSubcommand(StudioSetLayerCommand())
    ..addSubcommand(StudioPaintTileCommand())
    ..addSubcommand(StudioFillRegionCommand());
}

/// Loads the level at [path] as a [LevelDocument], or prints why it could
/// not and returns null.
LevelDocument? loadLevelOrNull(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Error: $path does not exist.');
    return null;
  }
  try {
    return LevelDocument.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  } on Object catch (e) {
    stderr.writeln('Error: $path is not a loadable level ($e).');
    return null;
  }
}

/// Validates [document]; an error blocks the write (the file at [path] is
/// left exactly as it was) and this returns false. Otherwise [document] is
/// written back to [path] in canonical form and this returns true.
bool validateAndWrite(String path, LevelDocument document) {
  final errors = LevelValidator.forSchemas(allComponentSchemas)
      .validate(document)
      .where((issue) => issue.severity == IssueSeverity.error)
      .toList();
  if (errors.isNotEmpty) {
    stderr.writeln('Error: this would make $path invalid:');
    for (final issue in errors) {
      stderr.writeln('  $issue');
    }
    return false;
  }
  File(path).writeAsStringSync(canonicalJson(document.toJson()));
  return true;
}

/// The entity named [name] in [document], or null after printing why there
/// is none (missing, or more than one other command already reported it).
LevelEntity? entityNamedOrNull(LevelDocument document, String name) {
  final entity = document.entityNamed(name);
  if (entity == null) {
    stderr.writeln('Error: no entity named "$name" in this level.');
  }
  return entity;
}

/// Parses [text] as an int, or prints an error naming [option] and returns
/// null.
int? parseIntOption(String option, String? text) {
  if (text == null) {
    stderr.writeln('Error: --$option is required.');
    return null;
  }
  final value = int.tryParse(text);
  if (value == null) {
    stderr.writeln('Error: --$option must be an integer, got "$text".');
  }
  return value;
}

/// Parses [text] as a double, or prints an error naming [option] and returns
/// null.
double? parseDoubleOption(String option, String? text) {
  if (text == null) {
    stderr.writeln('Error: --$option is required.');
    return null;
  }
  final value = double.tryParse(text);
  if (value == null) {
    stderr.writeln('Error: --$option must be a number, got "$text".');
  }
  return value;
}

/// The JSON value [text] denotes for a component field: parsed as JSON when
/// it is valid JSON (`3`, `3.5`, `true`, `"quoted"`, `[1,2]`, `{"a":1}`), or
/// else kept as the literal string, so `--value hello` doesn't require
/// `--value '"hello"'` for the common case of setting a plain string field.
Object? parseFieldValue(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// The level file argument every edit command takes, or null (with an error
/// already printed) when it is missing.
String? levelPathOrNull(ArgResults results) {
  final rest = results.rest;
  if (rest.isEmpty) {
    stderr.writeln('Error: missing the level file.');
    return null;
  }
  return rest.first;
}

/// `game_agent studio add-entity <level> [--name x] [--component c ...] [--index n]`:
/// adds an entity whose named components start at their schema's `template`
/// values — the same starting values `EntityPalette` gives a component placed
/// in the studio GUI.
class StudioAddEntityCommand extends Command<int> {
  @override
  final name = 'add-entity';
  @override
  final description =
      'Add an entity to a level, with the named components at their schema defaults.';

  StudioAddEntityCommand() {
    argParser
      ..addOption('name', help: "The new entity's name.")
      ..addMultiOption(
        'component',
        help: 'A component to give the entity, at its schema defaults. Repeatable.',
      )
      ..addOption('index', help: 'Position to insert at. Defaults to the end.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final components = <String, Map<String, dynamic>>{};
    for (final componentName in argResults!['component'] as List<String>) {
      final schema = allComponentSchemas[componentName];
      if (schema == null) {
        stderr.writeln('Error: unknown component "$componentName".');
        return 1;
      }
      components[componentName] = Map<String, dynamic>.of(schema.template);
    }

    final indexText = argResults!['index'] as String?;
    int? index;
    if (indexText != null) {
      index = int.tryParse(indexText);
      if (index == null) {
        stderr.writeln('Error: --index must be an integer, got "$indexText".');
        return 1;
      }
    }

    final entity = LevelEntity(
      name: argResults!['name'] as String?,
      components: components,
    );
    AddEntityCommand(entity, index: index).apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln(
      'Added entity${entity.name == null ? '' : ' ${entity.name}'} to $path.',
    );
    return 0;
  }
}

/// `game_agent studio remove-entity <level> --entity name`: removes the named
/// entity.
class StudioRemoveEntityCommand extends Command<int> {
  @override
  final name = 'remove-entity';
  @override
  final description = 'Remove an entity from a level.';

  StudioRemoveEntityCommand() {
    argParser.addOption('entity', help: 'Name of the entity to remove.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;

    RemoveEntityCommand(entity).apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Removed entity $entityName from $path.');
    return 0;
  }
}

/// `game_agent studio set-field <level> --entity name --component c --field f --value v`:
/// sets one field of one component on an entity, creating the component if it
/// is absent (see `SetComponentFieldCommand`).
class StudioSetFieldCommand extends Command<int> {
  @override
  final name = 'set-field';
  @override
  final description =
      "Set one field of one of an entity's components, creating the component if absent.";

  StudioSetFieldCommand() {
    argParser
      ..addOption('entity', help: 'Name of the entity to edit.')
      ..addOption('component', help: 'The component whose field to set.')
      ..addOption('field', help: 'The field to set.')
      ..addOption(
        'value',
        help:
            'The value to set it to, as JSON when possible (3, 3.5, true, '
            '"quoted", [1,2]) or a plain string otherwise.',
      );
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    final component = argResults!['component'] as String?;
    final field = argResults!['field'] as String?;
    final valueText = argResults!['value'] as String?;
    if (entityName == null || component == null || field == null || valueText == null) {
      stderr.writeln(
        'Error: --entity, --component, --field, and --value are all required.',
      );
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;

    SetComponentFieldCommand(
      entity: entity,
      component: component,
      field: field,
      value: parseFieldValue(valueText),
    ).apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Set $entityName.$component.$field in $path.');
    return 0;
  }
}

/// `game_agent studio move-entity <level> --entity name --x X --y Y`: sets an
/// entity's `position` component.
class StudioMoveEntityCommand extends Command<int> {
  @override
  final name = 'move-entity';
  @override
  final description = "Move an entity by setting its position component.";

  StudioMoveEntityCommand() {
    argParser
      ..addOption('entity', help: 'Name of the entity to move.')
      ..addOption('x', help: 'New x position.')
      ..addOption('y', help: 'New y position.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;

    final x = parseDoubleOption('x', argResults!['x'] as String?);
    final y = parseDoubleOption('y', argResults!['y'] as String?);
    if (x == null || y == null) return 1;

    MoveEntityCommand(entity: entity, x: x, y: y).apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Moved $entityName to ($x, $y) in $path.');
    return 0;
  }
}

/// `game_agent studio set-layer <level> --entity name --component c --z-index n`:
/// sets a component's draw-order `zIndex`.
class StudioSetLayerCommand extends Command<int> {
  @override
  final name = 'set-layer';
  @override
  final description = "Set a component's draw-order zIndex on an entity.";

  StudioSetLayerCommand() {
    argParser
      ..addOption('entity', help: 'Name of the entity to edit.')
      ..addOption(
        'component',
        help: 'The component whose zIndex to set (e.g. sprite, tileMap).',
      )
      ..addOption('z-index', help: 'The new zIndex.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    final component = argResults!['component'] as String?;
    if (entityName == null || component == null) {
      stderr.writeln('Error: --entity and --component are required.');
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;
    if (!entity.components.containsKey(component)) {
      stderr.writeln(
        'Error: $entityName has no "$component" component to set a layer on.',
      );
      return 1;
    }

    final zIndex = parseIntOption('z-index', argResults!['z-index'] as String?);
    if (zIndex == null) return 1;

    SetLayerCommand(entity: entity, component: component, zIndex: zIndex)
        .apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Set $entityName.$component.zIndex to $zIndex in $path.');
    return 0;
  }
}

/// Flattens [entity]'s `tileMap` from its legend-authored form to the flat
/// `tiles` form that [SetTileCommand]/[FillRegionCommand] require, if it
/// isn't already — the same thing the studio GUI does on a tile edit's first
/// stroke.
void _ensureFlatTileMap(LevelDocument document, LevelEntity entity) {
  final map = entity.components['tileMap'];
  if (map != null && map.containsKey('legend')) {
    FlattenTileMapCommand(entity).apply(document);
  }
}

/// `game_agent studio paint-tile <level> --entity name --col c --row r --tile-id id`:
/// sets one tile. Id 0 erases.
class StudioPaintTileCommand extends Command<int> {
  @override
  final name = 'paint-tile';
  @override
  final description = 'Set one tile on an entity\'s tileMap. Tile id 0 erases.';

  StudioPaintTileCommand() {
    argParser
      ..addOption('entity', help: "Name of the entity carrying the tileMap.")
      ..addOption('col', help: 'Tile column.')
      ..addOption('row', help: 'Tile row.')
      ..addOption('tile-id', help: 'Tile id to write (0 erases).');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;
    if (!entity.components.containsKey('tileMap')) {
      stderr.writeln('Error: $entityName has no tileMap component.');
      return 1;
    }

    final col = parseIntOption('col', argResults!['col'] as String?);
    final row = parseIntOption('row', argResults!['row'] as String?);
    final tileId = parseIntOption('tile-id', argResults!['tile-id'] as String?);
    if (col == null || row == null || tileId == null) return 1;

    _ensureFlatTileMap(document, entity);
    SetTileCommand(entity: entity, col: col, row: row, tileId: tileId)
        .apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Set tile ($col, $row) to $tileId on $entityName in $path.');
    return 0;
  }
}

/// `game_agent studio fill-region <level> --entity name --col c --row r --tile-id id`:
/// flood-fills the four-connected region at (col, row) with tile-id.
class StudioFillRegionCommand extends Command<int> {
  @override
  final name = 'fill-region';
  @override
  final description =
      "Flood-fill the connected region of matching tiles at (col, row) on an entity's tileMap.";

  StudioFillRegionCommand() {
    argParser
      ..addOption('entity', help: "Name of the entity carrying the tileMap.")
      ..addOption('col', help: 'Tile column to start the fill from.')
      ..addOption('row', help: 'Tile row to start the fill from.')
      ..addOption('tile-id', help: 'Tile id to fill with.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;
    final document = loadLevelOrNull(path);
    if (document == null) return 1;

    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final entity = entityNamedOrNull(document, entityName);
    if (entity == null) return 1;
    if (!entity.components.containsKey('tileMap')) {
      stderr.writeln('Error: $entityName has no tileMap component.');
      return 1;
    }

    final col = parseIntOption('col', argResults!['col'] as String?);
    final row = parseIntOption('row', argResults!['row'] as String?);
    final tileId = parseIntOption('tile-id', argResults!['tile-id'] as String?);
    if (col == null || row == null || tileId == null) return 1;

    _ensureFlatTileMap(document, entity);
    FillRegionCommand(entity: entity, col: col, row: row, tileId: tileId)
        .apply(document);
    if (!validateAndWrite(path, document)) return 1;
    stdout.writeln('Filled region at ($col, $row) with $tileId on $entityName in $path.');
    return 0;
  }
}
