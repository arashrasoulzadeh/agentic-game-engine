import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:engine_platformer/src/ai/velocity_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setVelocityX', () {
    late World world;

    setUp(() {
      world = World(width: 500, height: 500);
      registerCoreComponents(world);
      registerPlatformerComponents(world);
    });

    test('sets the x component, preserving an existing y component', () {
      final id = world.spawn();
      world.storeOf<Velocity>().set(id, Velocity(0, -250));

      setVelocityX(world, id, 40);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 40);
      expect(vel.y, -250, reason: 'vertical velocity (e.g. mid-jump/fall) must not be clobbered');
    });

    test('defaults y to 0 for an entity with no existing Velocity', () {
      final id = world.spawn();

      setVelocityX(world, id, 25);

      final vel = world.storeOf<Velocity>().get(id)!;
      expect(vel.x, 25);
      expect(vel.y, 0);
    });
  });
}
