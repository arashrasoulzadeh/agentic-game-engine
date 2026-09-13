import 'entity.dart';
import 'world.dart';

/// Thrown when level JSON fails validation. Carries a specific,
/// human/agent-readable path to the bad field rather than a generic
/// "invalid JSON" — a content-authoring agent needs to know exactly
/// what to fix.
class LevelLoadException implements Exception {
  final String message;
  LevelLoadException(this.message);

  @override
  String toString() => 'LevelLoadException: $message';
}

/// Loads declarative level/entity data into a `World`. This is the
/// content DSL: `{"entities": [{"components": {"position": {...}, ...}}]}`
/// — plain JSON an agent (or a human) can author without touching Dart,
/// built directly on the `ComponentRegistry`/`applyPatch` machinery
/// `World` already exposes for its own snapshot/patch API.
class Level {
  /// Validates [json], then spawns one entity per item in `entities`,
  /// applying its `components` map via the same path `World.applyPatch`
  /// uses. Throws [LevelLoadException] with a specific message on any
  /// structural problem — never silently drops or misapplies data.
  ///
  /// Returns the ids of every entity that had a `"name"` key, keyed by
  /// that name — how calling code finds "the player"/"the door" etc.
  /// after a data-driven load, for anything a level file can't express
  /// itself (attaching a live `InputState`, passing an id to
  /// `installPlatformerSystems`). An entity with no `"name"` isn't in
  /// the returned map at all; it's still spawned normally.
  static Map<String, EntityId> loadInto(World world, Map<String, dynamic> json) {
    final entities = validate(json);
    final named = <String, EntityId>{};
    for (final entityJson in entities) {
      final id = world.spawn();
      final components =
          entityJson['components'] as Map<String, dynamic>? ?? const {};
      world.components.applyToEntity(id, components);
      if (entityJson['name'] case final String name) {
        named[name] = id;
      }
    }
    return named;
  }

  /// Validates [json] and returns its `entities` list, cast, on success.
  /// Exposed separately so tools (e.g. a CLI lint command) can validate
  /// a level file without loading it into a live World.
  static List<Map<String, dynamic>> validate(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    if (rawEntities == null) {
      throw LevelLoadException('Level JSON is missing required key "entities"');
    }
    if (rawEntities is! List) {
      throw LevelLoadException(
          '"entities" must be a list, got ${rawEntities.runtimeType}');
    }

    final entities = <Map<String, dynamic>>[];
    for (var i = 0; i < rawEntities.length; i++) {
      final entry = rawEntities[i];
      if (entry is! Map) {
        throw LevelLoadException(
            'entities[$i] must be an object, got ${entry.runtimeType}');
      }
      final entityJson = entry.cast<String, dynamic>();

      if (entityJson.containsKey('name') && entityJson['name'] is! String) {
        throw LevelLoadException(
            'entities[$i].name must be a string, got ${entityJson['name'].runtimeType}');
      }

      if (entityJson.containsKey('components')) {
        final components = entityJson['components'];
        if (components is! Map) {
          throw LevelLoadException(
              'entities[$i].components must be an object, got ${components.runtimeType}');
        }
        for (final key in components.keys) {
          if (key is! String) {
            throw LevelLoadException(
                'entities[$i].components has a non-string key: $key');
          }
          if (components[key] is! Map) {
            throw LevelLoadException(
                'entities[$i].components["$key"] must be an object, got ${components[key].runtimeType}');
          }
        }
      }
      entities.add(entityJson);
    }
    return entities;
  }
}
