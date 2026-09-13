import 'entity.dart';

/// Sparse-set storage for one component type: O(1) get/set/remove, and
/// dense iteration for systems that need to scan every instance of a
/// component. Simpler to get correct than an archetype table, and fast
/// enough for the entity counts this engine targets (thousands, not
/// millions) — revisit only if profiling says otherwise.
class ComponentStore<T> {
  final List<T> _dense = [];
  final List<EntityId> _denseToEntity = [];
  final Map<EntityId, int> _entityToDense = {};

  void set(EntityId entity, T value) {
    final existing = _entityToDense[entity];
    if (existing != null) {
      _dense[existing] = value;
      return;
    }
    _entityToDense[entity] = _dense.length;
    _dense.add(value);
    _denseToEntity.add(entity);
  }

  T? get(EntityId entity) {
    final idx = _entityToDense[entity];
    return idx == null ? null : _dense[idx];
  }

  bool has(EntityId entity) => _entityToDense.containsKey(entity);

  void remove(EntityId entity) {
    final idx = _entityToDense.remove(entity);
    if (idx == null) return;
    final lastIdx = _dense.length - 1;
    // Removing anything but the last dense slot needs the swap-in from
    // the end; removing the last slot directly (the common single-
    // element case) must NOT re-run it -- `lastEntity` would equal the
    // entity just removed, and re-inserting its `_entityToDense` entry
    // here left a dangling index once `removeLast()` below shrank past
    // it, corrupting the very next `set()` on a recycled id with that
    // entity number (caught by a benchmark exercising spawn/destroy
    // churn, RangeError inside `set`'s `_dense[existing] = value`).
    if (idx != lastIdx) {
      final lastEntity = _denseToEntity[lastIdx];
      _dense[idx] = _dense[lastIdx];
      _denseToEntity[idx] = lastEntity;
      _entityToDense[lastEntity] = idx;
    }
    _dense.removeLast();
    _denseToEntity.removeLast();
  }

  /// Dense iteration — cache-friendly, no gaps, safe to call in hot loops.
  int get length => _dense.length;
  T denseAt(int i) => _dense[i];
  EntityId entityAt(int i) => _denseToEntity[i];
}
