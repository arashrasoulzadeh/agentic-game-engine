import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  multiplayerTests();
  test('installPlatformerSystems registers systems in the documented order', () {
    final world = _buildWorld();
    installPlatformerSystems(world, player: 0, behaviors: BehaviorRegistry());

    expect(world.systemOrder, [
      'platformerInput',
      'ai',
      'gravity',
      'movement',
      'platformer',
      'tileCollision',
      'waterPhysics',
      'jump',
      'ladder',
      'ledgeGrab',
      'dash',
      'collision',
      'health',
      'hitstun',
      'healthHud',
      'projectile',
      'attack',
      'facing',
      'movementAnimation',
      'jumpAnimation',
      'animation',
      'animationTransition',
    ]);
  });

  test('omits input/AI systems when player/behaviors are not given', () {
    final world = _buildWorld();
    installPlatformerSystems(world);

    expect(world.systemOrder, [
      'gravity',
      'movement',
      'platformer',
      'tileCollision',
      'waterPhysics',
      'jump',
      'dash',
      'collision',
      'health',
      'hitstun',
      'healthHud',
      'projectile',
      'attack',
      'facing',
      'movementAnimation',
      'jumpAnimation',
      'animation',
      'animationTransition',
    ]);
  });

  test('omits animation systems when includeAnimation is false', () {
    final world = _buildWorld();
    installPlatformerSystems(world, includeAnimation: false);

    expect(world.systemOrder, [
      'gravity',
      'movement',
      'platformer',
      'tileCollision',
      'waterPhysics',
      'jump',
      'dash',
      'collision',
      'health',
      'hitstun',
      'healthHud',
      'projectile',
      'attack',
    ]);
  });

  test('a full jump-off-tile-only-ground scenario works end to end via the pack', () {
    final world = _buildWorld();
    final input = InputState();

    // Solid floor tile spans y=[40,80]; overlapping it slightly (as
    // gravity would leave the player after a real frame) is what makes
    // PlatformerSystem/TileCollisionSystem actually resolve `grounded`
    // this tick -- see those tests' own comments for why an exact
    // tangent (y=28) wouldn't trigger the overlap check.
    final player = spawnPlayer(
      world,
      x: 20,
      y: 39,
      input: input,
      jumpSpeed: 300,
    );
    installPlatformerSystems(world, player: player);

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 2,
            rows: 2,
            tileWidth: 40,
            tileHeight: 40,
            tiles: [0, 0, 1, 1],
            solidTileIds: {1},
          ),
        );

    input.pressedActions.add('jump');
    world.step(0.016);

    expect(world.storeOf<Velocity>().get(player)!.y, -300);
  });
}

void multiplayerTests() {
  test('additionalPlayers gets its own input, ladder and ledge-grab systems', () {
    final world = _buildWorld();
    installPlatformerSystems(world, player: 0, additionalPlayers: [1, 2]);
    final order = world.systemOrder;
    expect(order.where((n) => n == 'platformerInput'), hasLength(3));
    expect(order.where((n) => n == 'ladder'), hasLength(3));
    expect(order.where((n) => n == 'ledgeGrab'), hasLength(3));
    expect(order.indexOf('gravity'), greaterThan(order.lastIndexOf('platformerInput')));
  });

  test('two players move independently from their own InputState', () {
    final world = _buildWorld();
    final left = InputState();
    final right = InputState();
    final p1 = spawnPlayer(world, x: 100, y: 100, input: left);
    final p2 = spawnPlayer(world, x: 300, y: 100, input: right);
    installPlatformerSystems(world, player: p1, additionalPlayers: [p2], includeAnimation: false);

    left.pressedActions.add('left');
    right.pressedActions.add('right');
    for (var i = 0; i < 10; i++) {
      world.step(1 / 60);
    }
    expect(world.storeOf<Position>().get(p1)!.x, lessThan(100));
    expect(world.storeOf<Position>().get(p2)!.x, greaterThan(300));
  });

  test('a single player still gets exactly one of each system', () {
    final world = _buildWorld();
    installPlatformerSystems(world, player: 0);
    expect(world.systemOrder.where((n) => n == 'platformerInput'), hasLength(1));
  });
}
