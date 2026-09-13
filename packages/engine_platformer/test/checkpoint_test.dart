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
  test('spawnPlayer with maxHealth attaches Health and a LastCheckpoint at spawn', () {
    final world = _buildWorld();
    final id = spawnPlayer(world, x: 40, y: 60, input: InputState(), maxHealth: 20);

    final health = world.storeOf<Health>().get(id);
    expect(health?.current, 20);
    expect(health?.max, 20);

    final last = world.storeOf<LastCheckpoint>().get(id);
    expect(last?.x, 40);
    expect(last?.y, 60);
  });

  test('trackCheckpoints records LastCheckpoint and marks activated on touch', () {
    final world = _buildWorld();
    final player = spawnPlayer(world, x: 0, y: 0, input: InputState(), maxHealth: 10);
    trackCheckpoints(world, player);

    final checkpointEntity = world.spawn();
    world.storeOf<Position>().set(checkpointEntity, Position(205, 300));
    world.storeOf<Collider>().set(checkpointEntity, Collider(10));
    world.storeOf<Checkpoint>().set(checkpointEntity, Checkpoint('cp1'));
    world.storeOf<Position>().get(player)!
      ..x = 200
      ..y = 300;
    world.storeOf<Collider>().set(player, Collider(10));

    world.step(0);

    final last = world.storeOf<LastCheckpoint>().get(player)!;
    expect(last.x, 205);
    expect(last.y, 300);
    expect(world.storeOf<Checkpoint>().get(checkpointEntity)!.activated, isTrue);
  });

  test('respawnPlayer resets position/velocity/health to the last checkpoint', () {
    final world = _buildWorld();
    final player = spawnPlayer(world, x: 0, y: 0, input: InputState(), maxHealth: 10);
    world.storeOf<LastCheckpoint>().set(player, LastCheckpoint(150, 75));
    world.storeOf<Position>().get(player)!.x = 999;
    world.storeOf<Velocity>().get(player)!.x = 50;
    world.storeOf<Health>().get(player)!.current = 2;

    respawnPlayer(world, player, fallbackX: 0, fallbackY: 0);

    final pos = world.storeOf<Position>().get(player)!;
    expect(pos.x, 150);
    expect(pos.y, 75);
    expect(world.storeOf<Velocity>().get(player)!.x, 0);
    expect(world.storeOf<Health>().get(player)!.current, 10);
  });

  test('respawnPlayer falls back to fallbackX/Y with no LastCheckpoint yet', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(999, 999));

    respawnPlayer(world, player, fallbackX: 5, fallbackY: 9);

    final pos = world.storeOf<Position>().get(player)!;
    expect(pos.x, 5);
    expect(pos.y, 9);
  });

  test('respawnOnDeath fires respawnPlayer when the player dies', () {
    final world = _buildWorld();
    final player = spawnPlayer(world, x: 0, y: 0, input: InputState(), maxHealth: 10);
    world.storeOf<LastCheckpoint>().set(player, LastCheckpoint(300, 400));
    respawnOnDeath(world, player, fallbackX: 0, fallbackY: 0);

    damageEntity(world, player, 100, invincibilitySeconds: 0);
    world.step(0);

    final pos = world.storeOf<Position>().get(player)!;
    expect(pos.x, 300);
    expect(pos.y, 400);
    expect(world.storeOf<Health>().get(player)!.current, 10);
  });
}
