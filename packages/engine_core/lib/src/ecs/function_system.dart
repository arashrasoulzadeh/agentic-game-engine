import 'system.dart';
import 'world.dart';

/// A [System] made from a function, for logic too small to deserve a class.
class FunctionSystem implements System {
  @override
  final String name;

  final void Function(World world, double dt) _update;

  FunctionSystem(this.name, this._update);

  @override
  void update(World world, double dt) => _update(world, dt);
}

/// Adding function systems straight to a [World].
extension FunctionSystems on World {
  /// Registers [update] as a system named [name] (see [World.addSystem] for
  /// [phase] and [after]) and returns it.
  ///
  /// ```dart
  /// world.addSystemFn('spin', (world, dt) {
  ///   for (final (_, r) in world.query<Rotation>()) {
  ///     r.angle += dt;
  ///   }
  /// });
  /// ```
  System addSystemFn(
    String name,
    void Function(World world, double dt) update, {
    SystemPhase phase = SystemPhase.physics,
    List<String> after = const [],
  }) {
    final system = FunctionSystem(name, update);
    addSystem(system, phase: phase, after: after);
    return system;
  }
}
