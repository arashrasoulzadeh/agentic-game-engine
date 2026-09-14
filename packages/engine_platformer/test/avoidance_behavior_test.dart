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
  group('AvoidanceBehavior', () {
    test('pushes two overlapping AI entities apart, in addition to the inner behavior',
        () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register(
          'patrol',
          AvoidanceBehavior(
            PatrolBehavior(minX: -1000, maxX: 1000, speed: 50),
            avoidRadius: 40,
            avoidStrength: 80,
          ),
        );
      world.addSystem(AISystem(registry));

      final left = world.spawn();
      world.storeOf<Position>().set(left, Position(0, 0));
      world.storeOf<Velocity>().set(left, Velocity(0, 0));
      world.storeOf<AIState>().set(left, AIState('patrol', memory: {'dir': 1.0}));

      final right = world.spawn();
      world.storeOf<Position>().set(right, Position(10, 0));
      world.storeOf<Velocity>().set(right, Velocity(0, 0));
      world.storeOf<AIState>().set(right, AIState('patrol', memory: {'dir': 1.0}));

      world.step(0.1);

      // Both patrol right (PatrolBehavior's own +50), but the closer
      // together they are, the more the avoidance push pulls them
      // apart -- left should end up moving slower rightward (pushed
      // left) than right (pushed further right), not identically.
      final leftVx = world.storeOf<Velocity>().get(left)!.x;
      final rightVx = world.storeOf<Velocity>().get(right)!.x;
      expect(leftVx, lessThan(rightVx));
      expect(leftVx, lessThan(50), reason: 'pushed left, away from the entity at x=10');
      expect(rightVx, greaterThan(50), reason: 'pushed right, away from the entity at x=0');
    });

    test('does not push away from an entity without AIState (e.g. the player)', () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register(
          'patrol',
          AvoidanceBehavior(PatrolBehavior(minX: -1000, maxX: 1000, speed: 50)),
        );
      world.addSystem(AISystem(registry));

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(10, 0));
      // No AIState on the player -- not part of the "AI pack".

      final enemy = world.spawn();
      world.storeOf<Position>().set(enemy, Position(0, 0));
      world.storeOf<Velocity>().set(enemy, Velocity(0, 0));
      world.storeOf<AIState>().set(enemy, AIState('patrol', memory: {'dir': 1.0}));

      world.step(0.1);

      expect(world.storeOf<Velocity>().get(enemy)!.x, 50,
          reason: 'unaffected by the nearby player -- only PatrolBehavior\'s own speed');
    });

    test('no push beyond avoidRadius', () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register(
          'patrol',
          AvoidanceBehavior(
            PatrolBehavior(minX: -1000, maxX: 1000, speed: 50),
            avoidRadius: 20,
          ),
        );
      world.addSystem(AISystem(registry));

      final far = world.spawn();
      world.storeOf<Position>().set(far, Position(500, 0));
      world.storeOf<AIState>().set(far, AIState('patrol', memory: {'dir': 1.0}));

      final enemy = world.spawn();
      world.storeOf<Position>().set(enemy, Position(0, 0));
      world.storeOf<Velocity>().set(enemy, Velocity(0, 0));
      world.storeOf<AIState>().set(enemy, AIState('patrol', memory: {'dir': 1.0}));

      world.step(0.1);

      expect(world.storeOf<Velocity>().get(enemy)!.x, 50);
    });

    test('does nothing extra when the inner behavior alone is missing Position (delegates)',
        () {
      final world = _buildWorld();
      final registry = BehaviorRegistry()
        ..register('patrol', AvoidanceBehavior(PatrolBehavior(minX: 0, maxX: 100)));
      world.addSystem(AISystem(registry));

      final id = world.spawn();
      world.storeOf<AIState>().set(id, AIState('patrol'));
      // no Position set

      expect(() => world.step(0.1), returnsNormally);
    });
  });
}
