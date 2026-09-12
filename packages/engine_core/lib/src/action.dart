import 'world.dart';

/// What a `Behavior` wants to happen this tick. `AISystem` calls
/// [apply] against the real, mutable `World` after a behavior returns
/// one — behaviors themselves only ever see a read-only `WorldView`, so
/// this is the sole path from agent decision to actual state change.
/// Games define their own `Action` subclasses for domain logic (e.g. a
/// `TakeDamage` action) — the engine only ships the generic ones below.
abstract class Action {
  void apply(World world);
}

/// Does nothing. The default/fallback action for a behavior with
/// nothing to do this tick.
class NoOpAction implements Action {
  const NoOpAction();

  @override
  void apply(World world) {}
}
