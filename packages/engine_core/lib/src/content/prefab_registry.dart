import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'level.dart';
import 'prefab.dart';

/// What [PrefabRegistry.spawn] created.
class PrefabInstance {
  /// Every spawned entity, in the prefab's entity order.
  final List<EntityId> ids;

  /// The entities that had a name, keyed by their final (uniquified) name.
  final Map<String, EntityId> named;

  PrefabInstance(this.ids, this.named);

  /// The first entity, the usual "main" one of a prefab.
  EntityId get root => ids.first;
}

/// Named [Prefab]s a game can spawn into a live world: `registry.spawn(world,
/// 'enemy', 100, 50)`. The data side (a prefab as JSON under `prefabs/`) is the
/// same `Prefab` the editor and the `prefab.*` operations use; this adds the
/// runtime lookup by name.
class PrefabRegistry {
  final Map<String, Prefab> _prefabs = {};

  /// Registers [prefab] under its own name, replacing any earlier one.
  void register(Prefab prefab) => _prefabs[prefab.name] = prefab;

  /// Registers a prefab read from JSON (a `prefabs/*.json` file's contents).
  void registerJson(Map<String, dynamic> json) =>
      register(Prefab.fromJson(json));

  /// Whether a prefab is registered as [name].
  bool has(String name) => _prefabs.containsKey(name);

  /// Registered names, sorted.
  List<String> get names => _prefabs.keys.toList()..sort();

  /// Spawns the prefab [name] with its origin at ([x], [y]). Fresh entities
  /// every call; component data goes through the same validation as a level
  /// load, and every component is checked before anything spawns, so a prefab
  /// with an unknown or malformed component fails here (spawning nothing)
  /// instead of producing a half-built entity.
  /// Throws [ArgumentError] listing the known names for an unknown [name].
  PrefabInstance spawn(
    World world,
    String name,
    double x,
    double y, {
    Set<String> takenNames = const {},
  }) {
    final prefab = _prefabs[name];
    if (prefab == null) {
      throw ArgumentError.value(
        name,
        'name',
        'No prefab registered under this name. Known: '
            '${names.isEmpty ? '(none)' : names.join(', ')}.',
      );
    }
    final entities = prefab.instantiate(x, y, taken: takenNames);
    Level.validate({
      'entities': [for (final e in entities) e.toJson()],
    });
    // Unlike a level load, which skips unknown component names so partial
    // data still loads, a prefab is checked up front: a typo'd component
    // would otherwise spawn a silently incomplete entity.
    for (final e in entities) {
      for (final entry in e.components.entries) {
        final problem = world.components.checkComponent(entry.key, entry.value);
        if (problem != null) {
          throw ArgumentError.value(
            name,
            'name',
            'Prefab "$name" is invalid: $problem.',
          );
        }
      }
    }
    final ids = <EntityId>[];
    final named = <String, EntityId>{};
    for (final e in entities) {
      final id = world.spawn();
      world.components.applyToEntity(id, e.components);
      ids.add(id);
      if (e.name != null) named[e.name!] = id;
    }
    return PrefabInstance(ids, named);
  }
}
