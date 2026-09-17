# Recipe: save/load game state

`SaveGame` (`packages/engine_flutter/lib/src/logic/save_game.dart`)
persists a full `World.toJson()` snapshot via `SharedPreferences`, under
a named slot, with schema versioning.

## Save

```dart
await SaveGame.save(world, slot: 'default', version: 1);
```

Wraps `world.toJson()` in `{"schemaVersion": 1, "world": {...}}` and
writes it as a JSON string.

## Load

```dart
final loaded = await SaveGame.load(world, slot: 'default', version: 1);
if (!loaded) {
  // no save exists for this slot — start a fresh game
}
```

Internally: reads the slot, then `Level.loadInto(world, worldJson)` —
so loading a save re-spawns every entity from the snapshot into
whatever `World` you pass in (typically a fresh one from a just-loaded
`Scene`, since a save is a full-world snapshot, not a patch).

## Schema migration

If you bump `version` after already shipping a save format, pass
`migrate` to transform old save JSON forward instead of throwing
`SaveVersionException`:

```dart
final loaded = await SaveGame.load(
  world,
  version: 2,
  migrate: (savedWorldJson, savedVersion) {
    if (savedVersion == 1) {
      // e.g. add a field new components expect that v1 saves don't have
    }
    return savedWorldJson;
  },
);
```

Omitting `migrate` while `savedVersion != version` throws
`SaveVersionException(savedVersion, version)` rather than silently
loading mismatched data.

## Slots

```dart
await SaveGame.hasSave(slot: 'slot2');       // bool
await SaveGame.deleteSave(slot: 'slot2');
final slots = await SaveGame.listSlots();    // List<String>
```

`SaveSlotMenuScene` (`engine_flutter`) is a ready-made UI scene for a
multi-slot save/load menu built on this API — see
`packages/engine_flutter/README.md`.
