import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  world.addSystem(CollisionSystem());
  return world;
}

void main() {
  test('TriggerZone round-trips through toJson/fromJson', () {
    final zone = TriggerZone('checkpointA', data: {'x': 1});
    final decoded = TriggerZone.fromJson(zone.toJson());
    expect(decoded.triggerId, 'checkpointA');
    expect(decoded.data, {'x': 1});
  });

  test('installTriggerZones fires TriggerEvent when something touches a TriggerZone', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    final zone = world.spawn();
    world.storeOf<Position>().set(zone, Position(5, 0));
    world.storeOf<Collider>().set(zone, Collider(10));
    world.storeOf<TriggerZone>().set(zone, TriggerZone('bossIntro', data: {'lineId': 3}));

    installTriggerZones(world);

    TriggerEvent? received;
    world.events.on<TriggerEvent>((e) => received = e);

    world.step(0.016);

    expect(received, isNotNull);
    expect(received!.triggerId, 'bossIntro');
    expect(received!.zone, zone);
    expect(received!.other, player);
    expect(received!.data, {'lineId': 3});
  });

  test('a trigger zone never elastically swaps velocity (no Velocity component)', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Velocity>().set(player, Velocity(50, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    final zone = world.spawn();
    world.storeOf<Position>().set(zone, Position(5, 0));
    world.storeOf<Collider>().set(zone, Collider(10));
    world.storeOf<TriggerZone>().set(zone, TriggerZone('checkpointA'));
    // Deliberately no Velocity on the zone.

    installTriggerZones(world);
    world.step(0.016);

    expect(world.storeOf<Velocity>().get(player)!.x, 50, reason: 'unaffected by the trigger zone touch');
  });

  test('colliding with a non-TriggerZone entity fires no TriggerEvent', () {
    final world = _buildWorld();
    final a = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(10));
    final b = world.spawn();
    world.storeOf<Position>().set(b, Position(5, 0));
    world.storeOf<Collider>().set(b, Collider(10));

    installTriggerZones(world);
    var fired = false;
    world.events.on<TriggerEvent>((_) => fired = true);

    world.step(0.016);

    expect(fired, isFalse);
  });

  test('both sides being TriggerZones fires an event for each', () {
    final world = _buildWorld();
    final a = world.spawn();
    world.storeOf<Position>().set(a, Position(0, 0));
    world.storeOf<Collider>().set(a, Collider(10));
    world.storeOf<TriggerZone>().set(a, TriggerZone('zoneA'));
    final b = world.spawn();
    world.storeOf<Position>().set(b, Position(5, 0));
    world.storeOf<Collider>().set(b, Collider(10));
    world.storeOf<TriggerZone>().set(b, TriggerZone('zoneB'));

    installTriggerZones(world);
    final ids = <String>[];
    world.events.on<TriggerEvent>((e) => ids.add(e.triggerId));

    world.step(0.016);

    expect(ids.toSet(), {'zoneA', 'zoneB'});
  });
}
