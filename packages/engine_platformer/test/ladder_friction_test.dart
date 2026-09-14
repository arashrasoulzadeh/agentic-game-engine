import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('PlatformerInputSystem groundFriction blending', () {
    test('groundFriction 1.0 (default/untagged tile) snaps velocity instantly', () {
      final world = _buildWorld();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(grounded: true);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(PlatformerInputSystem(id, moveSpeed: 100));

      input.pressedActions.add('right');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.x, 100);
    });

    test('groundFriction below 1.0 blends toward the target instead of snapping', () {
      final world = _buildWorld();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(grounded: true, groundFriction: 0.1);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(PlatformerInputSystem(id, moveSpeed: 100));

      input.pressedActions.add('right');
      world.step(0.016);

      final vx = world.storeOf<Velocity>().get(id)!.x;
      expect(vx, greaterThan(0));
      expect(vx, lessThan(100), reason: 'icy friction should slide toward the target, not snap');
    });

    test('a low groundFriction only slides while grounded, not airborne', () {
      final world = _buildWorld();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(grounded: false, groundFriction: 0.1);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(PlatformerInputSystem(id, moveSpeed: 100));

      input.pressedActions.add('right');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.x, 100);
    });
  });

  group('LadderSystem', () {
    World buildWithLadder() {
      final world = _buildWorld();
      world.addSystem(GravitySystem());
      return world;
    }

    test('climbSpeed 0 (default) is a no-op even while onLadder', () {
      final world = buildWithLadder();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(onLadder: true);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(LadderSystem(id));

      input.pressedActions.add('up');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, isNot(lessThan(0)));
    });

    test('holding up climbs (negative vel.y) while onLadder and climbSpeed > 0', () {
      final world = buildWithLadder();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 999));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(onLadder: true, climbSpeed: 80);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(LadderSystem(id));

      input.pressedActions.add('up');
      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, -80);
    });

    test('holding neither up nor down holds position on the ladder (vel.y = 0)', () {
      final world = buildWithLadder();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 999));
      world.storeOf<InputState>().set(id, input);
      final controller = PlatformerController(onLadder: true, climbSpeed: 80);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(LadderSystem(id));

      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 0);
    });

    test('not onLadder leaves velocity untouched (gravity still applies)', () {
      final world = buildWithLadder();
      final id = world.spawn();
      final input = InputState();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<InputState>().set(id, input);
      world.storeOf<Gravity>().set(id, Gravity());
      final controller = PlatformerController(onLadder: false, climbSpeed: 80);
      world.storeOf<PlatformerController>().set(id, controller);
      world.addSystem(LadderSystem(id));

      input.pressedActions.add('up');
      world.step(0.1);

      expect(world.storeOf<Velocity>().get(id)!.y, greaterThan(0));
    });
  });
}
