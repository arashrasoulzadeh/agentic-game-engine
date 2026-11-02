import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

bool get _assertsOn {
  var on = false;
  assert(on = true);
  return on;
}

/// n entities: all Position, evens Velocity, multiples of 3 Collider.
List<EntityId> _populate(World world, int n) {
  final ids = <EntityId>[];
  for (var i = 0; i < n; i++) {
    final id = world.spawn();
    ids.add(id);
    world.setComponent(id, Position(i.toDouble(), 0));
    if (i.isEven) world.setComponent(id, Velocity(i.toDouble(), 0));
    if (i % 3 == 0) world.setComponent(id, Collider(1));
  }
  return ids;
}

void main() {
  test('query yields every entity with the component, with its value', () {
    final world = _world();
    final ids = _populate(world, 7);
    final got = {for (final (id, p) in world.query<Position>()) id: p.x};
    expect(got.keys.toSet(), ids.toSet());
    for (var i = 0; i < ids.length; i++) {
      expect(got[ids[i]], i.toDouble());
    }
  });

  test('query2 equals a naive join, whichever collection is smaller', () {
    final world = _world();
    final ids = _populate(world, 20);
    final naive = {
      for (final id in ids)
        if (world.hasComponent<Position>(id) &&
            world.hasComponent<Velocity>(id))
          id,
    };
    final ab = {
      for (final (id, _, _) in world.query2<Position, Velocity>()) id,
    };
    final ba = {
      for (final (id, _, _) in world.query2<Velocity, Position>()) id,
    };
    expect(ab, naive);
    expect(ba, naive);
    expect(naive.length, 10);
    final (id, p, v) = world.query2<Position, Velocity>().first;
    expect(p.x, v.x, reason: 'values belong to the same entity: $id');
  });

  test('query3 equals a naive join for every choice of driving collection', () {
    final world = _world();
    final ids = _populate(world, 40);
    final naive = {
      for (final id in ids)
        if (world.hasComponent<Velocity>(id) &&
            world.hasComponent<Collider>(id))
          id,
    };
    expect(naive, isNotEmpty);
    Set<EntityId> ids3<A, B, C>() => {
      for (final r in world.query3<A, B, C>()) r.$1,
    };
    expect(ids3<Position, Velocity, Collider>(), naive);
    expect(ids3<Velocity, Position, Collider>(), naive);
    expect(ids3<Collider, Velocity, Position>(), naive);
    expect(ids3<Collider, Position, Velocity>(), naive);
    expect(ids3<Velocity, Collider, Position>(), naive);
    expect(ids3<Position, Collider, Velocity>(), naive);
  });

  test('empty collections and non-overlapping joins yield nothing', () {
    final world = _world();
    expect(world.query<Position>(), isEmpty);
    expect(world.query2<Position, Velocity>(), isEmpty);
    final a = world.spawn();
    final b = world.spawn();
    world.setComponent(a, Position(0, 0));
    world.setComponent(b, Velocity(0, 0));
    expect(world.query2<Position, Velocity>(), isEmpty);
    expect(world.query3<Position, Velocity, Collider>(), isEmpty);
  });

  test('results follow removals and destroys made between queries', () {
    final world = _world();
    final ids = _populate(world, 6);
    world.destroy(ids[0]);
    world.removeComponent<Velocity>(ids[2]);
    final got = {
      for (final (id, _, _) in world.query2<Position, Velocity>()) id,
    };
    expect(got, {ids[4]});
  });

  test('a query can be iterated twice and reflects the world each time', () {
    final world = _world();
    final ids = _populate(world, 3);
    final q = world.query<Position>();
    expect(q.length, 3);
    world.destroy(ids[1]);
    expect(q.length, 2);
  });

  test('queueing destroys on world.commands while iterating visits every '
      'entity (the immediate version skips)', () {
    final world = _world();
    final ids = _populate(world, 8);
    final visited = <EntityId>[];
    for (final (id, _) in world.query<Position>()) {
      visited.add(id);
      world.commands.destroy(id);
    }
    world.commands.apply();
    expect(visited.toSet(), ids.toSet());
    expect(world.entities.count, 0);
  });

  test('destroying while iterating trips the debug assert and points at '
      'world.commands', () {
    final world = _world();
    _populate(world, 4);
    expect(
      () {
        for (final (id, _) in world.query<Position>()) {
          world.destroy(id);
        }
      },
      _assertsOn
          ? throwsA(
              isA<AssertionError>().having(
                (e) => e.message.toString(),
                'message',
                contains('world.commands'),
              ),
            )
          : returnsNormally,
    );
  });

  test('mutating a non-driving collection is allowed', () {
    final world = _world();
    final ids = _populate(world, 6);
    for (final (id, _, _) in world.query2<Velocity, Position>()) {
      world.setComponent(id, Position(1, 1));
    }
    expect(world.getComponent<Position>(ids[0])!.x, 1);
  });
}
