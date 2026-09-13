import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('RoomExit round-trips through toJson/fromJson', () {
    final exit = RoomExit('caveEntrance', 'doorFromOverworld');
    final decoded = RoomExit.fromJson(exit.toJson());
    expect(decoded.targetSceneId, 'caveEntrance');
    expect(decoded.spawnPoint, 'doorFromOverworld');
  });

  test('RoomExit serializes through World.toJson/applyPatch like any registered component', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);

    final id = world.spawn();
    world.storeOf<RoomExit>().set(id, RoomExit('caveEntrance', 'doorFromOverworld'));

    final serialized = world.components.serializeEntity(id);
    expect(serialized['roomExit'], {'targetSceneId': 'caveEntrance', 'spawnPoint': 'doorFromOverworld'});

    world.components.applyToEntity(id, {
      'roomExit': {'targetSceneId': 'town', 'spawnPoint': 'doorFromCave'},
    });
    expect(world.storeOf<RoomExit>().get(id)!.targetSceneId, 'town');
  });
}
