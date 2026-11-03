import 'entity.dart';
import 'world.dart';

/// A reference to one *incarnation* of an entity: its id plus the generation
/// it had when the handle was made.
///
/// A plain [EntityId] is recycled, so a stored id can end up naming an
/// unrelated entity. An [Entity] never does: once the original is destroyed,
/// `World.isCurrent` is false for it even if a new entity reuses the id. It
/// is a single integer at runtime (no allocation), so keep it in fields and
/// lists freely. Do not put it in component JSON: serialize [id] instead.
///
/// The value is `generation * 2^32 + id`, using arithmetic rather than shifts
/// so it stays exact in a web build's 53-bit integers (ids must stay below
/// 2^32 and generations below 2^21).
extension type Entity._(int _packed) {
  static const int _span = 4294967296;

  /// The handle for [id] at [generation].
  Entity.from(EntityId id, int generation)
    : assert(id >= 0 && id < _span, 'entity id out of range: $id'),
      assert(
        generation >= 0 && generation < 2097152,
        'entity generation out of range: $generation',
      ),
      _packed = generation * _span + id;

  /// The id slot this handle refers to (what component collections use).
  EntityId get id => _packed % _span;

  /// How many times the slot had been destroyed when this was made.
  int get generation => _packed ~/ _span;
}

/// A handle bound to a [World] for call chains: `world.ref(e).set(...)`.
///
/// Every operation re-checks that the entity is still the same incarnation, so
/// a stale reference reads as empty and refuses writes instead of touching
/// whichever entity reused the id.
class EntityRef {
  final World world;
  final Entity entity;

  EntityRef(this.world, this.entity);

  /// The id slot, for APIs that take a raw [EntityId].
  EntityId get id => entity.id;

  /// Whether this exact entity still exists.
  bool get isAlive => world.isCurrent(entity);

  /// Its [T], or null when it has none or is gone.
  T? get<T>() => isAlive ? world.getComponent<T>(id) : null;

  /// Whether it currently has a [T].
  bool has<T>() => isAlive && world.hasComponent<T>(id);

  /// Attaches [value] as its [T] and returns this for chaining.
  ///
  /// Throws [StateError] if the entity is gone (see [World.setComponent]).
  EntityRef set<T>(T value) {
    if (!isAlive) {
      throw StateError(
        'Cannot set $T: entity $id is no longer the entity this reference '
        'was made for (destroyed, and possibly reused).',
      );
    }
    world.setComponent(id, value);
    return this;
  }

  /// Detaches its [T] (a no-op if absent or gone) and returns this.
  EntityRef remove<T>() {
    if (isAlive) world.removeComponent<T>(id);
    return this;
  }

  /// Destroys the entity; a no-op if it is already gone.
  void destroy() {
    if (isAlive) world.destroy(id);
  }

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.world == world && other.entity == entity;

  @override
  int get hashCode => Object.hash(world, entity);
}

/// Handle access on [World].
extension EntityHandles on World {
  /// The handle for the live entity [id].
  ///
  /// Throws [StateError] if [id] is not alive: a handle made from a dead id
  /// would silently describe the next entity to reuse it.
  Entity entityOf(EntityId id) {
    if (!entities.isAlive(id)) {
      throw StateError('Cannot make a handle for entity $id: it is not alive.');
    }
    return Entity.from(id, generationOf(id));
  }

  /// Whether [entity] is alive and still the same incarnation.
  bool isCurrent(Entity entity) =>
      entities.isCurrent(entity.id, entity.generation);

  /// A world-bound view of [entity] for fluent use.
  EntityRef ref(Entity entity) => EntityRef(this, entity);
}
