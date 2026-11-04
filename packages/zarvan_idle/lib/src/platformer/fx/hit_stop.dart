import 'package:zarvan_core/zarvan_core.dart';

/// Freezes the fight for a moment so a heavy blow lands visibly: a thin
/// wrapper over the engine's `World.hitStop`, which freezes every system and
/// timer that follows the world's clock for that many *real* seconds.
class HitStop {
  HitStop(this.world);

  final World world;

  bool get frozen => world.isHitStopped;

  void freeze(double seconds) {
    if (seconds > 0) world.hitStop(seconds);
  }

  /// Kept for callers that tick it with the frame time; the world counts the
  /// freeze down itself.
  void update(double realDt) {}
}
