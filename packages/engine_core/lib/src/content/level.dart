import '../ecs/entity.dart';
import '../ecs/world.dart';

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

/// Tracks every entity a single [Level.loadInto] call spawned, so that
/// content can be hot-reloaded into a *running* `World` — an agent (or
/// a human) editing a level JSON file wants to see the result without a
/// full app restart, which otherwise means either leaking the old
/// entities (spawning duplicates on top of them) or hand-tracking which
/// ids belong to which level load. `Level.loadInto` itself only returns
/// *named* entities (by design — that's the "find the player/door"
/// contract other code depends on); `LevelHandle` additionally keeps
/// every id, named or not, so [reload] can cleanly tear the old set
/// down first.
class LevelHandle {
  final World _world;
  List<EntityId> _entityIds;
  Map<String, EntityId> _named;

  LevelHandle._(this._world, this._entityIds, this._named);

  /// Loads [json] into [world] via [Level.loadInto], returning a handle
  /// that can later [reload] with new JSON.
  factory LevelHandle.load(World world, Map<String, dynamic> json) {
    final handle = LevelHandle._(world, const [], const {});
    handle._loadFresh(json);
    return handle;
  }

  /// Every entity currently alive from the last successful load —
  /// named and unnamed alike.
  List<EntityId> get entityIds => List.unmodifiable(_entityIds);

  /// The named entities from the last successful load, same contract
  /// as [Level.loadInto]'s return value.
  Map<String, EntityId> get named => Map.unmodifiable(_named);

  /// Destroys every entity from the current load, then loads [json] in
  /// its place. Validates [json] *before* destroying anything — a
  /// malformed edit (the common case while iterating on content)
  /// throws [LevelLoadException] and leaves the previous level fully
  /// intact rather than tearing it down for a load that was never
  /// going to succeed.
  void reload(Map<String, dynamic> json) {
    Level.validate(json); // throws before anything is torn down
    for (final id in _entityIds) {
      _world.destroy(id);
    }
    _loadFresh(json);
  }

  void _loadFresh(Map<String, dynamic> json) {
    final before = Set<EntityId>.from(_world.entities.all);
    _named = Level.loadInto(_world, json);
    _entityIds = _world.entities.all.where((id) => !before.contains(id)).toList();
  }
}
