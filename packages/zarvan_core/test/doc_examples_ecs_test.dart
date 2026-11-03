// The samples in docs/concepts/ecs.md, executed so the guide cannot drift.
import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  test('spawn an entity and attach, read and check a component', () {
    final world = World(width: 800, height: 600);
    registerCoreComponents(world);
    final id = world.spawn();
    expect(id, isA<EntityId>());

    world.setComponent(id, Position(100, 100));
    final pos = world.getComponent<Position>(id);
    final has = world.hasComponent<Position>(id);
    final all = world.componentsOf<Position>();
    expect(pos!.x, 100);
    expect(all.length, 1);
    expect(has, isTrue);
    expect(world.componentsOf<Position>().has(world.spawn()), isFalse);
  });

  test('a system sees every matching entity each step', () {
    final world = World(width: 800, height: 600);
    registerCoreComponents(world);
    world.addSystem(MovementSystem());
    final id = world.spawn();
    world.componentsOf<Position>().set(id, Position(0, 0));
    world.componentsOf<Velocity>().set(id, Velocity(50, 0));

    world.step(1);
    expect(world.componentsOf<Position>().get(id)!.x, closeTo(50, 1e-9));
  });
}
