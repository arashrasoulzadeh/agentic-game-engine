// Every code sample in docs/tutorials/01-hello-world.md is exercised here (the
// `runGame` entry point excepted: it needs a real window), so the tutorial can't
// drift from the API without this file failing. Keep the two in sync.
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_platformer/zarvan_platformer.dart';
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
    final y0 = world.componentsOf<Position>().get(player)!.y;
    for (var i = 0; i < 10; i++) {
      world.step(1 / 60);
    }
    expect(world.componentsOf<Position>().get(player)!.y, greaterThan(y0));
    expect(world.componentsOf<Health>().get(player)!.max, 100);
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
    world.componentsOf<TileMap>().set(groundEntity, tileMap);

    for (var i = 0; i < 240; i++) {
      world.step(1 / 60);
    }
    final y = world.componentsOf<Position>().get(player)!.y;
    expect(
      y,
      lessThan(13 * 32),
      reason: 'resting on top of row 13, not inside it',
    );
    expect(y, greaterThan(300));
  });

  test('step 4: a patrolling enemy spawns', () {
    behaviors.register(
      'patrol',
      PatrolBehavior(minX: 300, maxX: 500, speed: 60),
    );
    final enemy = spawnEnemy(
      world,
      x: 400,
      y: 400,
      behaviorId: 'patrol',
      affectedByGravity: true,
      maxHealth: 20,
    );
    expect(world.entities.isAlive(enemy), isTrue);
    expect(world.componentsOf<Health>().get(enemy)!.max, 20);
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
    world.componentsOf<Position>().set(coinId, Position(450, 380));
    world.componentsOf<Collider>().set(coinId, Collider(8));
    world.componentsOf<Sprite>().set(coinId, Sprite('items', 'coin'));

    world.componentsOf<Inventory>().set(player, Inventory({'coin': 0}));
    dealPickupOnTouch(world, {coinId}, 'coin');

    world.componentsOf<Position>().set(player, Position(450, 380));
    world.step(1 / 60);
    expect(
      world.componentsOf<Inventory>().get(player)!.items['coin'],
      greaterThan(0),
    );
  });
}
