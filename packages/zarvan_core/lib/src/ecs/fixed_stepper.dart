/// Turns variable frame times into a whole number of fixed simulation steps.
///
/// Feeding `World.step` the raw frame time makes physics depend on frame rate
/// (a 30 fps phone and a 144 Hz monitor simulate differently, and a replay
/// diverges). Pass each frame's time to [advance] instead: it runs the
/// callback once per [step] of accumulated time, always with exactly [step].
class FixedStepper {
  /// The length of every simulation step, in seconds.
  final double step;

  /// Most steps one [advance] call will run. If a frame took far longer than
  /// that (a pause, a debugger), the excess time is dropped rather than run
  /// as a burst of catch-up steps that takes even longer (the spiral of death).
  final int maxStepsPerFrame;

  double _accumulated = 0;

  FixedStepper(this.step, {this.maxStepsPerFrame = 5}) {
    if (step <= 0) throw ArgumentError.value(step, 'step', 'must be > 0');
    if (maxStepsPerFrame < 1) {
      throw ArgumentError.value(maxStepsPerFrame, 'maxStepsPerFrame', '>= 1');
    }
  }

  /// Time carried over that has not yet made a whole step.
  double get leftover => _accumulated;

  /// How far between the last step and the next one the clock is, in [0, 1).
  /// Use it to interpolate drawing between two simulated states.
  double get alpha => _accumulated / step;

  /// Adds [frameSeconds] and calls [onStep] with [step] once per whole step
  /// now available, up to [maxStepsPerFrame]. Returns how many ran.
  int advance(double frameSeconds, void Function(double step) onStep) {
    if (frameSeconds < 0) {
      throw ArgumentError.value(frameSeconds, 'frameSeconds', 'must be >= 0');
    }
    _accumulated += frameSeconds;
    // Tolerance so 60 frames of 1/60 make exactly 60 steps despite rounding.
    const epsilon = 1e-9;
    var ran = 0;
    while (_accumulated >= step - epsilon && ran < maxStepsPerFrame) {
      onStep(step);
      _accumulated -= step;
      ran++;
    }
    if (_accumulated < 0) _accumulated = 0;
    if (_accumulated >= step - epsilon) _accumulated = 0;
    return ran;
  }

  /// Forgets any carried-over time.
  void reset() => _accumulated = 0;
}
