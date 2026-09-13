import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InputState round-trips through toJson/fromJson', () {
    final state = InputState({'jump', 'left'}, {'moveX': 0.5});
    final decoded = InputState.fromJson(state.toJson());

    expect(decoded.pressedActions, {'jump', 'left'});
    expect(decoded.axis('moveX'), 0.5);
    expect(decoded.axis('moveY'), 0.0);
  });

  test('InputState.fromJson defaults to empty when pressed/axes are absent', () {
    final decoded = InputState.fromJson({});
    expect(decoded.pressedActions, isEmpty);
    expect(decoded.axisValues, isEmpty);
  });

  test('isPressed reflects pressedActions', () {
    final state = InputState();
    expect(state.isPressed('jump'), isFalse);
    state.pressedActions.add('jump');
    expect(state.isPressed('jump'), isTrue);
  });

  test('handleKeyEvent sets the bound action on key-down and key-repeat, clears on key-up', () {
    final controller = InputController();

    final result = controller.handleKeyEvent(const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      logicalKey: LogicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    ));
    expect(result, KeyEventResult.handled);
    expect(controller.state.isPressed('left'), isTrue);

    controller.handleKeyEvent(const KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      logicalKey: LogicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    ));
    expect(controller.state.isPressed('left'), isTrue);

    controller.handleKeyEvent(const KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      logicalKey: LogicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    ));
    expect(controller.state.isPressed('left'), isFalse);
  });

  test('handleKeyEvent ignores keys with no binding', () {
    final controller = InputController();

    final result = controller.handleKeyEvent(const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyQ,
      logicalKey: LogicalKeyboardKey.keyQ,
      timeStamp: Duration.zero,
    ));

    expect(result, KeyEventResult.ignored);
    expect(controller.state.pressedActions, isEmpty);
  });

  test('setAxis writes to InputState.axisValues, read back via axis', () {
    final controller = InputController();
    controller.setAxis('moveX', 0.75);
    expect(controller.state.axis('moveX'), 0.75);
  });

  group('captureNextKeyDown', () {
    test('captures the next key-down, clears itself, and consumes the event', () {
      final controller = InputController();
      LogicalKeyboardKey? captured;
      controller.captureNextKeyDown = (key) => captured = key;

      final result = controller.handleKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ));

      expect(result, KeyEventResult.handled);
      expect(captured, LogicalKeyboardKey.keyW);
      expect(controller.captureNextKeyDown, isNull);
    });

    test('capturing an already-bound key does not also fire its old action', () {
      final controller = InputController(); // space is bound to "jump" by default
      controller.captureNextKeyDown = (_) {};

      controller.handleKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      ));

      expect(controller.state.isPressed('jump'), isFalse);
    });

    test('normal binding handling resumes once nothing is capturing', () {
      final controller = InputController();
      controller.captureNextKeyDown = (_) {};
      controller.handleKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ));

      final result = controller.handleKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: LogicalKeyboardKey.arrowLeft,
        timeStamp: Duration.zero,
      ));

      expect(result, KeyEventResult.handled);
      expect(controller.state.isPressed('left'), isTrue);
    });
  });
}
