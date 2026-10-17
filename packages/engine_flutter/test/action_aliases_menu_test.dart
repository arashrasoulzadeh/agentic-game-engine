import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the keyboard remap menu labels actions with their alias', () {
    final input = InputController(
      bindings: {LogicalKeyboardKey.space: 'action_0', LogicalKeyboardKey.keyZ: 'action_1'},
      aliases: ActionAliases({'action_0': 'Jump'}),
    );
    final labels = RemapMenuScene(input, ['action_0', 'action_1'], onDone: () => throw 0)
        .buttons()
        .map((b) => b.label)
        .toList();
    expect(labels[0], startsWith('JUMP:'));
    expect(labels[1], startsWith('ACTION 1:'));
  });

  test('the gamepad remap menu uses the same aliases', () {
    final input = InputController(aliases: ActionAliases({'action_0': 'Jump'}));
    final pad = GamepadController(input: input, buttonBindings: {0: 'action_0'});
    final labels =
        GamepadRemapMenuScene(pad, ['action_0'], onDone: () => throw 0).buttons().map((b) => b.label);
    expect(labels.first, startsWith('JUMP:'));
  });

  test('aliases default to empty and never change the stored action ids', () {
    final input = InputController();
    expect(input.aliases.hasAlias('jump'), isFalse);
    input.aliases.set('jump', 'Leap');
    expect(input.bindings[LogicalKeyboardKey.space], 'jump');
  });
}
