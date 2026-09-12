import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('PatrolBehavior', () {
    test('walks toward maxX, then flips direction at the bound', () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register('patrol', PatrolBehavior(minX: 0, maxX: 100, speed: 50));
      world.addSystem(AISystem(registry));
      world.addSystem(MovementSystem());

      final id = world.spawn();
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<AIState>().set(id, AIState('patrol', memory: {'dir': 1.0}));

      // AISystem runs before MovementSystem, so a behavior's decide()
      // sees the position as of the *start* of this tick (last tick's
      // resolved movement) — placing the entity already at the bound,
      // not "about to reach it", is what triggers an immediate flip.
      world.storeOf<Position>().set(id, Position(100, 0));

      world.step(0.1);
      final state = world.storeOf<AIState>().get(id)!;
      expect(state.memory['dir'], -1.0);
      expect(world.storeOf<Velocity>().get(id)!.x, -50);
    });

    test('does nothing for an entity missing Position/AIState data', () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register('patrol', PatrolBehavior(minX: 0, maxX: 100));
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<AIState>().set(id, AIState('patrol'));
      // no Position set

      expect(() => world.step(0.1), returnsNormally);
    });
  });

  group('FollowBehavior', () {
    test('moves toward the target on the x axis only', () {
      final world = _buildWorld();
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(200, 0));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, speed: 40));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 0));
      world.storeOf<Velocity>().set(follower, Velocity(0, -999)); // e.g. falling
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(follower)!;
      expect(vel.x, 40);
      expect(vel.y, -999, reason: 'FollowBehavior must not touch vertical velocity');
    });

    test('stops once within stopDistance', () {
      final world = _buildWorld();
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(2, 0));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, stopDistance: 5));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 0));
      world.storeOf<Velocity>().set(follower, Velocity(0, 0));
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(follower)!.x, 0);
    });

    test('stops once outside maxDistance', () {
      final world = _buildWorld();
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(1000, 0));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, maxDistance: 50));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 0));
      world.storeOf<Velocity>().set(follower, Velocity(0, 0));
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(follower)!.x, 0);
    });
  });
}
