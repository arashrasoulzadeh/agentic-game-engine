import 'entity.dart';

/// Sparse-set storage for one component type: O(1) get/set/remove, and
/// dense iteration for systems that need to scan every instance of a
/// component. Simpler to get correct than an archetype table, and fast
/// enough for the entity counts this engine targets (thousands, not
/// millions) — revisit only if profiling says otherwise.
///
/// The sparse side is a `List<int>` indexed directly by entity id
/// (`-1` = absent), not a `Map<EntityId, int>` — `EntityId` is a small,
/// densely-recycled int (see `EntityManager`), so every `get`/`set`/
/// `has`/`remove` (the hottest path in the engine: every component
/// touch, every tick) skips hashing entirely. Grows on demand as ids
/// increase and never shrinks, the standard sparse-set tradeoff at the
/// entity counts this engine targets.
class ComponentStore<T> {
  final List<T> _dense = [];
  final List<EntityId> _denseToEntity = [];
  final List<int> _sparse = [];

  void _growSparse(int minLength) {
    while (_sparse.length < minLength) {
      _sparse.add(-1);
    }
  }

  void set(EntityId entity, T value) {
    _growSparse(entity + 1);
    final existing = _sparse[entity];
    if (existing != -1) {
      _dense[existing] = value;
      return;
    }
    _sparse[entity] = _dense.length;
    _dense.add(value);
    _denseToEntity.add(entity);
  }

  T? get(EntityId entity) {
    if (entity >= _sparse.length) return null;
    final idx = _sparse[entity];
    return idx == -1 ? null : _dense[idx];
  }

  bool has(EntityId entity) => entity < _sparse.length && _sparse[entity] != -1;

  void remove(EntityId entity) {
    if (entity >= _sparse.length) return;
    final idx = _sparse[entity];
    if (idx == -1) return;
    _sparse[entity] = -1;

    final lastIdx = _dense.length - 1;
    // Removing anything but the last dense slot needs the swap-in from
    // the end; removing the last slot directly (the common single-
    // element case) must NOT re-run it -- `lastEntity` would equal the
    // entity just removed, and re-inserting its sparse entry here would
    // leave a dangling index once `removeLast()` below shrank past it,
    // corrupting the very next `set()` on a recycled id with that
    // entity number (this exact bug existed in the Map-based version —
    // caught by a benchmark exercising spawn/destroy churn, RangeError
    // inside `set`'s `_dense[existing] = value`).
    if (idx != lastIdx) {
      final lastEntity = _denseToEntity[lastIdx];
      _dense[idx] = _dense[lastIdx];
      _denseToEntity[idx] = lastEntity;
      _sparse[lastEntity] = idx;
    }
    _dense.removeLast();
    _denseToEntity.removeLast();
  }

  /// Dense iteration — cache-friendly, no gaps, safe to call in hot loops.
  int get length => _dense.length;
  T denseAt(int i) => _dense[i];
  EntityId entityAt(int i) => _denseToEntity[i];
}
