import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sprite/AnimationState/InputState/ParallaxLayer serialize through World.toJson', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final spriteEntity = world.spawn();
    world.storeOf<Sprite>().set(spriteEntity, Sprite('atlas', 'idle'));

    final animEntity = world.spawn();
    world.storeOf<AnimationState>().set(
          animEntity,
          AnimationState(AnimationClip('idle', ['idle_0'])),
        );

    final inputEntity = world.spawn();
    world.storeOf<InputState>().set(inputEntity, InputState({'jump'}));

    final parallaxEntity = world.spawn();
    world.storeOf<ParallaxLayer>().set(parallaxEntity, ParallaxLayer('bg', 'sky'));

    final snapshot = world.toJson();
    final byId = {
      for (final e in snapshot['entities'] as List) (e as Map)['id']: e['components']
    };

    expect(byId[spriteEntity]['sprite']['atlasId'], 'atlas');
    expect(byId[animEntity]['animationState']['clip']['name'], 'idle');
    expect(byId[inputEntity]['inputState']['pressed'], ['jump']);
    expect(byId[parallaxEntity]['parallaxLayer']['atlasId'], 'bg');
  });
}
