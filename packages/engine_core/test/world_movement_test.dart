import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  World w() {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    return world;
  }

  test('move shifts position and ignores entities without one', () {
    final world = w();
    final id = world.spawnAt(1, 1);
    expect(world.move(id, 2, -1), isTrue);
    expect(world.getComponent<Position>(id)!.x, 3);
    expect(world.move(world.spawn(), 1, 1), isFalse);
  });

  test('moveToward steps, never overshoots, reports arrival', () {
    final world = w();
    final id = world.spawnAt(0, 0);
    expect(world.moveToward(id, 10, 0, 4), isFalse);
    expect(world.getComponent<Position>(id)!.x, 4);
    expect(world.moveToward(id, 10, 0, 4), isFalse);
    expect(world.moveToward(id, 10, 0, 4), isTrue);
    expect(world.getComponent<Position>(id)!.x, 10);
    expect(world.moveToward(id, 10, 0, 4), isTrue);
  });

  test('aimVelocity points at the target and carries over movement', () {
    final world = w();
    final id = world.spawnAt(0, 0);
    world.aimVelocity(id, 0, 10, 5);
    final v = world.getComponent<Velocity>(id)!;
    expect([v.x, v.y], [0, 5]);
    world.move(id, 0, 10);
    world.aimVelocity(id, 0, 10, 5);
    expect(world.getComponent<Velocity>(id)!.y, 0);
  });
}
