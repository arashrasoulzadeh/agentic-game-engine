import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('hitTestButton finds a Button entity whose Collider contains the point', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(100, 100));
    world.storeOf<Collider>().set(id, Collider(20));
    world.storeOf<Button>().set(id, Button('play'));

    expect(hitTestButton(world, 105, 95), id);
  });

  test('hitTestButton returns null outside every button\'s radius', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(100, 100));
    world.storeOf<Collider>().set(id, Collider(20));
    world.storeOf<Button>().set(id, Button('play'));

    expect(hitTestButton(world, 200, 200), isNull);
  });

  test('hitTestButton ignores a Button entity missing Position or Collider', () {
    final world = _buildWorld();
    final noPosition = world.spawn();
    world.storeOf<Collider>().set(noPosition, Collider(999));
    world.storeOf<Button>().set(noPosition, Button('play'));

    expect(hitTestButton(world, 0, 0), isNull);
  });

  test('hitTestButton prefers the most-recently-spawned overlapping button', () {
    final world = _buildWorld();
    final under = world.spawn();
    world.storeOf<Position>().set(under, Position(50, 50));
    world.storeOf<Collider>().set(under, Collider(100));
    world.storeOf<Button>().set(under, Button('under'));

    final over = world.spawn();
    world.storeOf<Position>().set(over, Position(50, 50));
    world.storeOf<Collider>().set(over, Collider(100));
    world.storeOf<Button>().set(over, Button('over'));

    expect(hitTestButton(world, 50, 50), over);
  });

  test('Button round-trips through toJson/fromJson', () {
    final decoded = Button.fromJson(Button('quit').toJson());
    expect(decoded.actionId, 'quit');
  });
}
