import 'world.dart';

/// One unit of simulation logic. Systems are small, composable, and run
/// in explicit registration order (World.systemOrder) — an agent can
/// inspect that order and add/replace a system without touching others.
abstract class System {
  String get name;
  void update(World world, double dt);
}
