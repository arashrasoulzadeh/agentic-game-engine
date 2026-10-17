/// An entity is just an integer id — all behavior/data lives in components.
typedef EntityId = int;

/// Allocates and recycles entity ids so long-running worlds with heavy
/// spawn/despawn churn (bullets, particles) don't grow ids unboundedly.
class EntityManager {
  int _next = 0;
  final List<EntityId> _free = [];
  final Set<EntityId> _alive = {};

  EntityId create() {
    final id = _free.isNotEmpty ? _free.removeLast() : _next++;
    _alive.add(id);
    return id;
  }

  /// Makes [id] alive, whatever it was: used to rebuild a world from a network
  /// snapshot, where ids are dictated by the sender rather than handed out.
  /// Ids skipped over to reach [id] stay available to `create()`.
  void ensureAlive(EntityId id) {
    if (_alive.contains(id)) return;
    _free.remove(id);
    while (_next < id) {
      _free.add(_next++);
    }
    if (id >= _next) _next = id + 1;
    _alive.add(id);
  }

  void destroy(EntityId id) {
    if (_alive.remove(id)) {
      _free.add(id);
    }
  }

  bool isAlive(EntityId id) => _alive.contains(id);

  Iterable<EntityId> get all => _alive;

  int get count => _alive.length;
}
