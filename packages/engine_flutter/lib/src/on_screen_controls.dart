import 'package:flutter/widgets.dart';

import 'input.dart';

/// One on-screen button: which logical action it sets while held, and
/// what to show on it. Used by [OnScreenControls]/`Game.onScreenButtons`.
class OnScreenButtonSpec {
  final String action;
  final String label;

  const OnScreenButtonSpec(this.action, this.label);
}

/// A draggable virtual joystick that sets `"left"`/`"right"`/`"up"`/
/// `"down"` on [controller] — the same logical actions a keyboard
/// binding would set, so `PlatformerInputSystem` (or any system reading
/// `InputState`) can't tell the two apart. Horizontal-only by default
/// (the common platformer case); pass [verticalEnabled] for a
/// top-down/free-movement game that also needs up/down.
class VirtualJoystick extends StatefulWidget {
  final InputController controller;
  final bool verticalEnabled;
  final double baseRadius;
  final double knobRadius;

  /// Fraction of [baseRadius] the knob must move past before a
  /// direction counts as pressed — avoids tiny accidental drags
  /// registering as movement.
  final double deadzone;

  const VirtualJoystick({
    super.key,
    required this.controller,
    this.verticalEnabled = false,
    this.baseRadius = 50,
    this.knobRadius = 24,
    this.deadzone = 0.25,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knobOffset = Offset.zero;
  final Set<String> _activeActions = {};

  void _updateFromLocalPosition(Offset localPosition) {
    final center = Offset(widget.baseRadius, widget.baseRadius);
    var delta = localPosition - center;
    final distance = delta.distance;
    if (distance > widget.baseRadius) {
      delta = delta * (widget.baseRadius / distance);
    }
    setState(() => _knobOffset = delta);
    _applyActions(delta);
  }

  void _applyActions(Offset delta) {
    final threshold = widget.baseRadius * widget.deadzone;
    final next = <String>{};
    if (delta.dx > threshold) next.add('right');
    if (delta.dx < -threshold) next.add('left');
    if (widget.verticalEnabled) {
      if (delta.dy > threshold) next.add('down');
      if (delta.dy < -threshold) next.add('up');
    }

    for (final action in _activeActions.difference(next)) {
      widget.controller.setAction(action, false);
    }
    for (final action in next.difference(_activeActions)) {
      widget.controller.setAction(action, true);
    }
    _activeActions
      ..clear()
      ..addAll(next);
  }

  void _clearActiveActions() {
    for (final action in _activeActions) {
      widget.controller.setAction(action, false);
    }
    _activeActions.clear();
  }

  void _reset() {
    _clearActiveActions();
    setState(() => _knobOffset = Offset.zero);
  }

  @override
  void dispose() {
    // Not setState -- the widget is already being torn down, so only
    // the controller side-effect (releasing any held direction) needs
    // to happen, not a rebuild.
    _clearActiveActions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.baseRadius * 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _updateFromLocalPosition(details.localPosition),
      onPanUpdate: (details) => _updateFromLocalPosition(details.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _circle(size, const Color(0x33FFFFFF)),
            Transform.translate(
              offset: _knobOffset,
              child: _circle(widget.knobRadius * 2, const Color(0x88FFFFFF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double diameter, Color color) => Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// An on-screen button that sets [spec.action] pressed for as long as
/// it's held down — the touch equivalent of holding a keyboard key.
class VirtualButton extends StatefulWidget {
  final InputController controller;
  final OnScreenButtonSpec spec;
  final double diameter;

  const VirtualButton({
    super.key,
    required this.controller,
    required this.spec,
    this.diameter = 64,
  });

  @override
  State<VirtualButton> createState() => _VirtualButtonState();
}

class _VirtualButtonState extends State<VirtualButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.controller.setAction(widget.spec.action, pressed);
  }

  @override
  void dispose() {
    if (_pressed) widget.controller.setAction(widget.spec.action, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: Container(
        width: widget.diameter,
        height: widget.diameter,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0x88FFFFFF) : const Color(0x33FFFFFF),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          widget.spec.label,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Joystick (bottom-left) + a row of buttons (bottom-right) overlaid on
/// the game — the default mobile control scheme. Compose your own
/// layout instead if this doesn't fit your game; `VirtualJoystick`/
/// `VirtualButton` work standalone.
class OnScreenControls extends StatelessWidget {
  final InputController controller;
  final bool verticalEnabled;
  final List<OnScreenButtonSpec> buttons;

  const OnScreenControls({
    super.key,
    required this.controller,
    this.verticalEnabled = false,
    this.buttons = const [OnScreenButtonSpec('jump', 'JUMP')],
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: VirtualJoystick(
              controller: controller,
              verticalEnabled: verticalEnabled,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final spec in buttons) ...[
                  VirtualButton(controller: controller, spec: spec),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
