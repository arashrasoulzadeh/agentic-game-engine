import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('component/hasComponent read through to the underlying store', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(1, 2));
    final view = WorldView(world);

    expect(view.hasComponent<Position>(id), isTrue);
    expect(view.component<Position>(id)!.x, 1);
    expect(view.hasComponent<Velocity>(id), isFalse);
    expect(view.component<Velocity>(id), isNull);
  });

  test('width/height/tick read through to the underlying World', () {
    final world = _buildWorld();
    world.addSystem(MovementSystem());
    world.step(0.016);
    world.step(0.016);

    final view = WorldView(world);
    expect(view.width, 500);
    expect(view.height, 500);
    expect(view.tick, 2);
  });

  test('entitiesWith yields every entity carrying the component', () {
    final world = _buildWorld();
    final a = world.spawn();
    final b = world.spawn();
    world.spawn(); // no Position
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Position>().set(b, Position(0, 0));

    final view = WorldView(world);
    expect(view.entitiesWith<Position>().toSet(), {a, b});
  });

  test('nearestWithPosition finds the closest match and respects exclude/maxDistance', () {
    final world = _buildWorld();
    final near = world.spawn();
    final far = world.spawn();
    final self = world.spawn();
    world.storeOf<Position>().set(near, Position(10, 0));
    world.storeOf<Position>().set(far, Position(100, 0));
    world.storeOf<Position>().set(self, Position(0, 0));

    final view = WorldView(world);
    expect(view.nearestWithPosition(0, 0, exclude: self), near);
    expect(
      view.nearestWithPosition(0, 0, exclude: self, maxDistance: 5),
      isNull,
    );
  });
}
