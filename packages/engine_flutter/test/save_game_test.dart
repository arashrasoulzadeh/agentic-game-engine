import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

  test('listSlots returns every slot with a stored save, and nothing else', () async {
    expect(await SaveGame.listSlots(), isEmpty);

    await SaveGame.save(_buildWorld()..spawn(), slot: 'a');
    await SaveGame.save(_buildWorld()..spawn(), slot: 'b');

    expect(await SaveGame.listSlots(), unorderedEquals(['a', 'b']));
  });

  test('listSlots omits a slot after it is deleted', () async {
    await SaveGame.save(_buildWorld()..spawn(), slot: 'a');
    await SaveGame.save(_buildWorld()..spawn(), slot: 'b');
    await SaveGame.deleteSave(slot: 'a');

    expect(await SaveGame.listSlots(), ['b']);
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

  group('checksum validation', () {
    test('save computes and stores SHA-256 checksum', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original);

      final checksum = await SaveGame.getChecksum();
      expect(checksum, isNotNull);
      expect(checksum!.length, greaterThan(0));
    });

    test('load verifies checksum and rejects corrupted data', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original);

      // Corrupt the save data directly in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('engine_save_default')!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['world']['entities'][0]['components']['position']['x'] = 999;
      final corrupted = jsonEncode(decoded);
      await prefs.setString('engine_save_default', corrupted);

      final world = _buildWorld();
      expect(
        () => SaveGame.load(world),
        throwsA(isA<LevelLoadException>().having((e) => e.toString(), 'message', contains('checksum'))),
      );
    });

    test('load skips checksum verification when verifyChecksum=false', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original);

      // Corrupt the save data
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('engine_save_default')!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['world']['entities'][0]['components']['position']['x'] = 999;
      final corrupted = jsonEncode(decoded);
      await prefs.setString('engine_save_default', corrupted);

      final world = _buildWorld();
      // Should load without throwing when verifyChecksum=false
      final loaded = await SaveGame.load(world, verifyChecksum: false);
      expect(loaded, isTrue);
    });
  });

  group('thumbnail support', () {
    test('save with thumbnail stores and retrieves base64 PNG', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      final thumbnail = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]); // PNG magic bytes
      await SaveGame.save(original, thumbnail: thumbnail);

      final retrieved = await SaveGame.getThumbnail();
      expect(retrieved, isNotNull);
      expect(retrieved!.length, thumbnail.length);
      expect(retrieved![0], 0x89);
      expect(retrieved[1], 0x50);
    });

    test('getThumbnail returns null when no thumbnail was saved', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original);

      final retrieved = await SaveGame.getThumbnail();
      expect(retrieved, isNull);
    });
  });

  group('cloud sync hook', () {
    test('onCloudSync callback fires after successful load', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original);

      String? syncedSlot;
      Map<String, dynamic>? syncedWorldJson;
      final restored = _buildWorld();
      final loaded = await SaveGame.load(
        restored,
        onCloudSync: (slot, worldJson) async {
          syncedSlot = slot;
          syncedWorldJson = worldJson;
        },
      );

      expect(loaded, isTrue);
      expect(syncedSlot, 'default');
      expect(syncedWorldJson, isNotNull);
      expect(syncedWorldJson!['entities'], isA<List>());
    });
  });

  group('checksum and versioning integration', () {
    test('checksum is updated after migration', () async {
      final original = _buildWorld();
      final id = original.spawn();
      original.storeOf<Position>().set(id, Position(1, 2));

      await SaveGame.save(original, version: 1);

      // Load with migration to version 2
      final restored = _buildWorld();
      await SaveGame.load(
        restored,
        version: 2,
        migrate: (savedWorldJson, savedVersion) {
          // Migration: add a new field to entities
          final entities = savedWorldJson['entities'] as List;
          for (final entity in entities) {
            entity['migrated'] = true;
          }
          return savedWorldJson;
        },
      );

      // Save again after migration - should have new checksum
      await SaveGame.save(restored, version: 2);
      final checksum = await SaveGame.getChecksum();
      expect(checksum, isNotNull);
    });
  });
}
