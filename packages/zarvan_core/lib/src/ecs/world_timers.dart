/// A scheduled callback; see [World.after] and [World.every].
class TimerHandle {
  final double _interval;
  final void Function() _callback;
  void Function(double dt)? _frame;
  double _remaining;
  bool _active = true;

  TimerHandle._(this._remaining, this._interval, this._callback);

  /// Whether it can still fire. A one-shot timer becomes inactive after it
  /// fires; a repeating one stays active until cancelled.
  bool get isActive => _active;

  /// Stops it. Safe from inside its own callback and more than once.
  void cancel() => _active = false;
}

/// Timers advanced by [World.step]'s `dt`, so they follow simulated time (and
/// therefore pause, slow down and replay with the world), never the clock.
///
/// Runtime-only: callbacks are closures and cannot be saved. For timers that
/// must survive save/load or a snapshot, use the `CountdownTimer` component.
class WorldTimers {
  List<TimerHandle> _timers = [];
  static const _epsilon = 1e-9;

  TimerHandle after(double seconds, void Function() callback) {
    if (seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be >= 0');
    }
    return _add(TimerHandle._(seconds, 0, callback));
  }

  TimerHandle every(double seconds, void Function() callback) {
    if (seconds <= 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be > 0');
    }
    return _add(TimerHandle._(seconds, seconds, callback));
  }

  TimerHandle frame(void Function(double dt) callback) {
    final t = TimerHandle._(0, 0, () {}).._frame = callback;
    return _add(t);
  }

  TimerHandle _add(TimerHandle timer) {
    _timers.add(timer);
    return timer;
  }

  bool get isEmpty => _timers.isEmpty;

  /// Moves time forward by [dt] and fires what came due, in registration order.
  /// A repeating timer fires once per elapsed interval, so a long [dt] does
  /// not lose beats. Timers created by a callback start counting next step.
  void advance(double dt) {
    final current = List<TimerHandle>.of(_timers);
    for (final timer in current) {
      if (!timer._active) continue;
      if (timer._frame != null) {
        timer._frame!(dt);
        continue;
      }
      timer._remaining -= dt;
      while (timer._active && timer._remaining <= _epsilon) {
        timer._callback();
        if (timer._interval == 0) {
          timer._active = false;
        } else {
          timer._remaining += timer._interval;
        }
      }
    }
    _timers.removeWhere((t) => !t._active);
  }
}
