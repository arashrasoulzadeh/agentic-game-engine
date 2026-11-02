import '../rendering/tween.dart';
import 'world.dart';
import 'world_timers.dart';

/// One step of a [WorldMotion.sequence]: wait, or run something.
class SeqStep {
  final double _wait;
  final void Function()? _action;

  /// Pauses the sequence for [seconds] of simulated time.
  const SeqStep.wait(double seconds) : _wait = seconds, _action = null;

  /// Runs [action] immediately when the sequence reaches it.
  const SeqStep.run(void Function() action) : _wait = 0, _action = action;
}

/// Closure-driven animation and scripting on [World], for juice and cutscenes
/// that don't need to survive a save (for a saved value, use the serializable
/// `Tween` component; for a saved timer, `CountdownTimer`).
extension WorldMotion on World {
  /// Animates a value from [from] to [to] over [duration] simulated seconds,
  /// calling [onUpdate] every step with the eased value (the last call is
  /// exactly [to]) and then [onDone] once. Cancel the handle to stop early.
  ///
  /// ```dart
  /// world.tween(0, 100, 0.3, (v) => pos.x = v, easing: EasingType.easeOutQuad);
  /// ```
  TimerHandle tween(
    double from,
    double to,
    double duration,
    void Function(double value) onUpdate, {
    EasingType easing = EasingType.linear,
    void Function()? onDone,
  }) {
    if (duration < 0) {
      throw ArgumentError.value(duration, 'duration', 'must be >= 0');
    }
    var elapsed = 0.0;
    late final TimerHandle handle;
    handle = onStep((dt) {
      elapsed += dt;
      final t = duration <= 0 ? 1.0 : (elapsed / duration).clamp(0.0, 1.0);
      onUpdate(t >= 1 ? to : from + (to - from) * easing.apply(t));
      if (t >= 1) {
        handle.cancel();
        onDone?.call();
      }
    });
    return handle;
  }

  /// Runs [steps] in order: waits advance simulated time, actions run in the
  /// step they come due. Cancel the returned handle to stop the rest.
  ///
  /// ```dart
  /// world.sequence([
  ///   SeqStep.wait(1),
  ///   SeqStep.run(() => world.spawnAt(10, 10)),
  ///   SeqStep.wait(2),
  ///   SeqStep.run(() => print('done')),
  /// ]);
  /// ```
  TimerHandle sequence(List<SeqStep> steps) {
    var index = 0;
    var remaining = 0.0;
    late final TimerHandle handle;
    handle = onStep((dt) {
      remaining -= dt;
      while (handle.isActive && remaining <= 1e-9 && index < steps.length) {
        final step = steps[index++];
        final action = step._action;
        if (action != null) {
          action();
        } else {
          remaining += step._wait;
        }
      }
      if (index >= steps.length && remaining <= 1e-9) handle.cancel();
    });
    return handle;
  }
}
