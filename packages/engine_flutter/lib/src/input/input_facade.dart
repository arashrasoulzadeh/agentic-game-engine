import 'input.dart';

/// One place to ask "what is the player doing", over whatever produced the
/// actions: keyboard, touch controls and gamepads all write named actions into
/// an [InputState], and this reads them with the questions games actually ask.
///
/// Adds what the raw state can't: edge detection (pressed *this frame*) and
/// composite axes (left/right keys as -1..1). Call [update] once per frame,
/// after input events were applied and before game logic reads, so
/// [justPressed] and [justReleased] compare against the previous frame.
///
/// ```dart
/// final input = Input(controller.state);
/// // each frame:
/// input.update();
/// if (input.justPressed('jump')) jump();
/// player.vx = input.axis('moveX', negative: 'left', positive: 'right') * 80;
/// ```
class Input {
  /// The live state this reads.
  final InputState state;
  Set<String> _previous = {};
  Set<String> _current = {};

  /// Wraps [state].
  Input(this.state);

  /// Snapshots the state; the previous snapshot becomes "last frame".
  void update() {
    _previous = _current;
    _current = {...state.pressedActions};
  }

  /// Whether [action] was held at the last [update].
  bool isDown(String action) => _current.contains(action);

  /// Whether [action] went down between the last two [update] calls.
  bool justPressed(String action) =>
      _current.contains(action) && !_previous.contains(action);

  /// Whether [action] was let go between the last two [update] calls.
  bool justReleased(String action) =>
      !_current.contains(action) && _previous.contains(action);

  /// A -1..1 value. Uses the analog axis [name] when it is nonzero; otherwise
  /// falls back to the [negative]/[positive] actions (-1, 0 or 1, and 0 when
  /// both are held).
  double axis(String name, {String? negative, String? positive}) {
    final analog = state.axis(name);
    if (analog != 0) return analog.clamp(-1.0, 1.0);
    final neg = negative != null && isDown(negative);
    final pos = positive != null && isDown(positive);
    return (pos ? 1.0 : 0.0) - (neg ? 1.0 : 0.0);
  }
}
