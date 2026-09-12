import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

/// Logical input state ("left"/"jump" are pressed), not raw Flutter key
/// codes — engine_core systems read this, so it must stay Flutter-free
/// and stay plain data (agent-editable, e.g. to script input for a replay
/// or a bot).
class InputState {
  final Set<String> pressedActions;

  InputState([Set<String>? pressedActions])
      : pressedActions = pressedActions ?? <String>{};

  bool isPressed(String action) => pressedActions.contains(action);

  Map<String, dynamic> toJson() => {'pressed': pressedActions.toList()};

  factory InputState.fromJson(Map<String, dynamic> json) => InputState(
        ((json['pressed'] as List?) ?? const []).cast<String>().toSet(),
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

  KeyEventResult handleKeyEvent(KeyEvent event) {
    final action = bindings[event.logicalKey];
    if (action == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      state.pressedActions.add(action);
    } else if (event is KeyUpEvent) {
      state.pressedActions.remove(action);
    }
    return KeyEventResult.handled;
  }
}
