import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setAction(true) then setAction(false) toggles pressedActions', () {
    final controller = InputController();
    expect(controller.state.isPressed('jump'), isFalse);

    controller.setAction('jump', true);
    expect(controller.state.isPressed('jump'), isTrue);

    controller.setAction('jump', false);
    expect(controller.state.isPressed('jump'), isFalse);
  });
}
