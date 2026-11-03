import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spawnFx plays once at its position and is cleaned up afterwards', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world
      ..addSystem(AnimationSystem())
      ..addSystem(OneShotFxSystem());

    final id = spawnFx(
      world,
      const FxClip('spark', 3, frameSeconds: 0.1),
      x: 12,
      y: 34,
      scale: 0.5,
    );
    final pos = world.componentsOf<Position>().get(id)!;
    expect((pos.x, pos.y), (12, 34));
    expect(world.componentsOf<Sprite>().get(id)!.scaleX, 0.5);

    world.step(0.05);
    expect(world.componentsOf<OneShotFx>().length, 1);
    for (var i = 0; i < 10; i++) {
      world.step(0.1);
    }
    expect(world.componentsOf<OneShotFx>().length, 0);
  });
}
