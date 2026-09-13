import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld({double? cellSize}) {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  world.addSystem(CollisionSystem(cellSize: cellSize));
  return world;
}

void main() {
  test('detects a colliding pair with default (auto-sized) cellSize', () {
    final world = _buildWorld();
    final a = world.spawn();
    final b = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(10));
    world.storeOf<Position>().set(b, Position(5, 0));
    world.storeOf<Collider>().set(b, Collider(10));

    var collided = false;
    world.events.on<CollisionEvent>((e) => collided = true);
    world.step(0);

    expect(collided, isTrue);
  });

  test('auto-sizing catches a large-radius pair a small fixed cellSize would miss', () {
    // Two large colliders (radius 100 each, so minDist 200) placed 3
    // cells apart under a small fixed cellSize (50) -- more than 1 cell
    // away, so the broad-phase's same+adjacent-cell search would miss
    // them entirely with a naive fixed cellSize that doesn't account
    // for collider size. Auto-sizing (2*maxRadius = 200) puts them in
    // the same cell instead.
    final world = _buildWorld(); // no explicit cellSize -> auto
    final a = world.spawn();
    final b = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(100));
    world.storeOf<Position>().set(b, Position(150, 0));
    world.storeOf<Collider>().set(b, Collider(100));

    var collided = false;
    world.events.on<CollisionEvent>((e) => collided = true);
    world.step(0);

    expect(collided, isTrue);
  });

  test('an explicit cellSize can reproduce the miss auto-sizing avoids', () {
    // Same geometry as above, but forcing a too-small fixed cellSize
    // demonstrates why auto-sizing is the safer default -- this is
    // deliberately exercising the failure mode, not asserting desired
    // behavior.
    final world = _buildWorld(cellSize: 50);
    final a = world.spawn();
    final b = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(100));
    world.storeOf<Position>().set(b, Position(150, 0));
    world.storeOf<Collider>().set(b, Collider(100));

    var collided = false;
    world.events.on<CollisionEvent>((e) => collided = true);
    world.step(0);

    expect(collided, isFalse);
  });

  test('an empty world (no colliders) does not throw', () {
    final world = _buildWorld();
    expect(() => world.step(0.016), returnsNormally);
  });

  test('a single collider (no pairs possible) does not throw', () {
    final world = _buildWorld();
    final a = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(5));

    expect(() => world.step(0.016), returnsNormally);
  });
}
