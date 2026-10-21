import 'dart:convert';

import '../ecs/entity.dart';
import '../ecs/world.dart';

/// A world frozen at one tick: every entity's components as plain JSON, keyed by
/// entity id. The unit of rollback and network sync.
///
/// Built on `World.toJson`'s component serialization, so it carries exactly
/// what `registerCoreComponents` & friends register -- an unregistered
/// component is not in a snapshot, which is the same rule as saving and
/// patching. Snapshots are value objects: [capture] deep-copies through JSON,
/// so later changes to the world never alter one.
class WorldSnapshot {
  final int tick;
  final Map<EntityId, Map<String, dynamic>> entities;

  WorldSnapshot(this.tick, Map<EntityId, Map<String, dynamic>> entities)
    : entities = Map.unmodifiable(entities);

  factory WorldSnapshot.capture(World world) {
    return WorldSnapshot(world.tick, {
      for (final id in world.entities.all)
        id: _copy(world.components.serializeEntity(id)),
    });
  }

  /// Rebuilds [world] to match this snapshot exactly: entities not in it are
  /// destroyed, missing ones are created *with their original ids*, and any
  /// entity whose components differ is recreated from the snapshot. Entities
  /// already identical are left alone, so a rollback of a mostly-unchanged
  /// world touches only what moved.
  void restoreInto(World world) {
    for (final id in world.entities.all.toList()) {
      if (!entities.containsKey(id)) world.destroy(id);
    }
    for (final entry in entities.entries) {
      final id = entry.key;
      if (world.entities.isAlive(id) &&
          _same(world.components.serializeEntity(id), entry.value)) {
        continue;
      }
      if (world.entities.isAlive(id)) world.destroy(id);
      world.entities.ensureAlive(id);
      world.components.applyToEntity(id, _copy(entry.value));
    }
    world.setTick(tick);
  }

  Map<String, dynamic> toJson() => {
    'tick': tick,
    'entities': {for (final e in entities.entries) '${e.key}': e.value},
  };

  factory WorldSnapshot.fromJson(Map<String, dynamic> json) =>
      WorldSnapshot((json['tick'] as num).toInt(), {
        for (final e in (json['entities'] as Map).entries)
          int.parse(e.key as String): _copy(
            (e.value as Map).cast<String, dynamic>(),
          ),
      });

  static Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

  static bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(_sorted(a)) == jsonEncode(_sorted(b));

  static Object? _sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(v[k])};
    }
    if (v is List) return v.map(_sorted).toList();
    return v;
  }
}

/// The difference between two snapshots, at entity granularity: the full
/// component set of every entity that changed or appeared, plus the ids that
/// vanished. Whole-entity (not per-component) deltas keep the format and the
/// apply step trivial, and a changed entity is usually small.
class WorldDelta {
  /// The snapshot tick this delta is relative to. A receiver that does not hold
  /// that exact baseline must ask for a full snapshot instead.
  final int baseTick;
  final int tick;
  final Map<EntityId, Map<String, dynamic>> changed;
  final List<EntityId> removed;

  WorldDelta({
    required this.baseTick,
    required this.tick,
    required this.changed,
    required this.removed,
  });

  factory WorldDelta.between(WorldSnapshot from, WorldSnapshot to) {
    final changed = <EntityId, Map<String, dynamic>>{};
    for (final e in to.entities.entries) {
      final before = from.entities[e.key];
      if (before == null || !WorldSnapshot._same(before, e.value)) {
        changed[e.key] = e.value;
      }
    }
    return WorldDelta(
      baseTick: from.tick,
      tick: to.tick,
      changed: changed,
      removed: [
        for (final id in from.entities.keys)
          if (!to.entities.containsKey(id)) id,
      ]..sort(),
    );
  }

  bool get isEmpty => changed.isEmpty && removed.isEmpty;

  /// The snapshot this delta leads to from [base]. Throws if [base] is not the
  /// baseline the delta was made against.
  WorldSnapshot applyTo(WorldSnapshot base) {
    if (base.tick != baseTick) {
      throw StateError(
        'delta is relative to tick $baseTick, got a base at tick ${base.tick}',
      );
    }
    final next = {...base.entities, ...changed};
    for (final id in removed) {
      next.remove(id);
    }
    return WorldSnapshot(tick, next);
  }

  Map<String, dynamic> toJson() => {
    'baseTick': baseTick,
    'tick': tick,
    'changed': {for (final e in changed.entries) '${e.key}': e.value},
    'removed': removed,
  };

  factory WorldDelta.fromJson(Map<String, dynamic> json) => WorldDelta(
    baseTick: (json['baseTick'] as num).toInt(),
    tick: (json['tick'] as num).toInt(),
    changed: {
      for (final e in (json['changed'] as Map).entries)
        int.parse(e.key as String): WorldSnapshot._copy(
          (e.value as Map).cast<String, dynamic>(),
        ),
    },
    removed: [for (final id in (json['removed'] as List)) (id as num).toInt()],
  );
}
