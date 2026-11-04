import 'component_registry.dart';
import 'entity.dart';
import 'world.dart';

/// Recycles the component objects of short-lived entities (bullets, sparks,
/// floating numbers) so a busy scene stops allocating them every frame.
///
/// [release] strips an entity's components into a stash and destroys it;
/// [acquire] spawns a fresh entity and puts a stashed bundle back on it. The
/// recycled components still hold their old values, so the caller must set
/// every field it relies on; that is the price of not allocating, and why
/// `acquire` says whether it recycled.
class EntityPool {
  EntityPool(this.world, {this.maxIdle = 256});

  final World world;

  /// Bundles kept; releases beyond this are destroyed normally.
  final int maxIdle;

  final List<List<(ComponentRegistration, Object)>> _idle = [];

  int _created = 0;
  int _recycled = 0;

  /// Bundles waiting to be reused.
  int get idle => _idle.length;

  /// Entities this pool has handed out fresh, and ones it reused.
  int get created => _created;
  int get recycled => _recycled;

  /// An entity ready to use. [PooledEntity.recycled] is true when it carries
  /// the components of a released one (stale values); false when it is brand
  /// new and empty, so the caller builds it as usual.
  PooledEntity acquire() {
    final entity = world.spawn();
    if (_idle.isEmpty) {
      _created++;
      return PooledEntity(entity, false);
    }
    for (final (reg, component) in _idle.removeLast()) {
      reg.attach(entity, component);
    }
    _recycled++;
    return PooledEntity(entity, true);
  }

  /// Returns [entity] to the pool: its components are kept for reuse and the
  /// entity itself is destroyed. The id is a plain int and may be handed out
  /// again by the next spawn, so drop every reference to it (use the
  /// generation-checked `Entity` handle if something must notice).
  void release(EntityId entity) {
    if (!world.entities.isAlive(entity)) return;
    final bundle = <(ComponentRegistration, Object)>[];
    for (final reg in world.components.all) {
      final component = reg.detach(entity);
      if (component != null) bundle.add((reg, component));
    }
    world.destroy(entity);
    if (_idle.length < maxIdle && bundle.isNotEmpty) _idle.add(bundle);
  }

  /// Drops every stashed bundle.
  void clear() => _idle.clear();
}

/// What [EntityPool.acquire] returns.
class PooledEntity {
  const PooledEntity(this.id, this.recycled);

  final EntityId id;

  /// Whether [id] already carries components from an earlier use.
  final bool recycled;
}
