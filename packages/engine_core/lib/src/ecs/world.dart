import 'component_registry.dart';
import 'component_store.dart';
import 'entity.dart';
import 'dev_warnings.dart';
import 'engine_error.dart';
import 'event_bus.dart';
import 'hierarchy.dart' show destroyChildrenOf;
import 'system.dart';
import 'archetype.dart';
import 'job_system.dart';
import 'world_profiler.dart';
import 'world_commands.dart';
import 'world_random.dart';
import 'world_timers.dart';

/// Thrown by [World.applyPatch] when the patch's own shape is wrong —
/// `entities` not a list, an entry not an object, a missing/malformed
/// `id`. Mirrors `Level.validate`'s `LevelLoadException`: a specific,
/// human/agent-readable path to the bad field rather than a bare
/// `TypeError` from a failed cast. Per-component problems (a bad
/// `fromJson`) throw `ComponentApplyException` instead, from
/// `ComponentRegistry.applyToEntity`.
/// One thing wrong with a patch, found by [World.checkPatch].
typedef PatchProblem = ErrorProblem;

class WorldPatchException implements EngineError {
  @override
  final String message;

  /// Every located problem when the patch was rejected as a whole (strict
  /// mode); empty for a single structural fault described by [message].
  final List<ErrorProblem> problems;

  WorldPatchException(this.message, {this.problems = const []});

  @override
  String get code => 'patch_invalid';

  @override
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (problems.isNotEmpty) 'problems': [for (final p in problems) p.toJson()],
  };

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

  /// Debug-time warnings about legal-but-suspicious calls (see [DevWarnings]).
  final DevWarnings warnings = DevWarnings();
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
    : random = WorldRandom(seed) {
    components.warnings = warnings;
  }

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
    if (_systems.any((e) => e.system.name == system.name)) {
      warnings.warn(
        'Two systems are named "${system.name}"; setSystemEnabled and the '
        'profiler treat them as one.',
      );
    }
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

  /// Calls [callback] with the simulated `dt` at the start of every step until
  /// cancelled. The primitive under [WorldMotion.tween]; runtime-only.
  TimerHandle onStep(void Function(double dt) callback) =>
      (_timers ??= WorldTimers()).frame(callback);

  /// Subscribes [handler] to events of exactly type [E]; shorthand for
  /// `events.on<E>`. Cancel the returned subscription to stop listening.
  Subscription on<E>(void Function(E event) handler) => events.on<E>(handler);

  /// Like [on] but unsubscribes itself after the first event.
  Subscription once<E>(void Function(E event) handler) =>
      events.once<E>(handler);

  /// Sets every component in [values] on [entity] in one call, each stored
  /// under its runtime type. All-or-nothing: a dead entity or an unregistered
  /// type throws before anything is written.
  void setComponents(EntityId entity, Iterable<Object> values) {
    if (!entities.isAlive(entity)) {
      throw StateError('Cannot set components on entity $entity: not alive.');
    }
    final list = values.toList();
    final seen = <Type>{};
    for (final v in list) {
      if (components.getRegistration(v.runtimeType) == null) {
        throw ArgumentError.value(
          v,
          'values',
          'Component type ${v.runtimeType} is not registered.',
        );
      }
      if (!seen.add(v.runtimeType)) {
        throw ArgumentError.value(
          v,
          'values',
          'Component type ${v.runtimeType} appears more than once.',
        );
      }
    }
    for (final v in list) {
      components.getRegistration(v.runtimeType)!.store.set(entity, v);
    }
  }

  /// Records a warning for every event that is flushed with no handler for its
  /// exact type (handlers match the runtime type, so a handler for a base class
  /// does not count). Off by default because unhandled events are often fine.
  set warnOnUnhandledEvents(bool on) => events.onUnhandled = on
      ? (event) => warnings.warn(
          'Event ${event.runtimeType} was emitted but nothing handles that exact type.',
        )
      : null;

  WorldTimers? _timers;

  /// Calls [callback] once, after [seconds] of simulated time (the `dt` given
  /// to [step]), on the step it comes due; 0 means the next step. Runtime-only:
  /// closures are not saved or snapshotted (see `CountdownTimer` for that).
  TimerHandle after(double seconds, void Function() callback) =>
      (_timers ??= WorldTimers()).after(seconds, callback);

  /// Calls [callback] every [seconds] of simulated time until cancelled; a
  /// long step fires it once per elapsed interval. Runtime-only like [after].
  TimerHandle every(double seconds, void Function() callback) =>
      (_timers ??= WorldTimers()).every(seconds, callback);

  EntityId spawn() => entities.create();

  /// Incarnation counter of [id]; see [EntityManager.generationOf].
  int generationOf(EntityId id) => entities.generationOf(id);

  /// Destroys [id] and removes all of its components. Entities parented to it
  /// (see [Parent]) are destroyed too, recursively, so attachments never
  /// outlive what they were attached to.
  void destroy(EntityId id) {
    final children = destroyChildrenOf(this, id);
    for (final child in children) {
      destroy(child);
    }
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
    _timers?.advance(dt);
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
  /// A short human-readable summary of the world for logs and bug reports:
  /// tick, seed, entity and component counts, the system order (disabled
  /// systems marked) and any [validateSystemOrder] problems.
  ///
  /// Meant to be read, not parsed; use [toJson] or `save` for data.
  String debug() {
    final counts = componentCounts();
    final components = counts.keys.toList()..sort();
    final systems = [
      for (final e in _systems)
        '${e.system.name}${e.enabled ? '' : ' (disabled)'}',
    ];
    final problems = validateSystemOrder();
    final out = StringBuffer()
      ..writeln(
        'World ${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)}'
        ' tick=$_tick seed=$seed entities=${entities.count}',
      )
      ..writeln(
        'components: ${components.isEmpty ? '(none)' : [for (final c in components) '$c=${counts[c]}'].join(', ')}',
      )
      ..writeln(
        'systems: ${systems.isEmpty ? '(none)' : systems.join(' -> ')}',
      );
    if (!commands.isEmpty) out.writeln('queued commands: ${commands.length}');
    for (final problem in problems) {
      out.writeln('order problem: $problem');
    }
    final warned = warnings.messages;
    if (warned.isNotEmpty) {
      out.writeln('warnings (${warned.length}), latest: ${warned.last}');
    }
    return out.toString().trimRight();
  }

  /// [debug] as data: the same facts, for tools and agents that should not parse
  /// prose. `components` maps each in-use component to its entity `count` and, when
  /// a schema is registered, its `fields` (name, type, required), so one call tells
  /// an agent what exists and how to write it.
  Map<String, dynamic> describe() {
    final counts = componentCounts();
    return {
      'tick': _tick,
      'seed': seed,
      'width': width,
      'height': height,
      'entities': entities.count,
      'components': {
        for (final name in (counts.keys.toList()..sort()))
          name: {
            'count': counts[name],
            if (components.schemaFor(name) case final schema?)
              'fields': [
                for (final f in schema.fields)
                  {'name': f.name, 'type': f.type.name, 'required': f.required},
              ],
          },
      },
      'systems': [
        for (final e in _systems) {'name': e.system.name, 'enabled': e.enabled},
      ],
      'queuedCommands': commands.length,
      'orderProblems': validateSystemOrder(),
      'warnings': List<String>.of(warnings.messages),
    };
  }

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

  /// Everything wrong with [patch], without applying any of it; empty means
  /// `applyPatch(patch, strict: true)` would succeed.
  ///
  /// Reports a missing or malformed `entities` list, ids that are not ints or
  /// not alive (the lenient apply skips these silently), `components` that are
  /// not an object, unknown component names, and component data its own
  /// `fromJson` rejects.
  List<PatchProblem> checkPatch(Map<String, dynamic> patch) {
    final problems = <PatchProblem>[];
    final rawEntities = patch['entities'];
    if (rawEntities == null) {
      return [
        const PatchProblem(
          'entities',
          'missing: a patch needs an '
              '"entities" list',
        ),
      ];
    }
    if (rawEntities is! List) {
      return [
        PatchProblem(
          'entities',
          'must be a list, got ${rawEntities.runtimeType}',
        ),
      ];
    }
    for (var i = 0; i < rawEntities.length; i++) {
      final at = 'entities[$i]';
      final raw = rawEntities[i];
      if (raw is! Map) {
        problems.add(
          PatchProblem(at, 'must be an object, got ${raw.runtimeType}'),
        );
        continue;
      }
      final id = raw['id'];
      if (id is! int) {
        problems.add(
          PatchProblem('$at.id', 'must be an int, got ${id.runtimeType}'),
        );
        continue;
      }
      if (!entities.isAlive(id)) {
        problems.add(
          PatchProblem(
            '$at.id',
            'entity $id is not alive (a lenient apply would skip it)',
          ),
        );
        continue;
      }
      final comps = raw['components'];
      if (comps == null) continue;
      if (comps is! Map) {
        problems.add(
          PatchProblem(
            '$at.components',
            'must be an object, got ${comps.runtimeType}',
          ),
        );
        continue;
      }
      for (final entry in comps.entries) {
        final reason = components.checkComponent('${entry.key}', entry.value);
        if (reason != null) {
          problems.add(PatchProblem('$at.components.${entry.key}', reason));
        }
      }
    }
    return problems;
  }

  /// Applies a snapshot produced by [toJson] (or a partial patch with a
  /// subset of entities/components) — the agent-facing write path.
  /// Throws [WorldPatchException] on a malformed patch shape, or
  /// [ComponentApplyException] if a named component's own JSON is bad
  /// — never a bare, contextless `TypeError`.
  ///
  /// Lenient by default: entities that are not alive are skipped and unknown
  /// component names ignored, so a forward-compatible patch still lands. Pass
  /// `strict: true` to instead throw a [WorldPatchException] listing every
  /// problem (see [checkPatch]) before anything is changed.
  void applyPatch(Map<String, dynamic> patch, {bool strict = false}) {
    if (strict) {
      final problems = checkPatch(patch);
      if (problems.isNotEmpty) {
        throw WorldPatchException(
          '${problems.length} problem${problems.length == 1 ? '' : 's'} in '
          'patch, nothing applied:\n${problems.join('\n')}',
          problems: problems,
        );
      }
    }
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

  /// Shuts down the job system and drops everything that could keep the world
  /// alive or act on it later: event handlers, systems, timers and queued
  /// commands. Entities and components are left readable so a final save or
  /// debug dump still works. Call this when the world is no longer needed
  /// (e.g., scene change); safe to call more than once.
  void dispose() {
    _jobSystem?.shutdown();
    _jobSystem = null;
    events.clearHandlers();
    _systems.clear();
    _timers = null;
    commands.clear();
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
