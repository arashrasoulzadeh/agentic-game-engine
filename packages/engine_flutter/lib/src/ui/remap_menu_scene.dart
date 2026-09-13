import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../input.dart';
import '../input_bindings_storage.dart';
import '../scene.dart';
import 'button_menu_scene.dart';

/// A ready-made "press a key to rebind" controls menu — the
/// `SaveSlotMenuScene` analogue for input: give it the actions to show,
/// the `InputController` to rebind, and where to go when done; it
/// handles listing each action's current key, capturing the next key
/// press (`InputController.captureNextKeyDown`) when its button is
/// tapped, and saving the result (`InputBindingsStorage.save`) once
/// rebound. Concrete (not subclassed like `SaveSlotMenuScene`) since
/// every bit of its behavior is already a plain constructor
/// parameter — no per-game override hook is actually needed.
///
/// Tapping an action's button starts listening; there's no separate
/// "press any key now" visual state on that button itself (a
/// deliberate, documented simplification — showing one would need a
/// second update to the same still-loading scene's rendered atlas,
/// which `ButtonMenuScene` doesn't support mid-populate). The whole
/// menu reloads (`scenes.loadScene`) once a key is captured, the same
/// way `MainMenuScene` reflects an updated coin count from `GameState`
/// — reading the just-changed `InputController.bindings` fresh, so the
/// tapped button's new key shows immediately after the press.
class RemapMenuScene extends ButtonMenuScene {
  RemapMenuScene(this.inputController, this.actions, {required this.onDone});

  final InputController inputController;

  /// Which actions to show, top to bottom — e.g.
  /// `['left', 'right', 'jump']`. Not necessarily every bound action;
  /// a game with actions it doesn't want players rebinding (an
  /// always-on debug key, say) just leaves them out of this list.
  final List<String> actions;

  /// Builds the `Scene` to switch to when "DONE" is tapped — typically
  /// back to wherever this menu was opened from (a settings menu, the
  /// pause menu).
  final Scene Function() onDone;

  @override
  List<MenuButtonSpec> buttons() => [
        for (final action in actions)
          MenuButtonSpec(label: '${action.toUpperCase()}: ${_keyLabelFor(action)}', actionId: action),
        const MenuButtonSpec(label: 'DONE', actionId: '_remapDone'),
      ];

  String _keyLabelFor(String action) {
    for (final entry in inputController.bindings.entries) {
      if (entry.value == action) return entry.key.keyLabel;
    }
    return '(unbound)';
  }

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    if (actionId == '_remapDone') {
      scenes.loadScene(onDone());
      return;
    }
    inputController.captureNextKeyDown = (LogicalKeyboardKey key) {
      // An action can only be bound to one key at a time -- drop any
      // existing binding for it before adding the new one, same as a
      // real "rebind" rather than "also bind."
      inputController.bindings.removeWhere((_, boundAction) => boundAction == actionId);
      inputController.bindings[key] = actionId;
      InputBindingsStorage.save(inputController);
      scenes.loadScene(RemapMenuScene(inputController, actions, onDone: onDone));
    };
  }
}
