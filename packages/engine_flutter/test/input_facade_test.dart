import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('justPressed and justReleased fire for exactly one frame', () {
    final state = InputState();
    final input = Input(state);
    input.update();
    expect(input.justPressed('jump'), isFalse);

    state.pressedActions.add('jump');
    input.update();
    expect([input.justPressed('jump'), input.isDown('jump')], [true, true]);

    input.update();
    expect([input.justPressed('jump'), input.isDown('jump')], [false, true]);

    state.pressedActions.remove('jump');
    input.update();
    expect([input.justReleased('jump'), input.isDown('jump')], [true, false]);
    input.update();
    expect(input.justReleased('jump'), isFalse);
  });

  test('a press and release between updates is invisible, by design', () {
    final state = InputState();
    final input = Input(state)..update();
    state.pressedActions.add('a');
    state.pressedActions.remove('a');
    input.update();
    expect(input.justPressed('a'), isFalse);
  });

  test('axis prefers analog, else composes from actions', () {
    final state = InputState();
    final input = Input(state);
    state.pressedActions.add('right');
    input.update();
    expect(input.axis('moveX', negative: 'left', positive: 'right'), 1);
    state.pressedActions.add('left');
    input.update();
    expect(input.axis('moveX', negative: 'left', positive: 'right'), 0);
    state.axisValues['moveX'] = -0.5;
    expect(input.axis('moveX', negative: 'left', positive: 'right'), -0.5);
    state.axisValues['moveX'] = 3;
    expect(input.axis('moveX'), 1);
  });
}
