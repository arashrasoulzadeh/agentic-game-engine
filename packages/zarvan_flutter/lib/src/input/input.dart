import 'package:zarvan_core/zarvan_core.dart' show ActionAliases;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

/// Logical input state ("left"/"jump" are pressed), not raw Flutter key
/// codes — zarvan_core systems read this, so it must stay Flutter-free
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
    ((json['axes'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
  );
}

/// Translates raw Flutter key events into an [InputState] via a
/// configurable key-to-action binding. Mutates the state in place so
/// whatever holds a reference (an ECS component store) sees updates
/// immediately, with no per-frame sync step required.
class InputController {
  final InputState state;
  final Map<LogicalKeyboardKey, String> bindings;

  /// Friendly names the remap menus and debug overlay show instead of raw
  /// action ids. Display only: the id in [bindings] is still what systems
  /// read, so changing a label never affects gameplay or saved bindings.
  final ActionAliases aliases;

  InputController({
    InputState? state,
    Map<LogicalKeyboardKey, String>? bindings,
    ActionAliases? aliases,
  }) : state = state ?? InputState(),
       bindings = bindings ?? defaultBindings(),
       aliases = aliases ?? ActionAliases();

  /// Arrow keys and space; with [wasd], W/A/S/D too (extra keys for the same
  /// actions, so nothing that read `left` or `jump` changes).
  static Map<LogicalKeyboardKey, String> defaultBindings({bool wasd = false}) =>
      {
        LogicalKeyboardKey.arrowLeft: 'left',
        LogicalKeyboardKey.arrowRight: 'right',
        LogicalKeyboardKey.arrowUp: 'up',
        LogicalKeyboardKey.arrowDown: 'down',
        LogicalKeyboardKey.space: 'jump',
        if (wasd) ...{
          LogicalKeyboardKey.keyA: 'left',
          LogicalKeyboardKey.keyD: 'right',
          LogicalKeyboardKey.keyW: 'up',
          LogicalKeyboardKey.keyS: 'down',
        },
      };

  /// Binds [key] to [action], replacing whatever [key] did before. Several
  /// keys may share one action (that is how arrows and WASD both mean `left`).
  void bind(LogicalKeyboardKey key, String action) => bindings[key] = action;

  /// Binds every key in [keys] to [action].
  void bindAll(String action, Iterable<LogicalKeyboardKey> keys) {
    for (final key in keys) {
      bind(key, action);
    }
  }

  /// Removes every key bound to [action]; if it was held, lets it go too, so a
  /// rebind menu cannot leave a stuck action behind.
  void unbindAction(String action) {
    bindings.removeWhere((_, bound) => bound == action);
    state.pressedActions.remove(action);
  }

  /// Every key currently bound to [action], for a remap menu to display.
  List<LogicalKeyboardKey> keysFor(String action) => [
    for (final entry in bindings.entries)
      if (entry.value == action) entry.key,
  ];

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
