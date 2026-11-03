import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('Entity packs and unpacks id and generation', () {
    final e = Entity.from(7, 3);
    expect(e.id, 7);
    expect(e.generation, 3);
    final big = Entity.from(4294967295, 2097151);
    expect(big.id, 4294967295);
    expect(big.generation, 2097151);
  });

  test('handles are distinct per incarnation and compare by value', () {
    expect(Entity.from(1, 0), Entity.from(1, 0));
    expect(Entity.from(1, 0) == Entity.from(1, 1), isFalse);
    expect(Entity.from(1, 0) == Entity.from(2, 0), isFalse);
  });

  test('entityOf reads the current generation and isCurrent tracks it', () {
    final world = _world();
    final id = world.spawn();
    final e = world.entityOf(id);
    expect(world.isCurrent(e), isTrue);
    world.destroy(id);
    expect(world.isCurrent(e), isFalse);
    final reused = world.spawn();
    expect(reused, id);
    expect(world.isCurrent(e), isFalse, reason: 'same id, different entity');
    expect(world.isCurrent(world.entityOf(reused)), isTrue);
  });

  test('entityOf refuses a dead id', () {
    final world = _world();
    final id = world.spawn();
    world.destroy(id);
    expect(() => world.entityOf(id), throwsStateError);
  });

  test('EntityRef get/set/has/remove chain on a live entity', () {
    final world = _world();
    final ref = world.ref(world.entityOf(world.spawn()));
    ref.set(Position(1, 2)).set(Velocity(3, 4));
    expect(ref.get<Position>()!.y, 2);
    expect(ref.has<Velocity>(), isTrue);
    ref.remove<Velocity>();
    expect(ref.has<Velocity>(), isFalse);
    expect(world.getComponent<Position>(ref.id)!.x, 1);
  });

  test('a stale EntityRef reads empty, ignores remove/destroy and refuses '
      'set, never touching the entity that reused the id', () {
    final world = _world();
    final id = world.spawn();
    final stale = world.ref(world.entityOf(id));
    stale.set(Position(1, 1));
    world.destroy(id);
    final reused = world.spawn();
    world.setComponent(reused, Position(9, 9));
    expect(stale.isAlive, isFalse);
    expect(stale.get<Position>(), isNull);
    expect(stale.has<Position>(), isFalse);
    expect(() => stale.set(Position(0, 0)), throwsStateError);
    stale.remove<Position>();
    stale.destroy();
    expect(world.entities.isAlive(reused), isTrue);
    expect(world.getComponent<Position>(reused)!.x, 9);
  });

  test('EntityRef.destroy removes the entity and is idempotent', () {
    final world = _world();
    final ref = world.ref(world.entityOf(world.spawn()));
    ref.set(Position(0, 0));
    ref.destroy();
    ref.destroy();
    expect(world.entities.count, 0);
    expect(world.componentsOf<Position>().length, 0);
  });

  test('EntityRef equality is per world and per incarnation', () {
    final w1 = _world();
    final w2 = _world();
    final e = w1.entityOf(w1.spawn());
    w2.spawn();
    expect(w1.ref(e), w1.ref(e));
    expect(w1.ref(e) == w2.ref(e), isFalse);
  });
}
