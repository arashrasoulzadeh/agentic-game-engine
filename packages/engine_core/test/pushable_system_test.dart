import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  world.addSystem(PushableSystem());
  return world;
}

void main() {
  test('Pushable round-trips through toJson/fromJson', () {
    final decoded = Pushable.fromJson(Pushable(pushSpeed: 120).toJson());
    expect(decoded.pushSpeed, 120);
  });

  test('a pusher overlapping from the left pushes the crate rightward', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(0, 0));
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable(pushSpeed: 80));

    final pusher = world.spawn();
    world.storeOf<Position>().set(pusher, Position(85, 0)); // to the crate's left, overlapping
    world.storeOf<Collider>().set(pusher, Collider(10));

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, 80);
  });

  test('a pusher overlapping from the right pushes the crate leftward', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(0, 0));
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable(pushSpeed: 80));

    final pusher = world.spawn();
    world.storeOf<Position>().set(pusher, Position(115, 0));
    world.storeOf<Collider>().set(pusher, Collider(10));

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, -80);
  });

  test('nothing overlapping leaves the crate stationary', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(0, 0));
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable());

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, 0);
  });

  test('a pusher far above (not roughly level) does not push', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(0, 0));
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable());

    final jumper = world.spawn();
    world.storeOf<Position>().set(jumper, Position(100, -100)); // way above
    world.storeOf<Collider>().set(jumper, Collider(10));

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, 0);
  });

  test('pushed from both sides at once cancels out to no movement', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(0, 0));
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable());

    final left = world.spawn();
    world.storeOf<Position>().set(left, Position(85, 0));
    world.storeOf<Collider>().set(left, Collider(10));
    final right = world.spawn();
    world.storeOf<Position>().set(right, Position(115, 0));
    world.storeOf<Collider>().set(right, Collider(10));

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, 0);
  });

  test('velocity stops the instant nothing is pushing anymore (no momentum)', () {
    final world = _buildWorld();
    final crate = world.spawn();
    world.storeOf<Position>().set(crate, Position(100, 0));
    world.storeOf<Velocity>().set(crate, Velocity(80, 0)); // was moving
    world.storeOf<Collider>().set(crate, Collider(10));
    world.storeOf<Pushable>().set(crate, Pushable(pushSpeed: 80));
    // No pusher this tick.

    world.step(0.016);

    expect(world.storeOf<Velocity>().get(crate)!.x, 0);
  });
}
