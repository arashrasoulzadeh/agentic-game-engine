import 'world.dart';

/// One unit of simulation logic. Systems are small, composable, and run
/// in explicit registration order (World.systemOrder) — an agent can
/// inspect that order and add/replace a system without touching others.
abstract class System {
  String get name;
  void update(World world, double dt);
}

/// Marks a [System] that runs on real frame time even while the world is
/// slowed, paused or in hit-stop (`World.timeScale`, `World.hitStop`): a UI
/// animation, a camera, an input reader. Add it with `implements` or `with`;
/// an ordinary system follows the world's clock.
abstract interface class RealTimeSystem {}
