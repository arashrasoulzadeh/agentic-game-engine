import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(CollisionSystem());
  return world;
}

void main() {
  test('Inventory count/has read through items, defaulting to 0/false', () {
    final inventory = Inventory({'coin': 3});
    expect(inventory.count('coin'), 3);
    expect(inventory.count('key'), 0);
    expect(inventory.has('coin'), isTrue);
    expect(inventory.has('coin', 4), isFalse);
    expect(inventory.has('key'), isFalse);
  });

  test('Inventory round-trips through toJson/fromJson', () {
    final restored = Inventory.fromJson(Inventory({'coin': 2, 'key': 1}).toJson());
    expect(restored.count('coin'), 2);
    expect(restored.count('key'), 1);
  });

  test('Inventory.fromJson defaults to empty when items is absent', () {
    expect(Inventory.fromJson({}).items, isEmpty);
  });

  test('spawnPlayer with startingInventory attaches a pre-populated Inventory', () {
    final world = _buildWorld();
    final id = spawnPlayer(
      world,
      x: 0,
      y: 0,
      input: InputState(),
      startingInventory: {'coin': 5},
    );

    expect(world.storeOf<Inventory>().get(id)?.count('coin'), 5);
  });

  test('spawnPlayer without startingInventory attaches no Inventory', () {
    final world = _buildWorld();
    final id = spawnPlayer(world, x: 0, y: 0, input: InputState());
    expect(world.storeOf<Inventory>().get(id), isNull);
  });

  test('collectItem adds to the holder\'s inventory and emits ItemCollectedEvent', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Inventory>().set(player, Inventory());

    ItemCollectedEvent? fired;
    world.events.on<ItemCollectedEvent>((e) => fired = e);

    collectItem(world, player, 'coin', amount: 3);
    world.step(0);

    expect(world.storeOf<Inventory>().get(player)!.count('coin'), 3);
    expect(fired?.holder, player);
    expect(fired?.itemId, 'coin');
    expect(fired?.amount, 3);
  });

  test('collectItem accumulates across multiple calls', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Inventory>().set(player, Inventory());

    collectItem(world, player, 'coin');
    collectItem(world, player, 'coin');
    collectItem(world, player, 'key', amount: 2);

    final inventory = world.storeOf<Inventory>().get(player)!;
    expect(inventory.count('coin'), 2);
    expect(inventory.count('key'), 2);
  });

  test('collectItem is a no-op for an entity with no Inventory component', () {
    final world = _buildWorld();
    final id = world.spawn();

    var fired = false;
    world.events.on<ItemCollectedEvent>((e) => fired = true);

    collectItem(world, id, 'coin');
    world.step(0);

    expect(fired, isFalse);
  });

  test('dealPickupOnTouch collects the item and destroys the pickup by default', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Inventory>().set(player, Inventory());

    final coin = world.spawn();
    world.storeOf<Position>().set(coin, Position(5, 0));
    world.storeOf<Collider>().set(coin, Collider(10));

    dealPickupOnTouch(world, {coin}, 'coin');
    world.step(0.016);

    expect(world.storeOf<Inventory>().get(player)!.count('coin'), 1);
    expect(world.entities.isAlive(coin), isFalse);
  });

  test('dealPickupOnTouch with destroyOnCollect: false leaves the pickup alive', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));
    world.storeOf<Inventory>().set(player, Inventory());

    final lever = world.spawn();
    world.storeOf<Position>().set(lever, Position(5, 0));
    world.storeOf<Collider>().set(lever, Collider(10));

    dealPickupOnTouch(world, {lever}, 'lever-pulls', destroyOnCollect: false);
    world.step(0.016);

    expect(world.storeOf<Inventory>().get(player)!.count('lever-pulls'), 1);
    expect(world.entities.isAlive(lever), isTrue);
  });
}
