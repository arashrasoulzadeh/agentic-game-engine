/// An entity is just an integer id — all behavior/data lives in components.
typedef EntityId = int;

/// Allocates and recycles entity ids so long-running worlds with heavy
/// spawn/despawn churn (bullets, particles) don't grow ids unboundedly.
class EntityManager {
  int _next = 0;
  final List<EntityId> _free = [];
  final Set<EntityId> _alive = {};
  final List<int> _generation = [];

  /// How many times [id] has been destroyed (0 for an id never used).
  ///
  /// Ids are recycled, so an id alone cannot tell "the enemy I stored last
  /// frame" from "a bullet that reused its slot". A holder that remembers
  /// `(id, generationOf(id))` can later ask [isCurrent]. Runtime-only: not
  /// serialized, so JSON and snapshots still carry plain ids.
  int generationOf(EntityId id) =>
      id < _generation.length ? _generation[id] : 0;

  /// Whether [id] is alive *and* still the same incarnation as when
  /// [generation] was read from [generationOf].
  bool isCurrent(EntityId id, int generation) =>
      _alive.contains(id) && generationOf(id) == generation;

  EntityId create() {
    final id = _free.isNotEmpty ? _free.removeLast() : _next++;
    _alive.add(id);
    _growGenerations(id);
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
    _growGenerations(id);
  }

  void _growGenerations(EntityId id) {
    while (_generation.length <= id) {
      _generation.add(0);
    }
  }

  void destroy(EntityId id) {
    if (_alive.remove(id)) {
      _free.add(id);
      _generation[id]++;
    }
  }

  bool isAlive(EntityId id) => _alive.contains(id);

  Iterable<EntityId> get all => _alive;

  int get count => _alive.length;
}
