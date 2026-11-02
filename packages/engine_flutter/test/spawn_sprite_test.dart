import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spawnSprite places a sprite entity at the point', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final id = spawnSprite(world, 3, 4, 'atlas', 'hero');
    expect(world.getComponent<Position>(id)!.y, 4);
    expect(world.getComponent<Sprite>(id)!.atlasId, 'atlas');
    expect(world.getComponent<Sprite>(id)!.region, 'hero');
  });
}
