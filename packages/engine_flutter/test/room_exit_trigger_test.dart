import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _NextScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  world.addSystem(CollisionSystem());
  return world;
}

void main() {
  test('touching a RoomExit calls loadScene with its target and records spawnPoint in state', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    final door = world.spawn();
    world.storeOf<Position>().set(door, Position(5, 0));
    world.storeOf<Collider>().set(door, Collider(10));
    world.storeOf<RoomExit>().set(door, RoomExit('cave', 'doorFromOverworld'));

    final scenes = SceneController();
    Scene? loaded;
    scenes.attach(
      loadScene: (next) => loaded = next,
      pushOverlay: (_) {},
      popOverlay: () {},
    );
    final state = GameState();
    final nextScene = _NextScene();

    installRoomExitTrigger(
      world,
      player: player,
      scenes: scenes,
      state: state,
      scenesById: {'cave': () => nextScene},
    );

    world.step(0.016);

    expect(identical(loaded, nextScene), isTrue);
    expect(state.data['enteredAt'], 'doorFromOverworld');
  });

  test('colliding with a non-RoomExit entity is a no-op', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    final coin = world.spawn();
    world.storeOf<Position>().set(coin, Position(5, 0));
    world.storeOf<Collider>().set(coin, Collider(10));

    final scenes = SceneController();
    var loadCalled = false;
    scenes.attach(
      loadScene: (_) => loadCalled = true,
      pushOverlay: (_) {},
      popOverlay: () {},
    );

    installRoomExitTrigger(
      world,
      player: player,
      scenes: scenes,
      state: GameState(),
      scenesById: const {},
    );

    world.step(0.016);

    expect(loadCalled, isFalse);
  });

  test('a RoomExit referencing an unregistered scene id throws', () {
    final world = _buildWorld();
    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(0, 0));
    world.storeOf<Collider>().set(player, Collider(10));

    final door = world.spawn();
    world.storeOf<Position>().set(door, Position(5, 0));
    world.storeOf<Collider>().set(door, Collider(10));
    world.storeOf<RoomExit>().set(door, RoomExit('nowhere', 'spawn'));

    final scenes = SceneController();
    scenes.attach(loadScene: (_) {}, pushOverlay: (_) {}, popOverlay: () {});

    installRoomExitTrigger(
      world,
      player: player,
      scenes: scenes,
      state: GameState(),
      scenesById: const {},
    );

    expect(() => world.step(0.016), throwsStateError);
  });
}
