import '../input/gamepad_controller.dart';
import '../input/gamepad_bindings_storage.dart';
import '../logic/scene.dart';
import 'button_menu_scene.dart';

/// A ready-made "press a gamepad button to rebind" controls menu —
/// the gamepad analogue of `RemapMenuScene`. Give it the actions to
/// show, the `GamepadController` to rebind, and where to go when
/// done; it handles listing each action's current button, capturing
/// the next button press (`GamepadController.captureNextButtonDown`)
/// when its button is tapped, and saving the result
/// (`GamepadBindingsStorage.save`) once rebound.
class GamepadRemapMenuScene extends ButtonMenuScene {
  GamepadRemapMenuScene(this.controller, this.actions, {required this.onDone});

  final GamepadController controller;

  /// Which actions to show, top to bottom — e.g.
  /// `['jump', 'attack', 'dash']`. Not necessarily every bound action;
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
          MenuButtonSpec(label: '${action.toUpperCase()}: ${_buttonLabelFor(action)}', actionId: action),
        const MenuButtonSpec(label: 'DONE', actionId: '_gamepadRemapDone'),
      ];

  String _buttonLabelFor(String action) {
    for (final entry in controller.buttonBindings.entries) {
      if (entry.value == action) return 'Button ${entry.key}';
    }
    return '(unbound)';
  }

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    if (actionId == '_gamepadRemapDone') {
      scenes.loadScene(onDone());
      return;
    }
    controller.captureNextButtonDown = (int buttonId) {
      // An action can only be bound to one button at a time -- drop any
      // existing binding for it before adding the new one, same as a
      // real "rebind" rather than "also bind."
      controller.buttonBindings.removeWhere((_, boundAction) => boundAction == actionId);
      controller.buttonBindings[buttonId] = actionId;
      GamepadBindingsStorage.save(controller);
      scenes.loadScene(GamepadRemapMenuScene(controller, actions, onDone: onDone));
    };
  }
}

/// Mixin to add capture-next-button functionality to [GamepadController].
/// Add this to your controller with `with GamepadCaptureMixin`.
mixin GamepadCaptureMixin on GamepadController {
  /// Set to capture the next button press as a binding for a specific
  /// action. When set, the next call to [handleButtonDown] will consume
  /// the button press and assign it to the action, rather than
  /// triggering the action normally. Clears itself after use.
  void Function(int buttonId)? captureNextButtonDown;

  @override
  void handleButtonDown(int buttonId) {
    final capture = captureNextButtonDown;
    if (capture != null) {
      captureNextButtonDown = null;
      capture(buttonId);
      return;
    }
    super.handleButtonDown(buttonId);
  }
}