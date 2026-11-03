import '../input/input.dart';

/// Scripts input for a headless test: press and release named actions on an
/// [InputState] and let time pass, without key events or a widget tree.
///
/// ```dart
/// final input = InputDriver(state, tick: tester.tick);
/// input.press('jump');      // held until released
/// input.tap('right', ticks: 10);
/// ```
///
/// [InputState] is plain data that systems read each step, so driving it
/// directly exercises the same path real keyboards, touch and gamepads use.
class InputDriver {
  InputDriver(this.state, {required this.tick});

  /// The state under test; hand the same instance to the systems.
  final InputState state;

  /// Advances the simulation by this many steps (e.g. `GameTester.tick`).
  /// Taken as a callback so this file stays free of the test-only library.
  final void Function(int ticks) tick;

  /// Holds [action] down until [release].
  void press(String action) => state.pressedActions.add(action);

  /// Lets go of [action]; a no-op if it was not held.
  void release(String action) => state.pressedActions.remove(action);

  /// Holds [action] for [ticks] steps, then releases it.
  void tap(String action, {int ticks = 1}) {
    press(action);
    try {
      tick(ticks);
    } finally {
      release(action);
    }
  }

  /// Sets an analog axis such as `moveX` to [value] (about -1..1). Press the
  /// matching discrete action yourself if the system under test reads that.
  void setAxis(String name, double value) {
    state.axisValues[name] = value;
  }

  /// Lets go of every action and zeroes every axis.
  void releaseAll() {
    state.pressedActions.clear();
    state.axisValues.clear();
  }
}
