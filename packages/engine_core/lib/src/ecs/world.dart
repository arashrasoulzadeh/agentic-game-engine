import 'component_registry.dart';
import 'component_store.dart';
import 'entity.dart';
import 'event_bus.dart';
import 'system.dart';
import 'archetype.dart';
import 'job_system.dart';
import 'world_profiler.dart';
import 'world_commands.dart';
import 'world_random.dart';

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
  final List<_SystemEntry> _systems = [];

  /// Job system for multithreaded work (collision broadphase, pathfinding, etc.).
  /// Lazy-initialized on first access.
  JobSystem? _jobSystem;
  JobSystem get jobSystem {
    _jobSystem ??= JobSystem();
    return _jobSystem!;
  }

  /// When set, `step` times every system (see [WorldProfiler]). Null by
  /// default, in which case `step` runs the untimed loop.
  WorldProfiler? profiler;

  int _tick = 0;
  int get tick => _tick;

  /// Sets the tick counter -- for restoring a snapshot (rollback, network
  /// sync), where the world must resume at the tick it was captured at.
  void setTick(int tick) => _tick = tick;

  /// `dt` of the [step] currently running (or the last completed step).
  ///
  /// Set at the start of every [step] so `Action.apply` (and anything else
  /// that only sees a [World], not the system's `dt` argument) can read the
  /// real tick length — e.g. FSM/BT runners that stash `_dt` on a
  /// blackboard. `0` before the first `step`.
  double _deltaTime = 0;
  double get deltaTime => _deltaTime;

  /// Creates a world. [seed] starts [random]; the default is a fixed 0 so a
  /// world is reproducible unless you ask otherwise: pass a varying seed for a
  /// game that should play differently each run (and record it to replay).
  World({required this.width, required this.height, this.seed = 0})
    : random = WorldRandom(seed);

  /// The seed [random] started from.
  final int seed;

  /// The simulation's random numbers. Draw from this, not `dart:math`, so
  /// runs are reproducible and a rollback restores the stream.
  final WorldRandom random;

  /// Returns the archetype manager for optimized queries.
  ArchetypeManager get archetypes => components.archetypeManager;

  /// Registers [system] to run in [step].
  ///
  /// Systems run ordered by [phase] first, then in the order they were added
  /// within a phase. The default [SystemPhase.physics] is shared by everything
  /// registered without a phase, so code that never mentions phases keeps its
  /// exact insertion order.
  ///
  /// [after] names systems that must run before this one. It does not reorder
  /// anything; [validateSystemOrder] reports when the real order breaks it, so
  /// a hand-built system list cannot silently drift into a known bad order.
  void addSystem(
    System system, {
    SystemPhase phase = SystemPhase.physics,
    List<String> after = const [],
  }) {
    final entry = _SystemEntry(system, phase, after);
    var at = _systems.length;
    while (at > 0 && _systems[at - 1].phase.index > phase.index) {
      at--;
    }
    _systems.insert(at, entry);
  }

  List<String> get systemOrder => _systems.map((e) => e.system.name).toList();

  /// Problems with the current system order, as readable sentences; empty when
  /// every `after:` declaration is satisfied.
  ///
  /// Reports a declared predecessor that is not registered at all, and one that
  /// is registered but runs later than the system that needs it (including
  /// because of its phase).
  List<String> validateSystemOrder() {
    final problems = <String>[];
    for (var i = 0; i < _systems.length; i++) {
      final entry = _systems[i];
      for (final needed in entry.after) {
        var lastAt = -1;
        for (var j = 0; j < _systems.length; j++) {
          if (_systems[j].system.name == needed) lastAt = j;
        }
        if (lastAt == -1) {
          problems.add(
            '"${entry.system.name}" must run after "$needed", but no system '
            'named "$needed" is registered. Registered: '
            '${systemOrder.join(', ')}.',
          );
        } else if (lastAt > i) {
          problems.add(
            '"${entry.system.name}" (position ${i + 1}) must run after '
            '"$needed", but "$needed" runs later (position ${lastAt + 1}). '
            'Register "$needed" first or move it to an earlier phase.',
          );
        }
      }
    }
    return problems;
  }

  /// Turns every system named [name] on or off without removing it.
  ///
  /// A disabled system is skipped by [step] (it keeps its place in
  /// [systemOrder]) and picks up again, with whatever state it holds, when
  /// re-enabled. Throws [ArgumentError] when no system has that name, with the
  /// registered names, since a typo would otherwise silently do nothing.
  void setSystemEnabled(String name, bool enabled) {
    var found = false;
    for (final entry in _systems) {
      if (entry.system.name == name) {
        entry.enabled = enabled;
        found = true;
      }
    }
    if (!found) {
      throw ArgumentError.value(
        name,
        'name',
        'No system named "$name". Registered: ${systemOrder.join(', ')}.',
      );
    }
  }

  /// Whether the system named [name] runs in [step]. False if it is disabled
  /// or unknown; with several systems of that name, true only if all are on.
  bool isSystemEnabled(String name) {
    var found = false;
    for (final entry in _systems) {
      if (entry.system.name == name) {
        found = true;
        if (!entry.enabled) return false;
      }
    }
    return found;
  }

  ComponentStore<T> storeOf<T>() => components.storeOf<T>();

  /// Every [T] component in the world, as a dense collection for iteration and
  /// bulk work. Prefer [getComponent]/[setComponent] for a single entity.
  ///
  /// Throws if [T] was never registered (see `registerCoreComponents` & co.).
  ComponentStore<T> componentsOf<T>() => components.storeOf<T>();

  /// The [T] on [entity], or null when it has none (or is not alive).
  T? getComponent<T>(EntityId entity) => components.storeOf<T>().get(entity);

  /// Attaches [value] as [entity]'s [T], replacing any existing one.
  ///
  /// Throws [StateError] when [entity] is not alive: ids are recycled, so a
  /// component written to a dead id would silently show up on whichever entity
  /// reuses it next.
  void setComponent<T>(EntityId entity, T value) {
    if (!entities.isAlive(entity)) {
      throw StateError(
        'Cannot set $T on entity $entity: it is not alive (destroyed, or '
        'never spawned). Spawn it with world.spawn() first.',
      );
    }
    components.storeOf<T>().set(entity, value);
  }

  /// Whether [entity] currently has a [T].
  bool hasComponent<T>(EntityId entity) => components.storeOf<T>().has(entity);

  /// Detaches [entity]'s [T]; a no-op when it has none or is not alive.
  void removeComponent<T>(EntityId entity) =>
      components.storeOf<T>().remove(entity);

  /// Changes queued by systems to be applied between systems; see
  /// [WorldCommands]. Use this instead of mutating while you iterate.
  late final WorldCommands commands = WorldCommands(this);

  EntityId spawn() => entities.create();

  /// Incarnation counter of [id]; see [EntityManager.generationOf].
  int generationOf(EntityId id) => entities.generationOf(id);

  void destroy(EntityId id) {
    for (final reg in components.all) {
      reg.removeEntity(id);
    }
    entities.destroy(id);
    components.archetypeManager.onEntityDestroyed(id);
  }

  /// Runs every registered system once, in registration order, then
  /// flushes events emitted during this tick. Fixed timestep is enforced
  /// by the caller (engine_flutter's ticker) — World just executes dt.
  void step(double dt) {
    _deltaTime = dt;
    final profiler = this.profiler;
    if (profiler == null) {
      for (final entry in _systems) {
        if (!entry.enabled) continue;
        entry.system.update(this, dt);
        commands.apply();
      }
      events.flush();
      commands.apply();
    } else {
      _profiledStep(profiler, dt);
    }
    _tick++;
  }

  void _profiledStep(WorldProfiler profiler, double dt) {
    final whole = Stopwatch()..start();
    final timer = Stopwatch();
    for (final entry in _systems) {
      if (!entry.enabled) continue;
      final system = entry.system;
      timer
        ..reset()
        ..start();
      system.update(this, dt);
      commands.apply();
      profiler.recordSystem(system.name, timer.elapsedMicroseconds / 1000);
    }
    timer
      ..reset()
      ..start();
    events.flush();
    commands.apply();
    profiler.recordStep(
      stepMs: whole.elapsedMicroseconds / 1000,
      eventsMs: timer.elapsedMicroseconds / 1000,
      entities: entities.count,
    );
  }

  /// How many entities carry each registered component, by name -- a
  /// census of what the world is made of. Dart has no per-type allocation
  /// counter, so this is the practical stand-in for "where is my memory
  /// going": a runaway `particle` or `soundEvent` count shows up here long
  /// before it shows up as a frame spike. Zero-count components are omitted.
  Map<String, int> componentCounts() => {
    for (final r in components.all)
      if (r.store.length > 0) r.name: r.store.length,
  };

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
        '"entities" must be a list, got ${rawEntities.runtimeType}',
      );
    }
    for (var i = 0; i < rawEntities.length; i++) {
      final raw = rawEntities[i];
      if (raw is! Map) {
        throw WorldPatchException(
          'entities[$i] must be an object, got ${raw.runtimeType}',
        );
      }
      final e = raw.cast<String, dynamic>();
      final rawId = e['id'];
      if (rawId is! int) {
        throw WorldPatchException(
          'entities[$i].id must be an int, got ${rawId.runtimeType}',
        );
      }
      if (!entities.isAlive(rawId)) continue;
      final rawComponents = e['components'];
      if (rawComponents == null) continue;
      if (rawComponents is! Map) {
        throw WorldPatchException(
          'entities[$i].components must be an object, got '
          '${rawComponents.runtimeType}',
        );
      }
      components.applyToEntity(rawId, rawComponents.cast<String, dynamic>());
    }
  }

  /// Shuts down the job system and releases isolate resources.
  /// Call this when the world is no longer needed (e.g., scene change).
  void dispose() {
    _jobSystem?.shutdown();
    _jobSystem = null;
  }
}

class _SystemEntry {
  final System system;
  final SystemPhase phase;
  bool enabled = true;

  final List<String> after;

  _SystemEntry(this.system, this.phase, [this.after = const []]);
}

/// Coarse stages of one [World.step], run in this order.
///
/// Most systems belong in [physics], the default, and rely on insertion order
/// there. Use the others to say "before everything" ([prePhysics]: input,
/// AI decisions), "after the simulation settled" ([postPhysics]: damage
/// resolution, animation selection) or "last" ([late]: camera, HUD) without
/// having to register in exactly the right place.
enum SystemPhase { prePhysics, physics, postPhysics, late }
