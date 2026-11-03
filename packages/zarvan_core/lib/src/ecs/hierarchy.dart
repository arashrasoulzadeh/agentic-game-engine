import '../physics/position.dart';
import 'entity.dart';
import 'world.dart';

/// Marks an entity as attached to [entity] (its parent): a weapon in a hand, a
/// shadow under a unit, an emitter on a ship.
///
/// A real registered component, so the link saves, loads and patches like any
/// other. Two rules come with it: destroying the parent destroys the child
/// (see [World.destroy]), and a child's [Position] is **relative to its
/// parent**; use [WorldHierarchy.worldPositionOf] for the absolute point.
/// Rotation and scale are not inherited (this engine's `Position` has none).
class Parent {
  /// The parent's entity id.
  final EntityId entity;

  Parent(this.entity);

  Map<String, dynamic> toJson() => {'entity': entity};

  factory Parent.fromJson(Map<String, dynamic> json) =>
      Parent(json['entity'] as int);
}

/// Direct children of [id], or an empty list when [Parent] is not registered
/// or nothing is attached. Internal: used by [World.destroy].
List<EntityId> destroyChildrenOf(World world, EntityId id) {
  if (world.components.getRegistration(Parent) == null) return const [];
  final parents = world.componentsOf<Parent>();
  if (parents.length == 0) return const [];
  return [
    for (var i = 0; i < parents.length; i++)
      if (parents.denseAt(i).entity == id) parents.entityAt(i),
  ];
}

/// Parent/child helpers on [World].
extension WorldHierarchy on World {
  /// Attaches [child] to [parent]. Rejects dead entities, self-parenting and
  /// cycles (a parent that is already a descendant of [child]).
  void addChild(EntityId parent, EntityId child) {
    if (!entities.isAlive(parent) || !entities.isAlive(child)) {
      throw StateError('addChild($parent, $child): both must be alive.');
    }
    if (parent == child) {
      throw ArgumentError('An entity cannot be its own parent ($parent).');
    }
    for (var up = parentOf(parent); up != null; up = parentOf(up)) {
      if (up == child) {
        throw ArgumentError(
          'addChild($parent, $child) would create a cycle: $child is already '
          'an ancestor of $parent.',
        );
      }
    }
    setComponent(child, Parent(parent));
  }

  /// Detaches [child] from its parent; the child keeps its relative position
  /// as its new absolute one unless you convert it first.
  void detach(EntityId child) => removeComponent<Parent>(child);

  /// [child]'s parent, or null.
  EntityId? parentOf(EntityId child) => getComponent<Parent>(child)?.entity;

  /// Direct children of [parent], in storage order.
  List<EntityId> childrenOf(EntityId parent) => destroyChildrenOf(this, parent);

  /// Absolute position of [id]: its [Position] plus every ancestor's. Null
  /// when [id] has no [Position]; an ancestor without one counts as (0, 0).
  ({double x, double y})? worldPositionOf(EntityId id) {
    final own = getComponent<Position>(id);
    if (own == null) return null;
    var x = own.x, y = own.y;
    for (var up = parentOf(id); up != null; up = parentOf(up)) {
      final p = getComponent<Position>(up);
      if (p != null) {
        x += p.x;
        y += p.y;
      }
    }
    return (x: x, y: y);
  }
}
