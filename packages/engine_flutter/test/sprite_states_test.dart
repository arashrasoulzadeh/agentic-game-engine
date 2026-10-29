import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late World world;
  late EntityId e;

  setUp(() {
    world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world
      ..addSystem(SpriteStateSystem())
      ..addSystem(AnimationSystem());
    e = world.spawn();
    world.storeOf<Position>().set(e, Position(0, 0));
    world.storeOf<Sprite>().set(e, Sprite('a_idle', '0'));
    world.storeOf<AnimationState>().set(
      e,
      AnimationState(AnimationClip('idle', ['0', '1'], loop: true)),
    );
    world.storeOf<SpriteStates>().set(
      e,
      SpriteStates({
        'idle': const SpriteClip(atlasId: 'a_idle', frames: 2, loop: true),
        'attack': const SpriteClip(atlasId: 'a_attack', frames: 3),
        'death': const SpriteClip(atlasId: 'a_death', frames: 2),
      }),
    );
  });

  test('a requested state swaps the sprite atlas, then returns to rest', () {
    playSpriteState(world, e, 'attack');
    world.step(0.01);
    expect(world.storeOf<Sprite>().get(e)!.atlasId, 'a_attack');
    for (var i = 0; i < 6; i++) {
      world.step(0.1);
    }
    expect(world.storeOf<SpriteStates>().get(e)!.current, 'idle');
    expect(world.storeOf<Sprite>().get(e)!.atlasId, 'a_idle');
  });

  test('hold states play to the last frame and stay there', () {
    playSpriteState(world, e, 'death');
    world.step(0.01);
    expect(spriteStateFinished(world, e, 'death'), isFalse);
    for (var i = 0; i < 10; i++) {
      world.step(0.2);
    }
    expect(spriteStateFinished(world, e, 'death'), isTrue);
    expect(world.storeOf<Sprite>().get(e)!.region, '1');

    playSpriteState(world, e, 'attack');
    world.step(0.5);
    expect(world.storeOf<SpriteStates>().get(e)!.current, 'death');
  });

  test('unknown states are ignored and the component round-trips JSON', () {
    playSpriteState(world, e, 'dance');
    world.step(0.01);
    expect(world.storeOf<SpriteStates>().get(e)!.current, 'idle');

    final back = SpriteStates.fromJson(
      world.storeOf<SpriteStates>().get(e)!.toJson(),
    );
    expect(back.clips['attack']!.atlasId, 'a_attack');
    expect(back.holdStates, {'death'});
  });
}
