import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('SetVelocityAction', () {
    test('applies velocity to entity', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));

      final action = SetVelocityAction(id, 50, 30);
      action.apply(world);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 50);
      expect(vel.y, 30);
    });

    test('overwrites existing velocity', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(100, 100));

      final action = SetVelocityAction(id, -20, 40);
      action.apply(world);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, -20);
      expect(vel.y, 40);
    });

    test('creates Velocity component if entity does not have one', () {
      final world = World(width: 100, height: 100);
      registerCoreComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      // No Velocity component initially

      final action = SetVelocityAction(id, 50, 30);
      action.apply(world);

      // Action creates the Velocity component
      final vel = world.storeOf<Velocity>().get(id);
      expect(vel, isNotNull);
      expect(vel!.x, 50);
      expect(vel.y, 30);
    });
  });
}