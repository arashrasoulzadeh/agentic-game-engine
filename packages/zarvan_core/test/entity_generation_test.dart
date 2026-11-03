import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  test('a fresh entity is generation 0 and current', () {
    final em = EntityManager();
    final id = em.create();
    expect(em.generationOf(id), 0);
    expect(em.isCurrent(id, 0), isTrue);
    expect(em.generationOf(99), 0, reason: 'unknown ids read as 0');
  });

  test('destroying bumps the generation, so a stale handle is not current', () {
    final em = EntityManager();
    final id = em.create();
    final seen = em.generationOf(id);
    em.destroy(id);
    expect(em.isCurrent(id, seen), isFalse);

    final reused = em.create();
    expect(reused, id, reason: 'same slot');
    expect(em.isAlive(id), isTrue, reason: 'raw aliveness cannot tell');
    expect(em.isCurrent(id, seen), isFalse);
    expect(em.isCurrent(id, em.generationOf(id)), isTrue);
    expect(em.generationOf(id), seen + 1);
  });

  test('destroying a dead id again does not bump the generation twice', () {
    final em = EntityManager();
    final id = em.create();
    em.destroy(id);
    em.destroy(id);
    expect(em.generationOf(id), 1);
  });

  test('ensureAlive does not change the generation of an existing entity', () {
    final em = EntityManager();
    final id = em.create();
    em.destroy(id);
    em.ensureAlive(id);
    expect(
      em.generationOf(id),
      1,
      reason: 'incarnations only advance on destroy',
    );
    em.ensureAlive(id);
    expect(em.generationOf(id), 1);
    em.ensureAlive(5);
    expect(em.generationOf(5), 0);
  });

  test('each slot counts independently', () {
    final em = EntityManager();
    final a = em.create();
    final b = em.create();
    em.destroy(a);
    em.create();
    em.destroy(a);
    expect([em.generationOf(a), em.generationOf(b)], [2, 0]);
  });

  test('generations are runtime-only: toJson carries plain ids', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final a = world.spawn();
    world.destroy(a);
    final b = world.spawn();
    world.setComponent(b, Position(1, 1));
    final json = world.toJson();
    expect(json.toString(), isNot(contains('generation')));
    expect([for (final e in json['entities'] as List) e['id']], [b]);
    expect(world.generationOf(b), 1);
  });

  test('restoring a snapshot invalidates handles to entities it removes', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final keep = world.spawn();
    world.setComponent(keep, Position(0, 0));
    final snapshot = WorldSnapshot.capture(world);
    final extra = world.spawn();
    world.setComponent(extra, Position(1, 1));
    final seen = world.generationOf(extra);
    snapshot.restoreInto(world);
    expect(world.entities.isCurrent(extra, seen), isFalse);
    expect(world.entities.isCurrent(keep, world.generationOf(keep)), isTrue);
  });
}
