import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  World buildWorld() {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(AnimationSystem());
    return world;
  }

  test('advances frame after frameDurationSeconds elapses', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
          id,
          AnimationState(
            AnimationClip('walk', ['frame0', 'frame1', 'frame2'],
                frameDurationSeconds: 0.1),
          ),
        );

    world.step(0.05); // not yet a full frame
    expect(world.storeOf<Sprite>().get(id)!.region, 'frame0');

    world.step(0.06); // total 0.11 -> advances one frame
    expect(world.storeOf<Sprite>().get(id)!.region, 'frame1');
  });

  test('loops back to frame 0 when loop is true', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
          id,
          AnimationState(
            AnimationClip('walk', ['frame0', 'frame1'],
                frameDurationSeconds: 0.1, loop: true),
            frameIndex: 1,
          ),
        );

    world.step(0.1);
    expect(world.storeOf<Sprite>().get(id)!.region, 'frame0');
  });

  test('stops on the last frame when loop is false', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    final state = AnimationState(
      AnimationClip('hit', ['frame0', 'frame1'],
          frameDurationSeconds: 0.1, loop: false),
      frameIndex: 1,
    );
    world.storeOf<AnimationState>().set(id, state);

    world.step(0.1);
    expect(world.storeOf<Sprite>().get(id)!.region, 'frame1');
    expect(state.playing, isFalse);
  });

  test('name identifies this system in World.systemOrder', () {
    final world = buildWorld();
    expect(world.systemOrder, contains('animation'));
  });

  test('AnimationState round-trips through toJson/fromJson', () {
    final clip = AnimationClip('walk', ['a', 'b'], frameDurationSeconds: 0.2);
    final state = AnimationState(clip, frameIndex: 1, elapsed: 0.05);
    final restored = AnimationState.fromJson(state.toJson());
    expect(restored.clip.name, 'walk');
    expect(restored.clip.frameRegions, ['a', 'b']);
    expect(restored.frameIndex, 1);
    expect(restored.elapsed, 0.05);
  });

  test('writes each frame\'s offsetX/offsetY onto Sprite as it advances', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0'));
    world.storeOf<AnimationState>().set(
          id,
          AnimationState(
            AnimationClip(
              'walk',
              ['frame0', 'frame1'],
              frameDurationSeconds: 0.1,
              frameOffsetsX: [2, -3],
              frameOffsetsY: [10, 25],
            ),
          ),
        );

    world.step(0); // AnimationSystem only writes region/offset on a step
    final sprite = world.storeOf<Sprite>().get(id)!;
    expect(sprite.offsetX, 2);
    expect(sprite.offsetY, 10);

    world.step(0.1);
    expect(sprite.offsetX, -3);
    expect(sprite.offsetY, 25);
  });

  test('offsetX/offsetY default to 0 for a clip with no frameOffsets', () {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'frame0', offsetY: 99));
    world.storeOf<AnimationState>().set(
          id,
          AnimationState(AnimationClip('idle', ['frame0'], frameDurationSeconds: 0.1)),
        );

    // A clip with null frameOffsets resets a Sprite's offset back to 0
    // every tick it's driven, same as it always wrote `region` outright
    // -- AnimationSystem owns both once an AnimationState is attached.
    world.step(0);
    expect(world.storeOf<Sprite>().get(id)!.offsetY, 0);
  });
}
