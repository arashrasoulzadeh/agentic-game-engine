import 'tween.dart';
import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';

/// Emitted the tick a (non-looping, non-ping-pong) `Tween` first
/// reaches its end — exactly once, the same "fires once, not every
/// tick past completion" guarantee `DeathEvent` gives for `Health`.
class TweenCompleteEvent {
  final EntityId entity;
  TweenCompleteEvent(this.entity);
}

/// Advances every `Tween`'s `elapsed` by `dt`. A looping tween wraps
/// back to 0; a ping-pong tween flips `reversed` at each end instead;
/// a plain one clamps at `duration` and fires `TweenCompleteEvent`
/// once. Doesn't touch any other component — see `Tween`'s doc comment
/// for why applying `.value` to something is left to the game.
class TweenSystem implements System {
  @override
  String get name => 'tween';

  @override
  void update(World world, double dt) {
    final tweens = world.storeOf<Tween>();
    for (var i = 0; i < tweens.length; i++) {
      final tween = tweens.denseAt(i);
      if (tween.isComplete) continue; // already fired its completion event

      tween.elapsed += dt;
      if (tween.duration <= 0) continue;

      if (tween.pingPong) {
        if (tween.elapsed >= tween.duration) {
          tween.elapsed -= tween.duration;
          tween.reversed = !tween.reversed;
        }
      } else if (tween.loop) {
        if (tween.elapsed >= tween.duration) {
          tween.elapsed %= tween.duration;
        }
      } else if (tween.elapsed >= tween.duration) {
        tween.elapsed = tween.duration;
        world.events.emit(TweenCompleteEvent(tweens.entityAt(i)));
      }
    }
  }
}
