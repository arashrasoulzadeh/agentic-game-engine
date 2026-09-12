import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('FacingSystem', () {
    test('flips scaleX positive when moving right, negative when moving left', () {
      final world = _buildWorld();
      world.addSystem(FacingSystem());
      final id = world.spawn();
      world.storeOf<Sprite>().set(id, Sprite('atlas', 'idle', scaleX: -1));
      world.storeOf<Velocity>().set(id, Velocity(50, 0));

      world.step(0.016);
      expect(world.storeOf<Sprite>().get(id)!.scaleX, 1);

      world.storeOf<Velocity>().set(id, Velocity(-50, 0));
      world.step(0.016);
      expect(world.storeOf<Sprite>().get(id)!.scaleX, -1);
    });

    test('holds the last facing while idle instead of resetting', () {
      final world = _buildWorld();
      world.addSystem(FacingSystem());
      final id = world.spawn();
      world.storeOf<Sprite>().set(id, Sprite('atlas', 'idle', scaleX: 1));
      world.storeOf<Velocity>().set(id, Velocity(-50, 0));
      world.step(0.016);
      expect(world.storeOf<Sprite>().get(id)!.scaleX, -1);

      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.step(0.016);
      expect(world.storeOf<Sprite>().get(id)!.scaleX, -1);
    });
  });

  group('MovementAnimationSystem', () {
    test('switches between idle and walk based on horizontal speed', () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      final id = world.spawn();
      final idle = AnimationClip('idle', ['idle_0']);
      final walk = AnimationClip('walk', ['walk_0', 'walk_1']);
      world.storeOf<MovementAnimationSet>().set(
            id,
            MovementAnimationSet(idle: idle, walk: walk, moveThreshold: 5),
          );
      world.storeOf<Velocity>().set(id, Velocity(0, 0));

      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.name, 'idle');

      world.storeOf<Velocity>().set(id, Velocity(50, 0));
      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.name, 'walk');
    });

    test('uses the jump clip while airborne, when provided', () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      final id = world.spawn();
      final idle = AnimationClip('idle', ['idle_0']);
      final walk = AnimationClip('walk', ['walk_0']);
      final jump = AnimationClip('jump', ['jump_0']);
      world.storeOf<MovementAnimationSet>().set(
            id,
            MovementAnimationSet(idle: idle, walk: walk, jump: jump),
          );
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<PlatformerController>().set(
            id,
            PlatformerController(grounded: false),
          );

      world.step(0.016);
      expect(world.storeOf<AnimationState>().get(id)!.clip.name, 'jump');
    });

    test('does not reset an already-playing clip of the same name', () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      final id = world.spawn();
      final walk = AnimationClip('walk', ['walk_0', 'walk_1']);
      world.storeOf<MovementAnimationSet>().set(
            id,
            MovementAnimationSet(idle: AnimationClip('idle', ['i']), walk: walk),
          );
      world.storeOf<Velocity>().set(id, Velocity(50, 0));
      world.storeOf<AnimationState>().set(
            id,
            AnimationState(walk, frameIndex: 1, elapsed: 0.05),
          );

      world.step(0.016);
      final state = world.storeOf<AnimationState>().get(id)!;
      expect(state.frameIndex, 1, reason: 'should not have reset playback');
      expect(state.elapsed, 0.05);
    });
  });
}
