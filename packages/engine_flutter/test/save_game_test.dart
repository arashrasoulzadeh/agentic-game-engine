import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

World _buildWorld() {
  final world = World(width: 200, height: 200);
  registerCoreComponents(world);
  return world;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('hasSave is false before any save exists', () async {
    expect(await SaveGame.hasSave(), isFalse);
  });

  test('save then load restores entity component data into a fresh world', () async {
    final original = _buildWorld();
    final id = original.spawn();
    original.storeOf<Position>().set(id, Position(10, 20));
    original.storeOf<Collider>().set(id, Collider(5));

    await SaveGame.save(original);
    expect(await SaveGame.hasSave(), isTrue);

    final restored = _buildWorld();
    final loaded = await SaveGame.load(restored);

    expect(loaded, isTrue);
    expect(restored.entities.count, 1);
    final restoredId = restored.entities.all.first;
    expect(restored.storeOf<Position>().get(restoredId)!.x, 10);
    expect(restored.storeOf<Position>().get(restoredId)!.y, 20);
    expect(restored.storeOf<Collider>().get(restoredId)!.radius, 5);
  });

  test('load returns false and does nothing when no save exists for the slot', () async {
    final world = _buildWorld();
    final loaded = await SaveGame.load(world, slot: 'nonexistent');
    expect(loaded, isFalse);
    expect(world.entities.count, 0);
  });

  test('slots are independent', () async {
    final worldA = _buildWorld()..spawn();
    await SaveGame.save(worldA, slot: 'a');

    expect(await SaveGame.hasSave(slot: 'a'), isTrue);
    expect(await SaveGame.hasSave(slot: 'b'), isFalse);
  });

  test('deleteSave removes the save', () async {
    final world = _buildWorld()..spawn();
    await SaveGame.save(world);
    await SaveGame.deleteSave();
    expect(await SaveGame.hasSave(), isFalse);
  });
}
