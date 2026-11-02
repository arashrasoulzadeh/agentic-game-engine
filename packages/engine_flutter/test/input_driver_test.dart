import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('press holds an action until release', () {
    final state = InputState();
    final input = InputDriver(state, tick: (_) {});
    input.press('jump');
    expect(state.isPressed('jump'), isTrue);
    input.release('jump');
    expect(state.isPressed('jump'), isFalse);
    input.release('jump');
  });

  test('tap holds the action for exactly the ticks it runs, then lets go', () {
    final state = InputState();
    final heldDuring = <bool>[];
    final input = InputDriver(
      state,
      tick: (n) {
        for (var i = 0; i < n; i++) {
          heldDuring.add(state.isPressed('right'));
        }
      },
    );
    input.tap('right', ticks: 3);
    expect(heldDuring, [true, true, true]);
    expect(state.isPressed('right'), isFalse);
  });

  test('tap releases even when a tick throws', () {
    final state = InputState();
    final input = InputDriver(state, tick: (_) => throw StateError('boom'));
    expect(() => input.tap('a'), throwsStateError);
    expect(state.isPressed('a'), isFalse);
  });

  test('axes and releaseAll', () {
    final state = InputState();
    final input = InputDriver(state, tick: (_) {});
    input.setAxis('moveX', 0.5);
    input.press('left');
    expect(state.axis('moveX'), 0.5);
    input.releaseAll();
    expect(state.axis('moveX'), 0);
    expect(state.pressedActions, isEmpty);
  });
}
