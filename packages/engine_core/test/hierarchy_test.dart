import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  World w() {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    return world;
  }

  test('children list, parentOf and detach', () {
    final world = w();
    final a = world.spawn(), b = world.spawn(), c = world.spawn();
    world.addChild(a, b);
    world.addChild(a, c);
    expect(world.childrenOf(a), [b, c]);
    expect(world.parentOf(b), a);
    world.detach(b);
    expect(world.parentOf(b), isNull);
    expect(world.childrenOf(a), [c]);
  });

  test('destroying a parent destroys descendants recursively', () {
    final world = w();
    final a = world.spawn(), b = world.spawn(), c = world.spawn();
    final other = world.spawn();
    world.addChild(a, b);
    world.addChild(b, c);
    world.destroy(a);
    expect([a, b, c].map(world.entities.isAlive), [false, false, false]);
    expect(world.entities.isAlive(other), isTrue);
    expect(world.componentsOf<Parent>().length, 0);
  });

  test('destroy without the Parent component registered still works', () {
    final world = World(width: 10, height: 10);
    final id = world.spawn();
    world.destroy(id);
    expect(world.entities.isAlive(id), isFalse);
  });

  test('self-parenting, cycles and dead entities are rejected', () {
    final world = w();
    final a = world.spawn(), b = world.spawn();
    world.addChild(a, b);
    expect(() => world.addChild(a, a), throwsArgumentError);
    expect(() => world.addChild(b, a), throwsArgumentError);
    world.destroy(b);
    expect(() => world.addChild(a, b), throwsStateError);
  });

  test('worldPositionOf adds ancestor positions', () {
    final world = w();
    final a = world.spawnAt(10, 20);
    final b = world.spawnAt(1, 2);
    final c = world.spawnAt(100, 100);
    world.addChild(a, b);
    world.addChild(b, c);
    expect(world.worldPositionOf(c), (x: 111.0, y: 122.0));
    expect(world.worldPositionOf(world.spawn()), isNull);
  });

  test('the link survives save and load', () {
    final world = w();
    final a = world.spawn(), b = world.spawn();
    world.addChild(a, b);
    final data = world.save();
    final copy = w();
    copy.load(data);
    expect(copy.parentOf(b), a);
  });
}
