import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

/// Logical input state ("left"/"jump" are pressed), not raw Flutter key
/// codes — engine_core systems read this, so it must stay Flutter-free
/// and stay plain data (agent-editable, e.g. to script input for a replay
/// or a bot).
class InputState {
  final Set<String> pressedActions;

  /// Continuous values (e.g. `"moveX"`/`"moveY"` from an analog
  /// joystick), range roughly -1..1. Discrete `pressedActions` are still
  /// set alongside these past the deadzone, so a system can ignore axes
  /// entirely and just read booleans if it doesn't need magnitude.
  final Map<String, double> axisValues;

  InputState([Set<String>? pressedActions, Map<String, double>? axisValues])
      : pressedActions = pressedActions ?? <String>{},
        axisValues = axisValues ?? <String, double>{};

  bool isPressed(String action) => pressedActions.contains(action);

  double axis(String name) => axisValues[name] ?? 0.0;

  Map<String, dynamic> toJson() => {
        'pressed': pressedActions.toList(),
        'axes': axisValues,
      };

  factory InputState.fromJson(Map<String, dynamic> json) => InputState(
        ((json['pressed'] as List?) ?? const []).cast<String>().toSet(),
        ((json['axes'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}

/// Translates raw Flutter key events into an [InputState] via a
/// configurable key-to-action binding. Mutates the state in place so
/// whatever holds a reference (an ECS component store) sees updates
/// immediately, with no per-frame sync step required.
class InputController {
  final InputState state;
  final Map<LogicalKeyboardKey, String> bindings;

  InputController({InputState? state, Map<LogicalKeyboardKey, String>? bindings})
      : state = state ?? InputState(),
        bindings = bindings ?? defaultBindings();

  static Map<LogicalKeyboardKey, String> defaultBindings() => {
        LogicalKeyboardKey.arrowLeft: 'left',
        LogicalKeyboardKey.arrowRight: 'right',
        LogicalKeyboardKey.arrowUp: 'up',
        LogicalKeyboardKey.arrowDown: 'down',
        LogicalKeyboardKey.space: 'jump',
      };

  /// Set by a control-remapping UI (see `RemapMenuScene`) to capture
  /// the *next* physical key pressed, regardless of whether it's
  /// already bound — [handleKeyEvent] checks this first, calls it with
  /// that key, clears it back to `null`, and consumes the event, so
  /// the key's old binding (if it had one) doesn't also fire from the
  /// same press it's being reassigned by. `null` (the default) means
  /// normal binding-based handling — nothing about this changes
  /// gameplay input unless something explicitly sets it.
  void Function(LogicalKeyboardKey key)? captureNextKeyDown;

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final capture = captureNextKeyDown;
      if (capture != null) {
        captureNextKeyDown = null;
        capture(event.logicalKey);
        return KeyEventResult.handled;
      }
    }

    final action = bindings[event.logicalKey];
    if (action == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      state.pressedActions.add(action);
    } else if (event is KeyUpEvent) {
      state.pressedActions.remove(action);
    }
    return KeyEventResult.handled;
  }

  /// Sets a logical action's pressed state directly — the touch-input
  /// counterpart to [handleKeyEvent], used by [VirtualJoystick]/
  /// [VirtualButton] since touch has no `LogicalKeyboardKey` to bind.
  /// Systems reading [state] (e.g. `PlatformerInputSystem`) can't tell
  /// keyboard and touch input apart, by design — both just set the same
  /// named actions.
  void setAction(String action, bool pressed) {
    if (pressed) {
      state.pressedActions.add(action);
    } else {
      state.pressedActions.remove(action);
    }
  }

  /// Sets a continuous axis value (e.g. `"moveX"`) — the analog
  /// counterpart to [setAction], used by [VirtualJoystick] to report
  /// stick displacement instead of just discrete direction booleans.
  void setAxis(String name, double value) {
    state.axisValues[name] = value;
  }
}
