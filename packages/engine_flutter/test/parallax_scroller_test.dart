import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ParallaxScroller moves each layer by its own speed', () {
    final world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final scroller = ParallaxScroller.spawn(world, 'bg', const [
      ParallaxSpec('far', 0.5),
      ParallaxSpec('near', 1.5, zIndex: 10),
    ]);
    scroller
      ..scroll(world, 10)
      ..scroll(world, 10);

    final layers = world.storeOf<ParallaxLayer>();
    final pos = world.storeOf<Position>();
    final xs = {
      for (var i = 0; i < layers.length; i++)
        layers.denseAt(i).atlasId: pos.get(layers.entityAt(i))!.x,
    };
    expect(xs, {'bg_far': -10, 'bg_near': -30});
  });

  test('ParallaxSpec parses JSON with a default z', () {
    final s = ParallaxSpec.fromJson({'name': 'sky', 'speed': 0.1});
    expect((s.name, s.speed, s.zIndex), ('sky', 0.1, -100));
    expect(s.atlasId('bg'), 'bg_sky');
  });
}
