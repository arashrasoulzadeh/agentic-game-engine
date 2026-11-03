import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sprite that moves, set up in a few lines with GameBuilder', () {
    final game = GameBuilder.create(
      width: 320,
      height: 240,
      register: [registerFlutterComponents],
    );
    final id = game.spawn([
      Position(0, 0),
      Velocity(60, 0),
      Sprite('atlas', 'ball'),
    ]);
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    expect(game.world.getComponent<Position>(id)!.x, closeTo(60, 1));
    expect(game.world.getComponent<Sprite>(id)!.region, 'ball');
    expect(game.world.components.serializeEntity(id), contains('sprite'));
  });
}
