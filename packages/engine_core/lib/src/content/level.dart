import '../ecs/engine_error.dart';
import '../ecs/entity.dart';
import '../ecs/name.dart';
import 'prefab_registry.dart';
import '../ecs/world.dart';

/// Thrown when level JSON fails validation. Carries a specific,
/// human/agent-readable path to the bad field rather than a generic
/// "invalid JSON" — a content-authoring agent needs to know exactly
/// what to fix.
class LevelLoadException implements EngineError {
  @override
  final String message;

  /// Every located problem when strict loading rejected the level; empty for
  /// a single structural fault described by [message].
  final List<ErrorProblem> problems;

  LevelLoadException(this.message, {this.problems = const []});

  @override
  String get code => 'level_invalid';

  @override
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (problems.isNotEmpty) 'problems': [for (final p in problems) p.toJson()],
  };

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
  ///
  /// By default unknown component names are skipped, so partial or
  /// forward-compatible data still loads. With [strict] every component is
  /// checked first (unknown name, not an object, or rejected by its own
  /// `fromJson`) and a [LevelLoadException] lists every problem with its
  /// `entities[i].components.name` path; nothing is spawned in that case.
  ///
  /// With [defaults], a field a component's schema gives a default is filled in
  /// when the level leaves it out (`{"position": {"x": 5}}` gets `y: 0`), so
  /// authors write only what differs. Fields without a declared default are
  /// still required. With [prefabs], entities carrying a `prefabRef` are
  /// replaced by that prefab (see [PrefabRegistry.expandRefs]); a named
  /// placeholder's name moves to the prefab's first entity.
  static Map<String, EntityId> loadInto(
    World world,
    Map<String, dynamic> json, {
    bool strict = false,
    PrefabRegistry? prefabs,
    bool defaults = false,
  }) {
    var entities = validate(json);
    if (defaults) entities = _withDefaults(world, entities);
    if (strict) {
      final problems = <ErrorProblem>[];
      for (var i = 0; i < entities.length; i++) {
        final components =
            entities[i]['components'] as Map<String, dynamic>? ?? const {};
        for (final entry in components.entries) {
          final problem = world.components.checkComponent(
            entry.key,
            entry.value,
          );
          if (problem != null) {
            problems.add(
              ErrorProblem('entities[$i].components.${entry.key}', problem),
            );
          }
        }
      }
      if (problems.isNotEmpty) {
        throw LevelLoadException(
          'Level has ${problems.length} invalid component '
          '${problems.length == 1 ? 'entry' : 'entries'}:\n  '
          '${problems.map((p) => '${p.path}: ${p.message}').join('\n  ')}',
          problems: problems,
        );
      }
    }
    final named = <String, EntityId>{};
    final spawned = <EntityId>[];
    for (final entityJson in entities) {
      final id = world.spawn();
      spawned.add(id);
      final components =
          entityJson['components'] as Map<String, dynamic>? ?? const {};
      world.components.applyToEntity(id, components);
      if (entityJson['name'] case final String name) {
        named[name] = id;
        if (world.components.isRegistered('name')) world.setName(id, name);
      }
    }
    if (prefabs != null) {
      final replaced = prefabs.expandRefs(world, only: spawned);
      for (final entry in named.entries.toList()) {
        final instance = replaced[entry.value];
        if (instance == null) continue;
        named[entry.key] = instance.root;
        if (world.components.isRegistered('name')) {
          world.setName(instance.root, entry.key);
        }
      }
    }
    return named;
  }

  /// True when [json] looks like an engine [Level] / [LevelDocument]
  /// (`entities` list present) rather than a game-specific sidecar
  /// (e.g. Mobarez wave/boss JSON under `assets/levels/`).
  ///
  /// Studio uses this to open custom formats in the text editor instead of
  /// failing inside the tile level editor.
  static bool looksLikeDocument(Object? json) {
    if (json is! Map) return false;
    return json['entities'] is List;
  }

  /// Validates [json] and returns its `entities` list, cast, on success.
  static List<Map<String, dynamic>> _withDefaults(
    World world,
    List<Map<String, dynamic>> entities,
  ) {
    return [
      for (final entity in entities)
        {
          ...entity,
          if (entity['components'] case final Map<String, dynamic> components)
            'components': {
              for (final entry in components.entries)
                entry.key: _fill(world, entry.key, entry.value),
            },
        },
    ];
  }

  static Object? _fill(World world, String name, Object? value) {
    final schema = world.components.schemaFor(name);
    if (schema == null || value is! Map) return value;
    return {...schema.defaults, ...value.cast<String, dynamic>()};
  }

  /// Exposed separately so tools (e.g. a CLI lint command) can validate
  /// a level file without loading it into a live World.
  static List<Map<String, dynamic>> validate(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    if (rawEntities == null) {
      throw LevelLoadException('Level JSON is missing required key "entities"');
    }
    if (rawEntities is! List) {
      throw LevelLoadException(
        '"entities" must be a list, got ${rawEntities.runtimeType}',
      );
    }

    final entities = <Map<String, dynamic>>[];
    for (var i = 0; i < rawEntities.length; i++) {
      final entry = rawEntities[i];
      if (entry is! Map) {
        throw LevelLoadException(
          'entities[$i] must be an object, got ${entry.runtimeType}',
        );
      }
      final entityJson = entry.cast<String, dynamic>();

      if (entityJson.containsKey('name') && entityJson['name'] is! String) {
        throw LevelLoadException(
          'entities[$i].name must be a string, got ${entityJson['name'].runtimeType}',
        );
      }

      if (entityJson.containsKey('components')) {
        final components = entityJson['components'];
        if (components is! Map) {
          throw LevelLoadException(
            'entities[$i].components must be an object, got ${components.runtimeType}',
          );
        }
        for (final key in components.keys) {
          if (key is! String) {
            throw LevelLoadException(
              'entities[$i].components has a non-string key: $key',
            );
          }
          if (components[key] is! Map) {
            throw LevelLoadException(
              'entities[$i].components["$key"] must be an object, got ${components[key].runtimeType}',
            );
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
    _entityIds = _world.entities.all
        .where((id) => !before.contains(id))
        .toList();
  }
}
