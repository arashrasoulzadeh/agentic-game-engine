import 'component_registry.dart';
import 'component_store.dart';
import 'entity.dart';
import 'event_bus.dart';
import 'system.dart';

/// Thrown by [World.applyPatch] when the patch's own shape is wrong —
/// `entities` not a list, an entry not an object, a missing/malformed
/// `id`. Mirrors `Level.validate`'s `LevelLoadException`: a specific,
/// human/agent-readable path to the bad field rather than a bare
/// `TypeError` from a failed cast. Per-component problems (a bad
/// `fromJson`) throw `ComponentApplyException` instead, from
/// `ComponentRegistry.applyToEntity`.
class WorldPatchException implements Exception {
  final String message;
  WorldPatchException(this.message);

  @override
  String toString() => 'WorldPatchException: $message';
}

/// The simulation root: owns entities, components, systems, and events.
/// Deliberately has no rendering or Flutter knowledge — engine_flutter
/// reads from a World to draw; it never writes gameplay state into it.
class World {
  final double width;
  final double height;

  final EntityManager entities = EntityManager();
  final ComponentRegistry components = ComponentRegistry();
  final EventBus events = EventBus();
  final List<System> _systems = [];

  int _tick = 0;
  int get tick => _tick;

  World({required this.width, required this.height});

  void addSystem(System system) => _systems.add(system);

  List<String> get systemOrder => _systems.map((s) => s.name).toList();

  ComponentStore<T> storeOf<T>() => components.storeOf<T>();

  EntityId spawn() => entities.create();

  void destroy(EntityId id) {
    for (final reg in components.all) {
      reg.removeEntity(id);
    }
    entities.destroy(id);
  }

  /// Runs every registered system once, in registration order, then
  /// flushes events emitted during this tick. Fixed timestep is enforced
  /// by the caller (engine_flutter's ticker) — World just executes dt.
  void step(double dt) {
    for (final system in _systems) {
      system.update(this, dt);
    }
    events.flush();
    _tick++;
  }

  /// Full world snapshot as plain JSON — the agent-facing read path.
  Map<String, dynamic> toJson() => {
        'tick': _tick,
        'width': width,
        'height': height,
        'entities': [
          for (final id in entities.all)
            {'id': id, 'components': components.serializeEntity(id)},
        ],
      };

  /// Applies a snapshot produced by [toJson] (or a partial patch with a
  /// subset of entities/components) — the agent-facing write path.
  /// Throws [WorldPatchException] on a malformed patch shape, or
  /// [ComponentApplyException] if a named component's own JSON is bad
  /// — never a bare, contextless `TypeError`.
  void applyPatch(Map<String, dynamic> patch) {
    final rawEntities = patch['entities'];
    if (rawEntities == null) return;
    if (rawEntities is! List) {
      throw WorldPatchException(
          '"entities" must be a list, got ${rawEntities.runtimeType}');
    }
    for (var i = 0; i < rawEntities.length; i++) {
      final raw = rawEntities[i];
      if (raw is! Map) {
        throw WorldPatchException(
            'entities[$i] must be an object, got ${raw.runtimeType}');
      }
      final e = raw.cast<String, dynamic>();
      final rawId = e['id'];
      if (rawId is! int) {
        throw WorldPatchException(
            'entities[$i].id must be an int, got ${rawId.runtimeType}');
      }
      if (!entities.isAlive(rawId)) continue;
      final rawComponents = e['components'];
      if (rawComponents == null) continue;
      if (rawComponents is! Map) {
        throw WorldPatchException(
            'entities[$i].components must be an object, got '
            '${rawComponents.runtimeType}');
      }
      components.applyToEntity(rawId, rawComponents.cast<String, dynamic>());
    }
  }
}
