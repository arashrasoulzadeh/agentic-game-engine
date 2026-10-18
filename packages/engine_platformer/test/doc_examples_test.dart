// Every code sample in docs/tutorials/01-hello-world.md is exercised here (the
// `runGame` entry point excepted: it needs a real window), so the tutorial can't
// drift from the API without this file failing. Keep the two in sync.
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late World world;
  late InputController input;
  late EntityId player;
  late BehaviorRegistry behaviors;

  setUp(() {
    world = World(width: 800, height: 480);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    input = InputController();
    behaviors = BehaviorRegistry();

    // Step 2 -- the scene's populate.
    registerPlatformerComponents(world);
    player = spawnPlayer(
      world,
      x: 100,
      y: 100,
      input: input.state,
      jumpSpeed: 480,
      maxHealth: 100,
    );
    installPlatformerSystems(world, player: player, behaviors: behaviors);
  });

  test('step 2: the player exists and falls under gravity', () {
    final y0 = world.storeOf<Position>().get(player)!.y;
    for (var i = 0; i < 10; i++) {
      world.step(1 / 60);
    }
    expect(world.storeOf<Position>().get(player)!.y, greaterThan(y0));
    expect(world.storeOf<Health>().get(player)!.max, 100);
  });

  test('step 3: a solid tile floor stops the player', () {
    final tileMap = TileMap(
      tileWidth: 32,
      tileHeight: 32,
      cols: 25,
      rows: 15,
      tiles: List.generate(25 * 15, (i) => i >= 25 * 13 ? 1 : 0),
      solidTileIds: {1},
    );
    final groundEntity = world.spawn();
    world.storeOf<TileMap>().set(groundEntity, tileMap);

    for (var i = 0; i < 240; i++) {
      world.step(1 / 60);
    }
    final y = world.storeOf<Position>().get(player)!.y;
    expect(y, lessThan(13 * 32), reason: 'resting on top of row 13, not inside it');
    expect(y, greaterThan(300));
  });

  test('step 4: a patrolling enemy spawns', () {
    behaviors.register('patrol', PatrolBehavior(minX: 300, maxX: 500, speed: 60));
    final enemy = spawnEnemy(
      world,
      x: 400,
      y: 400,
      behaviorId: 'patrol',
      affectedByGravity: true,
      maxHealth: 20,
    );
    expect(world.entities.isAlive(enemy), isTrue);
    expect(world.storeOf<Health>().get(enemy)!.max, 20);
  });

  test('step 5: a health bar HUD follows the player', () {
    final bar = spawnHealthHudBar(
      world,
      source: player,
      x: 20,
      y: 20,
      width: 200,
      height: 20,
    );
    expect(world.entities.isAlive(bar), isTrue);
  });

  test('step 6: touching a pickup adds it to the inventory', () {
    final coinId = world.spawn();
    world.storeOf<Position>().set(coinId, Position(450, 380));
    world.storeOf<Collider>().set(coinId, Collider(8));
    world.storeOf<Sprite>().set(coinId, Sprite('items', 'coin'));

    world.storeOf<Inventory>().set(player, Inventory({'coin': 0}));
    dealPickupOnTouch(world, {coinId}, 'coin');

    world.storeOf<Position>().set(player, Position(450, 380));
    world.step(1 / 60);
    expect(world.storeOf<Inventory>().get(player)!.items['coin'], greaterThan(0));
  });
}
