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

  test(
      'a reused SpatialHash across ticks (perf: no longer rebuilt from scratch every '
      'tick) does not leak a stale pair from an earlier tick once entities move apart',
      () {
    // Regression coverage for CollisionSystem now reusing one
    // SpatialHash instance + its bucket Lists across ticks instead of
    // building a fresh one every tick -- clear() must actually empty
    // every bucket in place, not just look empty because a fresh Map
    // replaced it.
    final world = _buildWorld();
    final a = world.spawn();
    final b = world.spawn();
    final posA = Position(0, 0);
    final posB = Position(5, 0);
    world.storeOf<Position>().set(a, posA);
    world.storeOf<Collider>().set(a, Collider(10));
    world.storeOf<Position>().set(b, posB);
    world.storeOf<Collider>().set(b, Collider(10));

    var collisions = 0;
    world.events.on<CollisionEvent>((e) => collisions++);

    world.step(0); // colliding
    expect(collisions, greaterThan(0));
    collisions = 0;

    posB.x = 1000; // far away -- must not still "collide" via a stale bucket
    world.step(0);
    expect(collisions, 0,
        reason: 'moved apart; a stale bucket from tick 1 would wrongly still report a '
            'collision here');

    posB.x = 5; // back together
    world.step(0);
    expect(collisions, greaterThan(0), reason: 'must still detect real collisions after '
        'reuse, not just correctly report their absence');
  });

  test(
      'a reused SpatialHash correctly rebuilds (not just reuses stale cell-hashing '
      "math) when auto-sizing's cellSize legitimately changes between ticks", () {
    // Tick 1 has only small colliders (cellSize auto-sizes small).
    // Tick 2 introduces a large *overlapping* pair elsewhere in the
    // world, which only auto-sizing's larger cellSize can reliably
    // place in the same/adjacent broad-phase cell (same geometry as
    // the "auto-sizing catches..." test above). If CollisionSystem
    // insert()ed this tick's colliders into a `SpatialHash` still using
    // the *previous*, smaller cellSize's cell-hashing math (i.e. failed
    // to rebuild), this pair would be missed exactly the way the
    // "explicit cellSize can reproduce the miss" test demonstrates.
    final world = _buildWorld();
    final small1 = world.spawn();
    final small2 = world.spawn();
    world.storeOf<Position>().set(small1, Position(-500, -500));
    world.storeOf<Collider>().set(small1, Collider(10));
    world.storeOf<Position>().set(small2, Position(-500, -450));
    world.storeOf<Collider>().set(small2, Collider(10));

    var collisions = 0;
    world.events.on<CollisionEvent>((e) => collisions++);

    world.step(0); // cellSize auto-sizes to 20 (2*10); small1/small2 don't overlap
    expect(collisions, 0);

    // Remove the small pair and introduce a large overlapping pair --
    // next tick's auto-sized cellSize jumps to 200 (2*100).
    world.destroy(small1);
    world.destroy(small2);
    final bigA = world.spawn();
    final bigB = world.spawn();
    world.storeOf<Position>().set(bigA, Position(0, 0));
    world.storeOf<Collider>().set(bigA, Collider(100));
    world.storeOf<Position>().set(bigB, Position(150, 0));
    world.storeOf<Collider>().set(bigB, Collider(100));

    world.step(0);
    expect(collisions, greaterThan(0),
        reason: 'bigA/bigB truly overlap (distance 150 < combined radius 200) and '
            "auto-sizing's cellSize this tick (200) is large enough to place them "
            'within reach of the broad-phase -- a hash that failed to rebuild and kept '
            "using tick 1's cellSize (20) would miss this pair the same way the "
            '"explicit cellSize can reproduce the miss" test demonstrates');
  });
}
