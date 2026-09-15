import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handleButtonDown/Up sets the bound action, ignores an unbound button id', () {
    final controller = GamepadController(input: InputController());

    controller.handleButtonDown(0); // bound to 'jump' by default
    expect(controller.input.state.isPressed('jump'), isTrue);

    controller.handleButtonUp(0);
    expect(controller.input.state.isPressed('jump'), isFalse);

    controller.handleButtonDown(999); // unbound
    expect(controller.input.state.pressedActions, isEmpty);
  });

  test('handleAxis reports the raw value under axisNames regardless of bindings', () {
    final controller = GamepadController(input: InputController());
    controller.handleAxis(0, 0.75);
    expect(controller.input.state.axis('moveX'), 0.75);
  });

  test('handleAxis past the positive deadzone presses the positive action, not the negative', () {
    final controller = GamepadController(input: InputController());
    controller.handleAxis(0, 0.9);
    expect(controller.input.state.isPressed('right'), isTrue);
    expect(controller.input.state.isPressed('left'), isFalse);
  });

  test('handleAxis past the negative deadzone presses the negative action, not the positive', () {
    final controller = GamepadController(input: InputController());
    controller.handleAxis(0, -0.9);
    expect(controller.input.state.isPressed('left'), isTrue);
    expect(controller.input.state.isPressed('right'), isFalse);
  });

  test('handleAxis inside the deadzone presses neither direction', () {
    final controller = GamepadController(input: InputController());
    controller.handleAxis(0, 0.05);
    expect(controller.input.state.isPressed('right'), isFalse);
    expect(controller.input.state.isPressed('left'), isFalse);
  });

  test('a stick recentered after being pushed clears the previously-pressed direction', () {
    final controller = GamepadController(input: InputController());
    controller.handleAxis(0, 0.9);
    expect(controller.input.state.isPressed('right'), isTrue);

    controller.handleAxis(0, 0.0);
    expect(controller.input.state.isPressed('right'), isFalse);
  });

  test('a custom deadzone is respected', () {
    final controller = GamepadController(input: InputController(), deadzone: 0.5);
    controller.handleAxis(0, 0.3);
    expect(controller.input.state.isPressed('right'), isFalse,
        reason: '0.3 is inside the wider 0.5 deadzone');

    controller.handleAxis(0, 0.6);
    expect(controller.input.state.isPressed('right'), isTrue);
  });

  test('custom bindings override the defaults entirely', () {
    final controller = GamepadController(
      input: InputController(),
      buttonBindings: {5: 'dash'},
      axisBindings: {},
      axisNames: {},
    );

    controller.handleButtonDown(0); // default binding no longer applies
    expect(controller.input.state.pressedActions, isEmpty);

    controller.handleButtonDown(5);
    expect(controller.input.state.isPressed('dash'), isTrue);
  });

  test('button/axis input and keyboard/touch input share the same InputState', () {
    final input = InputController();
    final gamepad = GamepadController(input: input);

    input.setAction('jump', true); // e.g. from touch
    gamepad.handleButtonDown(12); // d-pad up, bound to 'up'

    expect(input.state.isPressed('jump'), isTrue);
    expect(input.state.isPressed('up'), isTrue);
  });
}
