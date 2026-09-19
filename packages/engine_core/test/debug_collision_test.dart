import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('Debug collision groups', () {
    test('simple collision group check', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(0, 0));
      world.storeOf<Velocity>().set(a, Velocity(10, 0));
      world.storeOf<Collider>().set(a, Collider(10, collisionGroup: 1, collisionMask: 1));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(5, 0)); // overlapping initially
      world.storeOf<Velocity>().set(b, Velocity(-10, 0));
      world.storeOf<Collider>().set(b, Collider(10, collisionGroup: 2, collisionMask: 2));

      world.addSystem(CollisionSystem());

      world.step(0); // dt=0, no movement

      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;
      print('velA.x = ${velA.x}, velB.x = ${velB.x}');
      
      // Should NOT collide (different groups), so velocities unchanged
      expect(velA.x, 10);
      expect(velB.x, -10);
    });

    test('matching groups collide', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(0, 0));
      world.storeOf<Velocity>().set(a, Velocity(5, 0));
      world.storeOf<Collider>().set(a, Collider(10, collisionGroup: 1, collisionMask: 1));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(5, 0)); // overlapping
      world.storeOf<Velocity>().set(b, Velocity(-3, 2));
      world.storeOf<Collider>().set(b, Collider(10, collisionGroup: 1, collisionMask: 1));

      world.addSystem(CollisionSystem());

      world.step(0);

      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;
      print('velA = $velA, velB = $velB');
      
      expect(velA.x, -3);
      expect(velA.y, 2);
      expect(velB.x, 5);
      expect(velB.y, 0);
    });
  });
}