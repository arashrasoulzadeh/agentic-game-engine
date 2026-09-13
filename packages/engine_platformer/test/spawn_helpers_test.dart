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
  test('spawnPlayer wires up Position/Velocity/Collider/Gravity/PlatformerController/InputState', () {
    final world = _buildWorld();
    final input = InputState();
    final id = spawnPlayer(world, x: 10, y: 20, input: input, jumpSpeed: 400);

    expect(world.storeOf<Position>().get(id), isNotNull);
    expect(world.storeOf<Velocity>().get(id), isNotNull);
    expect(world.storeOf<Collider>().get(id), isNotNull);
    expect(world.storeOf<Gravity>().get(id), isNotNull);
    expect(world.storeOf<PlatformerController>().get(id)!.jumpSpeed, 400);
    expect(identical(world.storeOf<InputState>().get(id), input), isTrue);
  });

  test('spawnPlayer attaches a Sprite when atlasId/spriteRegion given', () {
    final world = _buildWorld();
    final id = spawnPlayer(
      world,
      x: 0,
      y: 0,
      input: InputState(),
      atlasId: 'atlas',
      spriteRegion: 'player_idle',
    );
    expect(world.storeOf<Sprite>().get(id)?.region, 'player_idle');
  });

  test('spawnEnemy wires up AIState and skips Gravity by default', () {
    final world = _buildWorld();
    final id = spawnEnemy(world, x: 5, y: 5, behaviorId: 'patrol');

    expect(world.storeOf<AIState>().get(id)!.behaviorId, 'patrol');
    expect(world.storeOf<Gravity>().get(id), isNull);
    expect(world.storeOf<PlatformerController>().get(id), isNull);
  });

  test('spawnEnemy adds Gravity/PlatformerController when affectedByGravity is true', () {
    final world = _buildWorld();
    final id = spawnEnemy(
      world,
      x: 5,
      y: 5,
      behaviorId: 'chase',
      affectedByGravity: true,
    );

    expect(world.storeOf<Gravity>().get(id), isNotNull);
    expect(world.storeOf<PlatformerController>().get(id), isNotNull);
  });

  test('spawnEnemy attaches a Sprite when atlasId/spriteRegion given', () {
    final world = _buildWorld();
    final id = spawnEnemy(
      world,
      x: 0,
      y: 0,
      behaviorId: 'patrol',
      atlasId: 'atlas',
      spriteRegion: 'enemy_idle',
    );
    expect(world.storeOf<Sprite>().get(id)?.region, 'enemy_idle');
  });

  test('spawnEnemy attaches Health when maxHealth is given', () {
    final world = _buildWorld();
    final id = spawnEnemy(world, x: 0, y: 0, behaviorId: 'patrol', maxHealth: 30);

    final health = world.storeOf<Health>().get(id);
    expect(health?.current, 30);
    expect(health?.max, 30);
  });

  test('PlatformerInputSystem turns pressed actions into velocity and jump requests', () {
    final world = _buildWorld();
    final input = InputState();
    final id = spawnPlayer(world, x: 0, y: 0, input: input, jumpSpeed: 300);
    world.addSystem(PlatformerInputSystem(id, moveSpeed: 100));

    input.pressedActions.add('right');
    world.step(0.016);
    expect(world.storeOf<Velocity>().get(id)!.x, 100);

    input.pressedActions
      ..remove('right')
      ..add('left');
    world.step(0.016);
    expect(world.storeOf<Velocity>().get(id)!.x, -100);

    input.pressedActions.add('jump');
    world.step(0.016);
    expect(world.storeOf<PlatformerController>().get(id)!.jumpRequested, isTrue);
  });
}
