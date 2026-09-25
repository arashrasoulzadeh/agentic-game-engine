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
  final Map<int, (String positive, String negative)> axisBindings;
  final Map<int, String> axisNames;

  /// How far past `0` an axis value must move before it's treated as
  /// pressed in either direction — real analog sticks rarely rest at
  /// exactly `0.0`, so a deadzone this small (not `0`) avoids a
  /// resting stick spuriously holding an action pressed.
  final double deadzone;

  /// Vibration/haptic feedback support — returns a [GamepadHaptics]
  /// handle if the underlying platform/plugin supports vibration.
  /// Null if the current platform/plugin doesn't support vibration.
  final GamepadHaptics? haptics;

  /// Set to capture the next button press as a binding for a specific
  /// action. When set, the next call to [handleButtonDown] will consume
  /// the button press and assign it to the action, rather than
  /// triggering the action normally. Clears itself after use.
  void Function(int buttonId)? captureNextButtonDown;

  GamepadController({
    required this.input,
    Map<int, String>? buttonBindings,
    Map<int, (String, String)>? axisBindings,
    Map<int, String>? axisNames,
    this.deadzone = 0.2,
    this.haptics,
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
    final capture = captureNextButtonDown;
    if (capture != null) {
      captureNextButtonDown = null;
      capture(buttonId);
      return;
    }
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

/// Abstract handle for gamepad vibration/haptic feedback.
/// Implementations are provided by platform-specific plugins (e.g.
/// Flutter's `gamepad_vibration`, Android's `Vibrator`, iOS's
/// `CoreHaptics`, etc.). The engine core doesn't depend on any
/// specific plugin — this is the transport-agnostic interface.
abstract class GamepadHaptics {
  /// Triggers a simple "rumble" with [strongMagnitude] (low-freq) and
  /// [weakMagnitude] (high-freq) for [duration]. Values are `0.0..1.0`.
  /// Returns a [Future] that completes when the effect finishes or is
  /// cancelled. Implementations should be idempotent: calling again
  /// while already vibrating restarts the effect.
  Future<void> rumble({
    double strongMagnitude = 1.0,
    double weakMagnitude = 1.0,
    Duration duration = const Duration(milliseconds: 200),
  });

  /// Triggers a more complex haptic pattern defined by [pattern]
  /// (pairs of [Duration, Intensity]). See [HapticPattern] for details.
  Future<void> playPattern(HapticPattern pattern);

  /// Stops any ongoing vibration/haptic effect immediately.
  Future<void> stop();
}

/// A reusable haptic pattern definition — sequence of (duration, intensity)
/// pairs. Intensity is `0.0..1.0` representing combined strong/weak.
class HapticPattern {
  final List<(Duration, double)> steps;

  HapticPattern(this.steps);

  static HapticPattern sharpClick() => HapticPattern([
    (Duration(milliseconds: 10), 1.0),
    (Duration(milliseconds: 50), 0.0),
  ]);

  static HapticPattern doubleClick() => HapticPattern([
    (Duration(milliseconds: 10), 1.0),
    (Duration(milliseconds: 40), 0.0),
    (Duration(milliseconds: 10), 1.0),
    (Duration(milliseconds: 50), 0.0),
  ]);

  static HapticPattern heavyImpact() => HapticPattern([
    (Duration(milliseconds: 100), 1.0),
    (Duration(milliseconds: 300), 0.5),
    (Duration(milliseconds: 200), 0.0),
  ]);

  static HapticPattern heartbeat() => HapticPattern([
    (Duration(milliseconds: 50), 0.8),
    (Duration(milliseconds: 100), 0.0),
    (Duration(milliseconds: 50), 0.8),
    (Duration(milliseconds: 400), 0.0),
  ]);
}

/// A no-op [GamepadHaptics] implementation for platforms/tests that
/// don't support vibration. All methods complete immediately.
class NoOpHaptics implements GamepadHaptics {
  const NoOpHaptics();

  @override
  Future<void> rumble({
    double strongMagnitude = 1.0,
    double weakMagnitude = 1.0,
    Duration duration = const Duration(milliseconds: 200),
  }) async {}

  @override
  Future<void> playPattern(HapticPattern pattern) async {}

  @override
  Future<void> stop() async {}
}

/// A no-op [GamepadController] with no haptics — useful for tests
/// or headless environments where no gamepad plugin is available.
class NoOpGamepadController extends GamepadController {
  NoOpGamepadController()
      : super(
          input: InputController(),
          haptics: const NoOpHaptics(),
        );
}