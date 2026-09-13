import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(DashSystem());
  return world;
}

EntityId _spawn(World world, PlatformerController controller) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(500, 500));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<PlatformerController>().set(id, controller);
  return id;
}

void main() {
  test('dashSpeed 0 (default) means dash never fires', () {
    final world = _buildWorld();
    final controller = PlatformerController(facingSign: 1);
    final id = _spawn(world, controller);

    controller.dashRequested = true;
    world.step(0.016);

    expect(world.storeOf<Velocity>().get(id)!.x, 0);
  });

  test('a dash sets Velocity.x to dashSpeed * facingSign for its duration', () {
    final world = _buildWorld();
    final controller = PlatformerController(
      dashSpeed: 400,
      dashDurationSeconds: 0.1,
      facingSign: 1,
    );
    final id = _spawn(world, controller);
    final vel = world.storeOf<Velocity>().get(id)!;

    controller.dashRequested = true;
    world.step(0.04);
    expect(vel.x, 400);

    world.step(0.04); // still mid-dash (0.08s elapsed of 0.1s)
    expect(vel.x, 400);
    expect(controller.dashUsed, isTrue);
  });

  test('a dash in the facing-left direction is negative', () {
    final world = _buildWorld();
    final controller = PlatformerController(dashSpeed: 400, facingSign: -1);
    final id = _spawn(world, controller);

    controller.dashRequested = true;
    world.step(0.016);

    expect(world.storeOf<Velocity>().get(id)!.x, -400);
  });

  test('only one dash per ground contact: a second dashRequested after it expires is ignored', () {
    final world = _buildWorld();
    final controller = PlatformerController(
      dashSpeed: 400,
      dashDurationSeconds: 0.05,
      facingSign: 1,
    );
    _spawn(world, controller);

    controller.dashRequested = true;
    world.step(0.02); // dash starts: dashTimeRemaining = 0.05
    world.step(0.02); // still mid-dash: 0.05 - 0.02 = 0.03
    world.step(0.05); // expires: 0.03 - 0.05 <= 0
    expect(controller.dashTimeRemaining, lessThanOrEqualTo(0));
    expect(controller.dashUsed, isTrue);

    controller.dashRequested = true; // pressed again
    world.step(0.02);

    expect(controller.dashTimeRemaining, lessThanOrEqualTo(0),
        reason: 'dashUsed is still true (no ground contact reset it), so this request is ignored');
  });

  test('PlatformerInputSystem updates facingSign from horizontal input', () {
    final world = World(width: 2000, height: 2000);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    final id = world.spawn();
    final input = InputState();
    world.storeOf<Position>().set(id, Position(0, 0));
    world.storeOf<Velocity>().set(id, Velocity(0, 0));
    world.storeOf<InputState>().set(id, input);
    final controller = PlatformerController();
    world.storeOf<PlatformerController>().set(id, controller);
    world.addSystem(PlatformerInputSystem(id));

    input.pressedActions.add('left');
    world.step(0.016);
    expect(controller.facingSign, -1);

    input.pressedActions
      ..remove('left')
      ..add('right');
    world.step(0.016);
    expect(controller.facingSign, 1);
  });
}
