import 'system.dart';
import 'world.dart';

/// Several systems added as one: `world.addSystem(SystemGroup('combat', [...]))`.
///
/// Children run in the order given. Queued [World.commands] are applied after
/// each child, exactly as they are between top-level systems, so a child
/// always sees what the previous one queued. The world sees one system named
/// [name] (that is what [World.systemOrder], [World.setSystemEnabled] and the
/// profiler use); the group's children stay reachable through [children].
class SystemGroup implements System {
  @override
  final String name;

  /// The member systems, in run order.
  final List<System> children;

  SystemGroup(this.name, Iterable<System> children)
    : children = List.unmodifiable(children);

  /// Names of the members, in run order.
  List<String> get childNames => [for (final c in children) c.name];

  @override
  void update(World world, double dt) {
    for (final child in children) {
      child.update(world, dt);
      world.commands.apply();
    }
  }
}
