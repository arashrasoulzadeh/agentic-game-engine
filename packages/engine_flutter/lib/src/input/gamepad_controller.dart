import 'input.dart';

/// Translates generic gamepad button/axis ids into the same
/// [InputState] keyboard and touch input already write to — this
/// engine deliberately doesn't depend on any specific gamepad plugin
/// (no such dependency exists in `pubspec.yaml`, and which one is
/// right varies by target platform/plugin maturity); instead this is
/// the transport-agnostic *binding* layer any plugin's raw button/axis
/// callbacks can be wired into with a few lines at the call site, the
/// same way [InputController.handleKeyEvent] is wired to Flutter's own
/// `Focus`/`KeyEvent` widgets. `PlatformerInputSystem` and friends
/// can't tell a gamepad, a keyboard, or a touch control apart, by
/// design — they only ever read [InputState]'s logical action names.
///
/// Button/axis ids are plain `int`s rather than an enum, since a real
/// gamepad plugin's own button/axis identifiers (raw HID usage codes,
/// a platform-specific button index, etc.) vary by plugin and
/// platform — this stays a dumb lookup table over whatever ids the
/// call site already has, not a guess at a "standard" gamepad layout.
class GamepadController {
  final InputController input;
  final Map<int, String> buttonBindings;

  /// Which logical action an axis's *positive* (` >0`) and *negative*
  /// (`<0`) direction each set, alongside reporting the raw analog
  /// value via [InputState.axisValues] — e.g. a left-stick X axis
  /// bound to `('right', 'left')` sets action `"right"` pressed while
  /// its value is positive past [deadzone], `"left"` while negative
  /// past it, and neither inside the deadzone (stick recentered).
  final Map<int, (String positive, String negative)> axisBindings;

  /// Which `InputState.axisValues` name an axis id reports its raw
  /// value under (e.g. axis id `0` -> `"moveX"`), independent of
  /// [axisBindings]'s discrete action mapping for the same id — a
  /// system that wants magnitude (`InputState.axis('moveX')`) and one
  /// that only wants direction (`InputState.isPressed('right')`) are
  /// both served from the same [handleAxis] call.
  final Map<int, String> axisNames;

  /// How far past `0` an axis value must move before it's treated as
  /// pressed in either direction — real analog sticks rarely rest at
  /// exactly `0.0`, so a deadzone this small (not `0`) avoids a
  /// resting stick spuriously holding an action pressed.
  final double deadzone;

  GamepadController({
    required this.input,
    Map<int, String>? buttonBindings,
    Map<int, (String, String)>? axisBindings,
    Map<int, String>? axisNames,
    this.deadzone = 0.2,
  })  : buttonBindings = buttonBindings ?? defaultButtonBindings(),
        axisBindings = axisBindings ?? defaultAxisBindings(),
        axisNames = axisNames ?? defaultAxisNames();

  /// A standard-layout gamepad's face/d-pad buttons — `0`-`3` the
  /// four face buttons (A/B/X/Y or ✕/○/□/△ depending on platform),
  /// `12`-`15` the d-pad, matching the button-index order the [W3C
  /// Gamepad API's "standard" mapping](https://www.w3.org/TR/gamepad/#remapping)
  /// defines, since that's the closest thing to a cross-platform
  /// convention most gamepad plugins already follow or can be
  /// remapped into.
  static Map<int, String> defaultButtonBindings() => {
        0: 'jump',
        12: 'up',
        13: 'down',
        14: 'left',
        15: 'right',
      };

  /// The W3C standard mapping's left analog stick: axis `0` is
  /// horizontal, axis `1` vertical.
  static Map<int, (String, String)> defaultAxisBindings() => {
        0: ('right', 'left'),
        1: ('down', 'up'),
      };

  static Map<int, String> defaultAxisNames() => {
        0: 'moveX',
        1: 'moveY',
      };

  void handleButtonDown(int buttonId) {
    final action = buttonBindings[buttonId];
    if (action != null) input.setAction(action, true);
  }

  void handleButtonUp(int buttonId) {
    final action = buttonBindings[buttonId];
    if (action != null) input.setAction(action, false);
  }

  /// Reports axis [axisId]'s current [value] (typically `-1.0..1.0`).
  /// Updates the raw [axisNames] value unconditionally, and — if
  /// [axisBindings] has an entry for this id — the positive/negative
  /// discrete actions per [deadzone], clearing whichever direction(s)
  /// the value no longer satisfies so a stick released back to center
  /// doesn't leave a direction stuck pressed.
  void handleAxis(int axisId, double value) {
    final name = axisNames[axisId];
    if (name != null) input.setAxis(name, value);

    final actions = axisBindings[axisId];
    if (actions == null) return;
    final (positive, negative) = actions;
    input.setAction(positive, value > deadzone);
    input.setAction(negative, value < -deadzone);
  }
}
