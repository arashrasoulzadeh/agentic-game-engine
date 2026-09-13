import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('MovementAnimationSet.fromSequences', () {
    test('builds idle/walk/jump clips from region naming conventions', () {
      final set = MovementAnimationSet.fromSequences(
        idleRegion: 'idle',
        walkPrefix: 'walk',
        walkFrameCount: 8,
        jumpPrefix: 'jump',
        jumpFrameCount: 4,
      );

      expect(set.idle.frameRegions, ['idle']);
      expect(set.walk.frameRegions, [
        'walk_0', 'walk_1', 'walk_2', 'walk_3', //
        'walk_4', 'walk_5', 'walk_6', 'walk_7',
      ]);
      expect(set.jump!.frameRegions, ['jump_0', 'jump_1', 'jump_2', 'jump_3']);
      expect(set.jump!.loop, isFalse);
    });

    test('jump is omitted when jumpPrefix/jumpFrameCount are not given', () {
      final set = MovementAnimationSet.fromSequences(
        idleRegion: 'idle',
        walkPrefix: 'walk',
        walkFrameCount: 2,
      );
      expect(set.jump, isNull);
    });
  });

  group('spawnPlayer/spawnEnemy with animations', () {
    test('spawnPlayer attaches MovementAnimationSet and initial AnimationState', () {
      final world = _buildWorld();
      final animations = MovementAnimationSet.fromSequences(
        idleRegion: 'idle',
        walkPrefix: 'walk',
        walkFrameCount: 2,
      );
      final id = spawnPlayer(
        world,
        x: 0,
        y: 0,
        input: InputState(),
        animations: animations,
      );

      expect(world.storeOf<MovementAnimationSet>().get(id), same(animations));
      expect(world.storeOf<AnimationState>().get(id)!.clip.name, 'idle');
    });

    test('spawnEnemy attaches MovementAnimationSet and initial AnimationState', () {
      final world = _buildWorld();
      final animations = MovementAnimationSet.fromSequences(
        idleRegion: 'enemy_idle',
        walkPrefix: 'enemy_walk',
        walkFrameCount: 2,
      );
      final id = spawnEnemy(
        world,
        x: 0,
        y: 0,
        behaviorId: 'patrol',
        animations: animations,
      );

      expect(world.storeOf<MovementAnimationSet>().get(id), same(animations));
      expect(world.storeOf<AnimationState>().get(id)!.clip.name, 'idle');
    });

    test('animations is optional -- no components attached when omitted', () {
      final world = _buildWorld();
      final id = spawnPlayer(world, x: 0, y: 0, input: InputState());
      expect(world.storeOf<MovementAnimationSet>().get(id), isNull);
      expect(world.storeOf<AnimationState>().get(id), isNull);
    });
  });
}
