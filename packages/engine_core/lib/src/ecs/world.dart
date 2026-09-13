import 'component_registry.dart';
import 'component_store.dart';
import 'entity.dart';
import 'event_bus.dart';
import 'system.dart';

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
  void applyPatch(Map<String, dynamic> patch) {
    final entityPatches = patch['entities'] as List<dynamic>? ?? const [];
    for (final raw in entityPatches) {
      final e = raw as Map<String, dynamic>;
      final id = e['id'] as int;
      if (!entities.isAlive(id)) continue;
      components.applyToEntity(id, e['components'] as Map<String, dynamic>);
    }
  }
}
