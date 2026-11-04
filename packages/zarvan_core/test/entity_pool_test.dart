import 'package:test/test.dart';
import 'package:zarvan_core/zarvan_core.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

PooledEntity _bullet(EntityPool pool, World world, double x) {
  final b = pool.acquire();
  if (b.recycled) {
    world.componentsOf<Position>().get(b.id)!.x = x;
  } else {
    world.componentsOf<Position>().set(b.id, Position(x, 0));
    world.componentsOf<Velocity>().set(b.id, Velocity(1, 0));
  }
  return b;
}

void main() {
  test('a fresh pool hands out empty new entities', () {
    final world = _world();
    final pool = EntityPool(world);
    final b = pool.acquire();
    expect(b.recycled, isFalse);
    expect(world.componentsOf<Position>().has(b.id), isFalse);
    expect((pool.created, pool.recycled, pool.idle), (1, 0, 0));
  });

  test('a released entity comes back with the same component objects', () {
    final world = _world();
    final pool = EntityPool(world);
    final first = _bullet(pool, world, 5);
    final position = world.componentsOf<Position>().get(first.id)!;
    final velocity = world.componentsOf<Velocity>().get(first.id)!;
    pool.release(first.id);
    expect(pool.idle, 1);
    expect(world.entities.isAlive(first.id), isFalse);
    expect(world.componentsOf<Position>().has(first.id), isFalse);

    final again = _bullet(pool, world, 9);
    expect(again.recycled, isTrue);
    expect(
      identical(world.componentsOf<Position>().get(again.id), position),
      isTrue,
    );
    expect(
      identical(world.componentsOf<Velocity>().get(again.id), velocity),
      isTrue,
    );
    expect(position.x, 9);
    expect((pool.created, pool.recycled, pool.idle), (1, 1, 0));
  });

  test('recycled entities take part in queries like any other', () {
    final world = _world();
    final pool = EntityPool(world);
    final a = _bullet(pool, world, 1);
    pool.release(a.id);
    final b = _bullet(pool, world, 2);
    final seen = [for (final (id, p) in world.query<Position>()) (id, p.x)];
    expect(seen, [(b.id, 2.0)]);
    expect(world.componentsOf<Velocity>().has(b.id), isTrue);
  });

  test('maxIdle caps the stash; extra releases are just destroyed', () {
    final world = _world();
    final pool = EntityPool(world, maxIdle: 2);
    final all = [
      for (var i = 0; i < 5; i++) _bullet(pool, world, i.toDouble()),
    ];
    for (final b in all) {
      pool.release(b.id);
    }
    expect(pool.idle, 2);
    pool.clear();
    expect(pool.idle, 0);
  });

  test('releasing a dead or empty entity is a safe no-op', () {
    final world = _world();
    final pool = EntityPool(world);
    pool.release(9999);
    final empty = pool.acquire();
    pool.release(empty.id);
    pool.release(empty.id);
    expect(pool.idle, 0);
  });

  test('pooling a thousand bullets recycles instead of creating', () {
    final world = _world();
    final pool = EntityPool(world);
    for (var round = 0; round < 10; round++) {
      final batch = [for (var i = 0; i < 100; i++) _bullet(pool, world, 0)];
      for (final b in batch) {
        pool.release(b.id);
      }
    }
    expect(pool.created, 100);
    expect(pool.recycled, 900);
  });
}
