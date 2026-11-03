import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wasd adds keys for the same actions without changing the defaults', () {
    final plain = InputController.defaultBindings();
    final wasd = InputController.defaultBindings(wasd: true);
    expect(wasd.length, plain.length + 4);
    expect(wasd[LogicalKeyboardKey.keyA], 'left');
    expect(wasd[LogicalKeyboardKey.arrowLeft], 'left');
    expect(plain.containsKey(LogicalKeyboardKey.keyA), isFalse);
  });

  test('bind replaces a key\'s old action; keysFor lists the keys', () {
    final c = InputController();
    c.bind(LogicalKeyboardKey.space, 'fire');
    expect(c.bindings[LogicalKeyboardKey.space], 'fire');
    expect(c.keysFor('jump'), isEmpty);
    c.bindAll('jump', [LogicalKeyboardKey.keyZ, LogicalKeyboardKey.keyX]);
    expect(c.keysFor('jump'), [
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.keyX,
    ]);
  });

  test('unbindAction removes all its keys and releases a held action', () {
    final c = InputController(
      bindings: InputController.defaultBindings(wasd: true),
    );
    c.setAction('left', true);
    c.unbindAction('left');
    expect(c.keysFor('left'), isEmpty);
    expect(c.state.isPressed('left'), isFalse);
    expect(c.bindings[LogicalKeyboardKey.arrowRight], 'right');
  });
}
