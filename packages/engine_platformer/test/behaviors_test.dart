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

    test('stops (does not throw) when follower or target is missing a Position', () {
      final world = _buildWorld();
      final target = world.spawn(); // no Position

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 0));
      world.storeOf<Velocity>().set(follower, Velocity(5, 0));
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

    test('requireLineOfSight: false (default) chases straight through a wall', () {
      final world = _buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 3,
              rows: 1,
              tileWidth: 40,
              tileHeight: 40,
              tiles: [0, 1, 0],
              solidTileIds: {1},
            ),
          );
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 20));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, speed: 40));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 20));
      world.storeOf<Velocity>().set(follower, Velocity(0, 0));
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(follower)!.x, 40);
    });

    test('requireLineOfSight: true stops chasing when a wall blocks sight', () {
      final world = _buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 3,
              rows: 1,
              tileWidth: 40,
              tileHeight: 40,
              tiles: [0, 1, 0],
              solidTileIds: {1},
            ),
          );
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 20));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, speed: 40, requireLineOfSight: true));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 20));
      world.storeOf<Velocity>().set(follower, Velocity(0, 0));
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(follower)!.x, 0);
    });

    test('requireLineOfSight: true still chases once sight is clear', () {
      final world = _buildWorld();
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(cols: 3, rows: 1, tileWidth: 40, tileHeight: 40, tiles: [0, 0, 0]),
          );
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(100, 20));

      final registry = BehaviorRegistry()
        ..register('follow', FollowBehavior(target: target, speed: 40, requireLineOfSight: true));
      world.addSystem(AISystem(registry));

      final follower = world.spawn();
      world.storeOf<Position>().set(follower, Position(0, 20));
      world.storeOf<Velocity>().set(follower, Velocity(0, 0));
      world.storeOf<AIState>().set(follower, AIState('follow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(follower)!.x, 40);
    });
  });

  group('PathFollowBehavior', () {
    test('walks toward the first waypoint, then advances once arrived', () {
      final world = _buildWorld();
      final path = [PathPoint(50, 0), PathPoint(100, 0)];
      final registry = BehaviorRegistry()
        ..register('pathFollow', PathFollowBehavior(path, speed: 40, arriveDistance: 5));
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<AIState>().set(id, AIState('pathFollow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(id)!.x, 40, reason: 'heading toward the first waypoint');
    });

    test('advances to the next waypoint once within arriveDistance', () {
      final world = _buildWorld();
      final path = [PathPoint(2, 0), PathPoint(100, 0)];
      final behavior = PathFollowBehavior(path, speed: 40, arriveDistance: 5);
      final registry = BehaviorRegistry()..register('pathFollow', behavior);
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0)); // already within arriveDistance of waypoint 1
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<AIState>().set(id, AIState('pathFollow'));

      world.step(0.016);
      expect(behavior.currentTarget, path[1]);
      expect(world.storeOf<Velocity>().get(id)!.x, 40, reason: 'now heading toward waypoint 2');
    });

    test('stops once the last waypoint is reached', () {
      final world = _buildWorld();
      final path = [PathPoint(2, 0)];
      final behavior = PathFollowBehavior(path, speed: 40, arriveDistance: 5);
      final registry = BehaviorRegistry()..register('pathFollow', behavior);
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<AIState>().set(id, AIState('pathFollow'));

      world.step(0.016);
      expect(behavior.currentTarget, isNull);
      expect(world.storeOf<Velocity>().get(id)!.x, 0);
    });

    test('an empty path stops immediately', () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()..register('pathFollow', PathFollowBehavior(const []));
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(5, 0));
      world.storeOf<AIState>().set(id, AIState('pathFollow'));

      world.step(0.016);
      expect(world.storeOf<Velocity>().get(id)!.x, 0);
    });
  });
}
