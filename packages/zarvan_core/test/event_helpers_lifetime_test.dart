import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void _collide(World world, EntityId a, EntityId b) {
  world.events.emit(CollisionEvent(a, b));
  world.events.flush();
}

void main() {
  test('the helpers return a Subscription that can be cancelled', () {
    final world = _world();
    final a = world.spawn();
    final b = world.spawn();
    var fired = 0;
    final sub = world.onCollisionBetween(a, b, () => fired++);
    _collide(world, a, b);
    sub.cancel();
    _collide(world, a, b);
    expect(fired, 1);
  });

  test('onCollisionBetween stops once either entity is destroyed', () {
    final world = _world();
    final a = world.spawn();
    final b = world.spawn();
    var fired = 0;
    final sub = world.onCollisionBetween(a, b, () => fired++);
    world.destroy(b);
    _collide(world, a, 99);
    expect(sub.isActive, isFalse);
    expect(fired, 0);
  });

  test(
    'onCollisionBetween does not fire for a new entity that reuses an id',
    () {
      final world = _world();
      final a = world.spawn();
      final b = world.spawn();
      var fired = 0;
      world.onCollisionBetween(a, b, () => fired++);
      world.destroy(b);
      final reused = world.spawn();
      expect(reused, b);
      _collide(world, a, reused);
      expect(fired, 0);
    },
  );

  test('onCollisionInvolving stops when the entity dies, even if the id is '
      'reused', () {
    final world = _world();
    final player = world.spawn();
    final other = world.spawn();
    final seen = <EntityId>[];
    final sub = world.onCollisionInvolving(player, seen.add);
    _collide(world, player, other);
    world.destroy(player);
    final reused = world.spawn();
    expect(reused, player);
    _collide(world, reused, other);
    expect(seen, [other]);
    expect(sub.isActive, isFalse);
  });

  test('a live entity keeps its handler (no false auto-cancel)', () {
    final world = _world();
    final player = world.spawn();
    final other = world.spawn();
    var fired = 0;
    final sub = world.onCollisionInvolving(player, (_) => fired++);
    world.destroy(other);
    _collide(world, player, 77);
    _collide(world, 77, player);
    expect(fired, 2);
    expect(sub.isActive, isTrue);
  });

  test('onCollisionWithAny returns a handle but does not auto-stop', () {
    final world = _world();
    final a = world.spawn();
    var fired = 0;
    final sub = world.onCollisionWithAny({a}, (_, __) => fired++);
    world.destroy(a);
    _collide(world, a, 5);
    expect(fired, 1, reason: 'raw ids carry no generation to check');
    expect(sub.isActive, isTrue);
    sub.cancel();
    _collide(world, a, 5);
    expect(fired, 1);
  });
}
