import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  world.addSystem(CollisionSystem());
  return world;
}

void main() {
  test('onCollisionBetween fires only for that exact pair, either order', () {
    final world = _buildWorld();
    final a = world.spawn();
    final b = world.spawn();
    final c = world.spawn();
    // Overlapping but not exactly coincident -- CollisionSystem treats
    // distSq < 0.0001 (exact same position) as degenerate and skips it.
    final positions = [Position(0, 0), Position(5, 0), Position(-5, 0)];
    for (var i = 0; i < 3; i++) {
      final id = [a, b, c][i];
      world.storeOf<Position>().set(id, positions[i]);
      world.storeOf<Collider>().set(id, Collider(10));
    }

    var fired = 0;
    world.onCollisionBetween(a, b, () => fired++);

    world.step(0.016);
    expect(fired, 1);
  });

  test('onCollisionInvolving passes the other entity regardless of order', () {
    final world = _buildWorld();
    final player = world.spawn();
    final coin = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Position>().set(coin, Position(5, 0));
    world.storeOf<Collider>().set(coin, Collider(10));

    EntityId? other;
    world.onCollisionInvolving(player, (o) => other = o);
    world.step(0.016);

    expect(other, coin);
  });

  test('onCollisionInvolving also matches when entity is the second id in the pair', () {
    final world = _buildWorld();
    final player = world.spawn();
    final coin = world.spawn();
    // Collider set for coin first so it's the first entry in the spatial
    // hash bucket -- CollisionEvent comes out as (coin, player), putting
    // player on the `e.b` side instead of `e.a`.
    world.storeOf<Position>().set(coin, Position(5, 0));
    world.storeOf<Collider>().set(coin, Collider(10));
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    EntityId? other;
    world.onCollisionInvolving(player, (o) => other = o);
    world.step(0.016);

    expect(other, coin);
  });

  test('onCollisionWithAny fires for any group member and reports which one', () {
    final world = _buildWorld();
    final player = world.spawn();
    final coinA = world.spawn();
    final coinB = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Position>().set(coinA, Position(5, 0));
    world.storeOf<Collider>().set(coinA, Collider(10));
    // coinB far away, shouldn't collide.
    world.storeOf<Position>().set(coinB, Position(9999, 9999));
    world.storeOf<Collider>().set(coinB, Collider(10));

    final touched = <EntityId>{};
    world.onCollisionWithAny({coinA, coinB}, (self, other) => touched.add(self));

    world.step(0.016);

    expect(touched, {coinA});
  });

  test('onCollisionWithAny matches when a group member is the first id in the pair', () {
    final world = _buildWorld();
    final coinA = world.spawn();
    final player = world.spawn();
    // Collider set for coinA first, so it ends up as `e.a` -- the
    // `group.contains(e.a)` branch, never exercised by the tests above
    // (which both put the group member on the `e.b` side).
    world.storeOf<Position>().set(coinA, Position(0, 0));
    world.storeOf<Collider>().set(coinA, Collider(10));
    world.storeOf<Position>().set(player, Position(5, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    EntityId? touchedSelf;
    EntityId? touchedOther;
    world.onCollisionWithAny({coinA}, (self, other) {
      touchedSelf = self;
      touchedOther = other;
    });

    world.step(0.016);

    expect(touchedSelf, coinA);
    expect(touchedOther, player);
  });

  test('onCollisionWithAny also matches when a group member is the second id in the pair', () {
    final world = _buildWorld();
    final player = world.spawn();
    final coinA = world.spawn();
    // Collider set for player first, so player ends up as `e.a` and
    // coinA (the group member) as `e.b` -- the reverse of the test
    // above, which only exercised `group.contains(e.a)`.
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Position>().set(coinA, Position(5, 0));
    world.storeOf<Collider>().set(coinA, Collider(10));

    EntityId? touchedSelf;
    EntityId? touchedOther;
    world.onCollisionWithAny({coinA}, (self, other) {
      touchedSelf = self;
      touchedOther = other;
    });

    world.step(0.016);

    expect(touchedSelf, coinA);
    expect(touchedOther, player);
  });
}
