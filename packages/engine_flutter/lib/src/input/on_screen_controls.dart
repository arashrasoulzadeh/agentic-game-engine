import 'dart:ui' as ui;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import 'input.dart';
import '../rendering/sprite_atlas.dart';

/// One on-screen button: which logical action it sets while held, and
/// what to show on it. Used by [OnScreenControls]/`Game.onScreenButtons`.
///
/// The default constructor covers the common case (a label on a plain
/// circle). Use [OnScreenButtonSpec.custom] for a sprite-based button
/// (draws a region from the game's own atlas — the same
/// `AtlasRegistry`/`SpriteAtlas` your characters use, so a button can
/// literally be a game icon) or any other visual customization: colors,
/// size, shape, a different sprite while pressed, custom label style.
class OnScreenButtonSpec {
  final String action;
  final String? label;
  final Color idleColor;
  final Color pressedColor;
  final double diameter;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final TextStyle? labelStyle;

  /// Which atlas (registered via `AtlasRegistry.register`) and region
  /// to draw as the button's face, instead of a plain color. Both must
  /// be set for a sprite to render; falls back to [idleColor]/[label]
  /// if the atlas isn't found (e.g. not loaded yet).
  final String? atlasId;
  final String? region;

  /// Swaps to this region while the button is held, if given — e.g. a
  /// "pressed" frame for a button that looks like it depresses.
  final String? pressedRegion;

  const OnScreenButtonSpec(this.action, [this.label])
      : idleColor = const Color(0x33FFFFFF),
        pressedColor = const Color(0x88FFFFFF),
        diameter = 64,
        shape = BoxShape.circle,
        borderRadius = null,
        labelStyle = null,
        atlasId = null,
        region = null,
        pressedRegion = null;

  const OnScreenButtonSpec.custom(
    this.action, {
    this.label,
    this.idleColor = const Color(0x33FFFFFF),
    this.pressedColor = const Color(0x88FFFFFF),
    this.diameter = 64,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.labelStyle,
    this.atlasId,
    this.region,
    this.pressedRegion,
  });
}

/// A draggable virtual joystick that sets `"left"`/`"right"`/`"up"`/
/// `"down"` on [controller] — the same logical actions a keyboard
/// binding would set, so `PlatformerInputSystem` (or any system reading
/// `InputState`) can't tell the two apart. Horizontal-only by default
/// (the common platformer case); pass [verticalEnabled] for a
/// top-down/free-movement game that also needs up/down.
///
/// [floating] (default `true`, the standard mobile-game pattern) makes
/// the joystick invisible until touched, then draws it wherever the
/// finger lands within the widget's bounds — this is what avoids a
/// fixed-position joystick permanently overlapping gameplay content
/// (e.g. a camera-followed player rendered underneath it near a world
/// edge, which a fixed base can't avoid in general). Pass `false` for
/// the classic always-visible joystick at a fixed spot instead.
class VirtualJoystick extends StatefulWidget {
  final InputController controller;
  final bool verticalEnabled;
  final double baseRadius;
  final double knobRadius;
  final bool floating;

  /// Fraction of [baseRadius] the knob must move past before a
  /// direction counts as pressed — avoids tiny accidental drags
  /// registering as movement.
  final double deadzone;

  /// Whether the axis names `"moveX"`/`"moveY"` are set on
  /// [InputController.state] with the stick's continuous displacement
  /// (range -1..1), in addition to the discrete `"left"`/`"right"`/
  /// `"up"`/`"down"` actions. Off by default — most existing systems
  /// (e.g. `PlatformerInputSystem`) only read the discrete actions, so
  /// this is opt-in for games that want variable-speed movement/aim.
  final bool analogOutput;

  /// Whether a short vibration plays when the stick first moves past
  /// the deadzone (i.e. a new direction starts). No-op on platforms
  /// without haptic support (e.g. web).
  final bool hapticFeedback;

  const VirtualJoystick({
    super.key,
    required this.controller,
    this.verticalEnabled = false,
    this.baseRadius = 50,
    this.knobRadius = 24,
    this.deadzone = 0.25,
    this.floating = true,
    this.analogOutput = false,
    this.hapticFeedback = true,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  // A ValueNotifier, not a plain field rebuilt via setState -- onPanUpdate
  // fires on every raw pointer-move event (tens of times/sec while
  // dragging), and setState here would rebuild this whole subtree
  // (GestureDetector, LayoutBuilder, the base/knob Stack, both
  // BoxDecoration containers) every single time just to move one dot a
  // few pixels. Measured live on a real device: frame times up to 75ms
  // while holding the stick, with EngineView's own step/paint/light all
  // under 1.5ms combined in the same frames -- proving the cost was
  // entirely outside the engine's render pipeline, on exactly this
  // input-handling path. A ValueListenableBuilder around only the
  // knob's Transform.translate (see _joystickVisual) means a drag now
  // repaints just that one translated circle instead of rebuilding and
  // relaying-out the whole joystick every pointer-move event.
  final ValueNotifier<Offset> _knobOffset = ValueNotifier(Offset.zero);
  Offset? _origin;
  final Set<String> _activeActions = {};

  void _onDragStart(Offset localPosition, Size bounds) {
    if (widget.floating) {
      // Clamp so the base circle stays fully within bounds even if the
      // finger lands right at an edge. setState here is fine -- this
      // only runs once per drag (onPanStart), not on every move.
      setState(() {
        _origin = Offset(
          localPosition.dx.clamp(widget.baseRadius, bounds.width - widget.baseRadius),
          localPosition.dy.clamp(widget.baseRadius, bounds.height - widget.baseRadius),
        );
      });
    }
    _updateKnob(localPosition);
  }

  void _updateKnob(Offset localPosition) {
    final origin = _origin ?? Offset(widget.baseRadius, widget.baseRadius);
    var delta = localPosition - origin;
    final distance = delta.distance;
    if (distance > widget.baseRadius) {
      delta = delta * (widget.baseRadius / distance);
    }
    _knobOffset.value = delta;
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

    if (widget.hapticFeedback && _activeActions.isEmpty && next.isNotEmpty) {
      HapticFeedback.selectionClick();
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

    if (widget.analogOutput) {
      widget.controller.setAxis('moveX', (delta.dx / widget.baseRadius).clamp(-1.0, 1.0));
      if (widget.verticalEnabled) {
        widget.controller.setAxis('moveY', (delta.dy / widget.baseRadius).clamp(-1.0, 1.0));
      }
    }
  }

  void _clearActiveActions() {
    for (final action in _activeActions) {
      widget.controller.setAction(action, false);
    }
    _activeActions.clear();
    if (widget.analogOutput) {
      widget.controller.setAxis('moveX', 0);
      if (widget.verticalEnabled) widget.controller.setAxis('moveY', 0);
    }
  }

  void _reset() {
    _clearActiveActions();
    _knobOffset.value = Offset.zero;
    if (widget.floating) {
      // Structural change (the floating visual disappears entirely) --
      // still needs setState, but this only runs once per drag
      // (onPanEnd/onPanCancel), not on every move.
      setState(() => _origin = null);
    }
  }

  @override
  void dispose() {
    // Not setState -- the widget is already being torn down, so only
    // the controller side-effect (releasing any held direction) needs
    // to happen, not a rebuild.
    _clearActiveActions();
    _knobOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onDragStart(details.localPosition, bounds),
          onPanUpdate: (details) => _updateKnob(details.localPosition),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: SizedBox.expand(
            child: (widget.floating && _origin == null)
                ? null
                : _joystickVisual(widget.floating ? _origin! : null, bounds),
          ),
        );
      },
    );
  }

  Widget _joystickVisual(Offset? floatingOrigin, Size bounds) {
    final size = widget.baseRadius * 2;
    final base = Stack(
      alignment: Alignment.center,
      children: [
        _circle(size, const Color(0x33FFFFFF)),
        ValueListenableBuilder<Offset>(
          valueListenable: _knobOffset,
          builder: (context, offset, child) => Transform.translate(offset: offset, child: child),
          child: _circle(widget.knobRadius * 2, const Color(0x88FFFFFF)),
        ),
      ],
    );

    if (floatingOrigin == null) {
      // Fixed mode: bottom-left of whatever space this widget occupies.
      return Align(alignment: Alignment.bottomLeft, child: base);
    }
    return Stack(children: [
      Positioned(
        left: floatingOrigin.dx - widget.baseRadius,
        top: floatingOrigin.dy - widget.baseRadius,
        child: base,
      ),
    ]);
  }

  Widget _circle(double diameter, Color color) => Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// An on-screen button that sets [spec.action] pressed for as long as
/// it's held down — the touch equivalent of holding a keyboard key.
/// Renders a sprite from [atlasRegistry] when [spec] names one (see
/// `OnScreenButtonSpec.custom`); otherwise a colored shape + label.
class VirtualButton extends StatefulWidget {
  final InputController controller;
  final OnScreenButtonSpec spec;
  final AtlasRegistry? atlasRegistry;

  /// Whether a short vibration plays on press. No-op on platforms
  /// without haptic support (e.g. web).
  final bool hapticFeedback;

  const VirtualButton({
    super.key,
    required this.controller,
    required this.spec,
    this.atlasRegistry,
    this.hapticFeedback = true,
  });

  @override
  State<VirtualButton> createState() => _VirtualButtonState();
}

class _VirtualButtonState extends State<VirtualButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    if (pressed && widget.hapticFeedback) HapticFeedback.selectionClick();
    setState(() => _pressed = pressed);
    widget.controller.setAction(widget.spec.action, pressed);
  }

  @override
  void dispose() {
    if (_pressed) widget.controller.setAction(widget.spec.action, false);
    super.dispose();
  }

  SpriteAtlas? _resolveAtlas() {
    final atlasId = widget.spec.atlasId;
    final registry = widget.atlasRegistry;
    if (atlasId == null || registry == null || !registry.has(atlasId)) {
      return null;
    }
    return registry.resolve(atlasId);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final activeRegion =
        (_pressed ? spec.pressedRegion ?? spec.region : spec.region);
    final atlas = activeRegion == null ? null : _resolveAtlas();

    final Widget visual;
    if (atlas != null && activeRegion != null) {
      visual = CustomPaint(
        key: ValueKey(activeRegion),
        painter: _SpritePainter(atlas, activeRegion),
      );
    } else {
      visual = DecoratedBox(
        decoration: BoxDecoration(
          color: _pressed ? spec.pressedColor : spec.idleColor,
          shape: spec.shape,
          borderRadius: spec.shape == BoxShape.rectangle ? spec.borderRadius : null,
        ),
        child: spec.label == null
            ? null
            : Center(
                child: Text(
                  spec.label!,
                  style: spec.labelStyle ??
                      const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
      );
    }

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: SizedBox(width: spec.diameter, height: spec.diameter, child: visual),
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  final SpriteAtlas atlas;
  final String region;

  _SpritePainter(this.atlas, this.region);

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = atlas.regionFor(region);
    canvas.drawImageRect(
      atlas.image,
      srcRect,
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.region != region;
}

/// Joystick (bottom-left) + a row of buttons (bottom-right) overlaid on
/// the game — the default mobile control scheme. Compose your own
/// layout instead if this doesn't fit your game; `VirtualJoystick`/
/// `VirtualButton` work standalone.
class OnScreenControls extends StatelessWidget {
  final InputController controller;
  final bool verticalEnabled;
  final List<OnScreenButtonSpec> buttons;

  /// Needed only for buttons using `OnScreenButtonSpec.custom`'s
  /// `atlasId`/`region` — omit if none of your buttons are sprite-based.
  final AtlasRegistry? atlasRegistry;

  /// See `VirtualJoystick.analogOutput` — off by default.
  final bool analogOutput;

  /// See `VirtualJoystick.hapticFeedback`/`VirtualButton.hapticFeedback`
  /// — on by default for both the joystick and every button.
  final bool hapticFeedback;

  const OnScreenControls({
    super.key,
    required this.controller,
    this.verticalEnabled = false,
    this.buttons = const [OnScreenButtonSpec('jump', 'JUMP')],
    this.atlasRegistry,
    this.analogOutput = false,
    this.hapticFeedback = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // The joystick gets the whole bottom-left region as its touch
          // area (floating: true by default, so it's invisible until
          // touched) rather than a small fixed-size box in the corner
          // -- both so there's room for the finger to land anywhere
          // comfortable, and so nothing is drawn over gameplay content
          // until the player actually starts using it.
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.bottomLeft,
              widthFactor: 0.5,
              heightFactor: 0.6,
              child: VirtualJoystick(
                controller: controller,
                verticalEnabled: verticalEnabled,
                analogOutput: analogOutput,
                hapticFeedback: hapticFeedback,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final spec in buttons) ...[
                  VirtualButton(
                    controller: controller,
                    spec: spec,
                    atlasRegistry: atlasRegistry,
                    hapticFeedback: hapticFeedback,
                  ),
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
