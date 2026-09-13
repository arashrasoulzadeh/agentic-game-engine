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

    test('does not create an AnimationTransition when crossfadeSeconds is 0 (default)', () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      final id = world.spawn();
      final idle = AnimationClip('idle', ['idle_0']);
      final walk = AnimationClip('walk', ['walk_0']);
      world.storeOf<MovementAnimationSet>().set(id, MovementAnimationSet(idle: idle, walk: walk));
      world.storeOf<Sprite>().set(id, Sprite('atlas', 'idle_0'));
      world.storeOf<AnimationState>().set(id, AnimationState(idle));
      world.storeOf<Velocity>().set(id, Velocity(50, 0)); // triggers idle -> walk

      world.step(0.016);

      expect(world.storeOf<AnimationTransition>().has(id), isFalse);
    });

    test('snapshots the outgoing Sprite frame into an AnimationTransition when crossfading', () {
      final world = _buildWorld();
      world.addSystem(MovementAnimationSystem());
      final id = world.spawn();
      final idle = AnimationClip('idle', ['idle_0']);
      final walk = AnimationClip('walk', ['walk_0']);
      world.storeOf<MovementAnimationSet>().set(id, MovementAnimationSet(idle: idle, walk: walk));
      world.storeOf<Sprite>().set(id, Sprite('atlas', 'idle_0', scaleX: 2, scaleY: 2, zIndex: 3));
      world.storeOf<AnimationState>().set(id, AnimationState(idle, crossfadeSeconds: 0.2));
      world.storeOf<Velocity>().set(id, Velocity(50, 0)); // triggers idle -> walk

      world.step(0.016);

      final transition = world.storeOf<AnimationTransition>().get(id);
      expect(transition, isNotNull);
      expect(transition!.atlasId, 'atlas');
      expect(transition.region, 'idle_0', reason: 'snapshot of the outgoing frame');
      expect(transition.scaleX, 2);
      expect(transition.scaleY, 2);
      expect(transition.zIndex, 3);
      expect(transition.remainingSeconds, 0.2);
      expect(transition.totalSeconds, 0.2);

      // crossfadeSeconds carries forward onto the new AnimationState.
      expect(world.storeOf<AnimationState>().get(id)!.crossfadeSeconds, 0.2);
    });
  });

  group('AnimationTransitionSystem', () {
    test('counts remainingSeconds down and removes the component at 0', () {
      final world = _buildWorld();
      world.addSystem(AnimationTransitionSystem());
      final id = world.spawn();
      world.storeOf<AnimationTransition>().set(
            id,
            AnimationTransition('atlas', 'idle_0', remainingSeconds: 0.3, totalSeconds: 0.3),
          );

      world.step(0.2);
      expect(world.storeOf<AnimationTransition>().get(id)!.remainingSeconds, closeTo(0.1, 0.001));

      world.step(0.2);
      expect(world.storeOf<AnimationTransition>().has(id), isFalse);
    });
  });

  group('AnimationTransition.alpha', () {
    test('fades from 1 to 0 as remainingSeconds counts down', () {
      final full = AnimationTransition('a', 'r', remainingSeconds: 0.3, totalSeconds: 0.3);
      expect(full.alpha, 1);

      final half = AnimationTransition('a', 'r', remainingSeconds: 0.15, totalSeconds: 0.3);
      expect(half.alpha, closeTo(0.5, 0.001));

      final done = AnimationTransition('a', 'r', remainingSeconds: 0, totalSeconds: 0.3);
      expect(done.alpha, 0);
    });

    test('totalSeconds <= 0 reads as already-finished rather than dividing by zero', () {
      final transition = AnimationTransition('a', 'r', remainingSeconds: 0, totalSeconds: 0);
      expect(transition.alpha, 0);
    });
  });
}
