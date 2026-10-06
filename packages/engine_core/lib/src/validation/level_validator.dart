import '../content/level_document.dart';
import 'package:engine_schema/engine_schema.dart';

import '../ecs/component_registry.dart';
import '../physics/tile_map.dart';
import 'reachability.dart';

/// How serious a [LevelIssue] is. An error means the level will not run as
/// designed; a warning means it may still be fine, but the check could not
/// prove it.
enum IssueSeverity { error, warning }

/// One problem found in a [LevelDocument]: which entity, which component (when
/// the problem is inside one), and a message that names the field. The studio
/// shows [message] verbatim, so it says what is wrong rather than just "invalid".
class LevelIssue {
  final int entityIndex;
  final String? entityName;
  final String? component;
  final String message;
  final IssueSeverity severity;

  const LevelIssue({
    required this.entityIndex,
    required this.entityName,
    required this.component,
    required this.message,
    this.severity = IssueSeverity.error,
  });

  @override
  String toString() {
    final where = entityName ?? 'entities[$entityIndex]';
    final inside = component == null ? '' : '.$component';
    return '$where$inside: $message';
  }
}

/// Checks a [LevelDocument] against the components registered in [components].
///
/// Used by the studio for its live validation panel and by `game_agent studio
/// validate` in CI, so both report the same problems. Checks return every
/// issue, not only the first, so a designer can fix them in one pass.
class LevelValidator {
  /// The schema for a component name, or null when it has none.
  final ComponentSchema? Function(String name) schemaFor;

  /// Whether a component name is known at all. A known component without a
  /// schema is reported as unchecked; an unknown one as a typo.
  final bool Function(String name) isKnown;

  const LevelValidator({required this.schemaFor, required this.isKnown});

  /// Validates against a live registry, which knows exactly what a running game
  /// registers. Use this inside the engine and its tests.
  factory LevelValidator.forRegistry(ComponentRegistry components) => LevelValidator(
        schemaFor: components.schemaFor,
        isKnown: components.isRegistered,
      );

  /// Validates against a plain schema map, such as `allComponentSchemas`, for
  /// tools that cannot register components (the CLI, the studio). Every name
  /// missing from [schemas] is reported as unknown.
  factory LevelValidator.forSchemas(Map<String, ComponentSchema> schemas) => LevelValidator(
        schemaFor: (name) => schemas[name],
        isKnown: schemas.containsKey,
      );

  /// Every issue in [document], in entity order. Empty when the level is valid.
  List<LevelIssue> validate(LevelDocument document) {
    final issues = <LevelIssue>[];
    for (var i = 0; i < document.entities.length; i++) {
      final entity = document.entities[i];
      for (final entry in entity.components.entries) {
        final name = entry.key;
        if (name == 'tileMap' && entry.value.containsKey('legend')) {
          for (final message in _legendTileMapProblems(entry.value)) {
            issues.add(LevelIssue(
              entityIndex: i,
              entityName: entity.name,
              component: name,
              message: message,
            ));
          }
          continue;
        }
        final schema = schemaFor(name);
        if (schema == null) {
          issues.add(
            LevelIssue(
              entityIndex: i,
              entityName: entity.name,
              component: name,
              message: !isKnown(name)
                  ? 'unknown component "$name"'
                  : 'component "$name" has no schema, so its fields cannot be checked',
            ),
          );
          continue;
        }
        for (final message in schema.validate(entry.value)) {
          issues.add(
            LevelIssue(
              entityIndex: i,
              entityName: entity.name,
              component: name,
              message: message,
            ),
          );
        }
      }
    }
    _checkExitReachability(document, issues);
    return issues;
  }

  /// Checks the legend-authored `tileMap` form: the ASCII `rows` a designer
  /// writes, and the `legend` that maps each character to a tile id. The flat
  /// `tiles` form is checked by the schema instead.
  static List<String> _legendTileMapProblems(Map<String, dynamic> map) {
    final problems = <String>[];
    final legend = map['legend'];
    if (legend is! Map) {
      return ['legend must be an object mapping characters to tile ids'];
    }
    final rows = map['rows'];
    if (rows is! List || rows.any((row) => row is! String)) {
      return ['rows must be a list of strings, one per map row'];
    }
    for (var r = 0; r < rows.length; r++) {
      for (final character in (rows[r] as String).split('')) {
        if (!legend.containsKey(character)) {
          problems.add('row $r uses "$character", which is not in the legend');
        }
      }
    }
    return problems;
  }

  /// Warns for each exit no walker from the player can reach. Skipped when the
  /// level has no tile map, no player, or a tile map that fails to parse (that
  /// failure is reported by the schema check already).
  void _checkExitReachability(LevelDocument document, List<LevelIssue> issues) {
    final mapIndex = document.entities.indexWhere((e) => e.components.containsKey('tileMap'));
    final playerIndex = document.entities.indexWhere((e) => e.name == 'player');
    if (mapIndex < 0 || playerIndex < 0) return;

    final TileMap map;
    try {
      map = TileMap.fromJson(document.entities[mapIndex].components['tileMap']!);
    } on Object {
      return;
    }
    final origin = _position(document.entities[mapIndex].components);
    final player = _position(document.entities[playerIndex].components);
    if (origin == null || player == null) return;

    for (var i = 0; i < document.entities.length; i++) {
      final exit = document.entities[i];
      if (!exit.components.containsKey('roomExit')) continue;
      final at = _position(exit.components);
      if (at == null) continue;
      final reachable = isTileReachable(
        map,
        startX: player.x - origin.x,
        startY: player.y - origin.y,
        targetX: at.x - origin.x,
        targetY: at.y - origin.y,
      );
      if (!reachable) {
        issues.add(LevelIssue(
          entityIndex: i,
          entityName: exit.name,
          component: 'roomExit',
          message: 'exit is not reachable from the player by walking or jumping',
          severity: IssueSeverity.warning,
        ));
      }
    }
  }

  static ({double x, double y})? _position(Map<String, Map<String, dynamic>> components) {
    final position = components['position'];
    if (position == null) return null;
    final x = position['x'];
    final y = position['y'];
    if (x is! num || y is! num) return null;
    return (x: x.toDouble(), y: y.toDouble());
  }
}
