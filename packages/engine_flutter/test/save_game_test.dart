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

  test('load throws LevelLoadException on corrupted (non-object) save data', () async {
    SharedPreferences.setMockInitialValues({'engine_save_default': '"just a string"'});
    final world = _buildWorld();
    expect(() => SaveGame.load(world), throwsA(isA<LevelLoadException>()));
  });

  test('load throws LevelLoadException when the saved snapshot has a malformed entity', () async {
    SharedPreferences.setMockInitialValues({
      'engine_save_default': '{"entities": [{"id": 0, "components": "not an object"}]}',
    });
    final world = _buildWorld();
    expect(() => SaveGame.load(world), throwsA(isA<LevelLoadException>()));
  });

  group('schema versioning', () {
    test('save/load round-trip works at a non-default version', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(5, 6));

      await SaveGame.save(original, version: 3);
      final restored = _buildWorld();
      final loaded = await SaveGame.load(restored, version: 3);

      expect(loaded, isTrue);
      expect(restored.storeOf<Position>().get(restored.entities.all.first)!.x, 5);
    });

    test('a version mismatch with no migrate throws SaveVersionException', () async {
      final original = _buildWorld()..spawn();
      await SaveGame.save(original, version: 1);

      final restored = _buildWorld();
      expect(
        () => SaveGame.load(restored, version: 2),
        throwsA(isA<SaveVersionException>()
            .having((e) => e.savedVersion, 'savedVersion', 1)
            .having((e) => e.currentVersion, 'currentVersion', 2)),
      );
    });

    test('a version mismatch calls migrate and loads the migrated data', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 1));
      await SaveGame.save(original, version: 1);

      final restored = _buildWorld();
      var migrateCalledWithVersion = -1;
      final loaded = await SaveGame.load(
        restored,
        version: 2,
        migrate: (savedWorldJson, savedVersion) {
          migrateCalledWithVersion = savedVersion;
          return savedWorldJson; // no real shape change in this test
        },
      );

      expect(loaded, isTrue);
      expect(migrateCalledWithVersion, 1);
      expect(restored.storeOf<Position>().get(restored.entities.all.first)!.x, 1);
    });

    test('a save written before versioning existed (no envelope) is treated as version 1', () async {
      // What SaveGame.save produced before this parameter existed --
      // the raw World JSON with no {schemaVersion, world} wrapper.
      SharedPreferences.setMockInitialValues({
        'engine_save_default': '{"tick": 0, "width": 200, "height": 200, "entities": []}',
      });
      final world = _buildWorld();

      final loaded = await SaveGame.load(world, version: 1);
      expect(loaded, isTrue);

      expect(
        () => SaveGame.load(_buildWorld(), version: 2),
        throwsA(isA<SaveVersionException>().having((e) => e.savedVersion, 'savedVersion', 1)),
      );
    });
  });
}
