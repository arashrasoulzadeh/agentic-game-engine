import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:path/path.dart' as p;

import 'studio_command.dart' show canonicalJson;

/// `game_agent studio ...` edit verbs: thin adapters over the matching
/// `level.*` operations (undo, locks, structured errors). Historical stdout /
/// stderr wording is kept so `studio_golden_test.dart` stays green.
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
///
/// Kept for non-registry studio commands (e.g. asset helpers) that still
/// edit a document in memory.
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
/// is none.
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
/// it is valid JSON, otherwise the literal string.
Object? parseFieldValue(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// The level file argument every edit command takes, or null when missing.
String? levelPathOrNull(ArgResults results) {
  final rest = results.rest;
  if (rest.isEmpty) {
    stderr.writeln('Error: missing the level file.');
    return null;
  }
  return rest.first;
}

/// Project root + relative path for a level file (walks up for `pubspec.yaml`,
/// otherwise the file's parent is an ephemeral project root).
({String root, String rel}) _levelProject(String levelPath) {
  final abs = p.normalize(p.absolute(levelPath));
  var dir = p.dirname(abs);
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      return (
        root: dir,
        rel: p.relative(abs, from: dir).replaceAll('\\', '/'),
      );
    }
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  return (root: p.dirname(abs), rel: p.basename(abs));
}

void _printStudioOpError(OpError e, {required String displayPath}) {
  final details = e.details;
  final errors = details == null ? null : details['errors'];
  if (e.code == ErrorCode.validationFailed && errors is List) {
    stderr.writeln('Error: this would make $displayPath invalid:');
    for (final issue in errors) {
      stderr.writeln('  $issue');
    }
    return;
  }
  final msg = e.message;
  final body = msg.isEmpty ? msg : '${msg[0].toLowerCase()}${msg.substring(1)}';
  stderr.writeln('Error: $body');
  if (e.hint != null) stderr.writeln(e.hint);
}

/// Calls [op] with [apply] (and auto-confirms destructive previews so the
/// historical one-shot `studio` verbs keep working).
Future<OpResult?> _callLevelOp(
  String op,
  String levelPath,
  Map<String, Object?> args,
) async {
  if (!File(levelPath).existsSync()) {
    stderr.writeln('Error: $levelPath does not exist.');
    return null;
  }
  final located = _levelProject(levelPath);
  final ctx = OpContext(
    project: ProjectRoot(located.root),
    actor: 'cli',
  );
  final registry = buildRegistry();
  final callArgs = {...args, 'path': located.rel, 'apply': true};
  var result = await registry.call(op, callArgs, ctx);
  // Destructive ops refuse apply without a token; pull it from the error
  // preview (or a dry-run success) and re-call so one-shot studio verbs
  // still complete without a second CLI invocation.
  final token = _confirmationToken(result);
  if (token != null) {
    result = await registry.call(op, {
      ...callArgs,
      'confirmation': token,
    }, ctx);
  }
  if (!result.ok) {
    _printStudioOpError(result.error!, displayPath: levelPath);
  }
  return result;
}

String? _confirmationToken(OpResult result) {
  if (result.ok && result.data is Map) {
    final data = result.data! as Map;
    if (data['preview'] == true && data['confirmation'] is String) {
      return data['confirmation'] as String;
    }
  }
  if (!result.ok &&
      result.error!.code == ErrorCode.confirmationRequired) {
    final preview = result.error!.details?['preview'];
    if (preview is Map && preview['confirmation'] is String) {
      return preview['confirmation'] as String;
    }
  }
  return null;
}

/// `game_agent studio add-entity <level> [--name x] [--component c ...] [--index n]`.
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
        help:
            'A component to give the entity, at its schema defaults. Repeatable.',
      )
      ..addOption('index', help: 'Position to insert at. Defaults to the end.');
  }

  @override
  Future<int> run() async {
    final path = levelPathOrNull(argResults!);
    if (path == null) return 1;

    final indexText = argResults!['index'] as String?;
    int? index;
    if (indexText != null) {
      index = int.tryParse(indexText);
      if (index == null) {
        stderr.writeln('Error: --index must be an integer, got "$indexText".');
        return 1;
      }
    }

    final name = argResults!['name'] as String?;
    final result = await _callLevelOp('level.add_entity', path, {
      if (name != null) 'name': name,
      'components': argResults!['component'] as List<String>,
      if (index != null) 'index': index,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln(
      'Added entity${name == null ? '' : ' $name'} to $path.',
    );
    return 0;
  }
}

/// `game_agent studio remove-entity <level> --entity name`.
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
    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final result = await _callLevelOp('level.remove_entity', path, {
      'name': entityName,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln('Removed entity $entityName from $path.');
    return 0;
  }
}

/// `game_agent studio set-field <level> --entity name --component c --field f --value v`.
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
    final entityName = argResults!['entity'] as String?;
    final component = argResults!['component'] as String?;
    final field = argResults!['field'] as String?;
    final valueText = argResults!['value'] as String?;
    if (entityName == null ||
        component == null ||
        field == null ||
        valueText == null) {
      stderr.writeln(
        'Error: --entity, --component, --field, and --value are all required.',
      );
      return 1;
    }
    final result = await _callLevelOp('level.set_field', path, {
      'entity': entityName,
      'component': component,
      'field': field,
      'value': parseFieldValue(valueText),
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln('Set $entityName.$component.$field in $path.');
    return 0;
  }
}

/// `game_agent studio move-entity <level> --entity name --x X --y Y`.
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
    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final x = parseDoubleOption('x', argResults!['x'] as String?);
    final y = parseDoubleOption('y', argResults!['y'] as String?);
    if (x == null || y == null) return 1;
    final result = await _callLevelOp('level.move_entity', path, {
      'name': entityName,
      'x': x,
      'y': y,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln('Moved $entityName to ($x, $y) in $path.');
    return 0;
  }
}

/// `game_agent studio set-layer <level> --entity name --component c --z-index n`.
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
    final entityName = argResults!['entity'] as String?;
    final component = argResults!['component'] as String?;
    if (entityName == null || component == null) {
      stderr.writeln('Error: --entity and --component are required.');
      return 1;
    }
    final zIndex = parseIntOption('z-index', argResults!['z-index'] as String?);
    if (zIndex == null) return 1;
    final result = await _callLevelOp('level.set_layer', path, {
      'entity': entityName,
      'component': component,
      'z': zIndex,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln('Set $entityName.$component.zIndex to $zIndex in $path.');
    return 0;
  }
}

/// `game_agent studio paint-tile <level> --entity name --col c --row r --tile-id id`.
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
    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final col = parseIntOption('col', argResults!['col'] as String?);
    final row = parseIntOption('row', argResults!['row'] as String?);
    final tileId = parseIntOption('tile-id', argResults!['tile-id'] as String?);
    if (col == null || row == null || tileId == null) return 1;
    final result = await _callLevelOp('level.paint_tile', path, {
      'entity': entityName,
      'col': col,
      'row': row,
      'tileId': tileId,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln('Set tile ($col, $row) to $tileId on $entityName in $path.');
    return 0;
  }
}

/// `game_agent studio fill-region <level> --entity name --col c --row r --tile-id id`.
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
    final entityName = argResults!['entity'] as String?;
    if (entityName == null) {
      stderr.writeln('Error: --entity is required.');
      return 1;
    }
    final col = parseIntOption('col', argResults!['col'] as String?);
    final row = parseIntOption('row', argResults!['row'] as String?);
    final tileId = parseIntOption('tile-id', argResults!['tile-id'] as String?);
    if (col == null || row == null || tileId == null) return 1;
    final result = await _callLevelOp('level.fill_region', path, {
      'entity': entityName,
      'col': col,
      'row': row,
      'tileId': tileId,
    });
    if (result == null || !result.ok) return 1;
    stdout.writeln(
      'Filled region at ($col, $row) with $tileId on $entityName in $path.',
    );
    return 0;
  }
}
