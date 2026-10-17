# Recipe: save and restore a turn-based game

The whole game — units, hit points, turn clock, fog — is world state, so a
snapshot is just `World.toJson()`.

```dart
final snapshot = world.toJson();            // Map<String, dynamic> — jsonEncode it to a file
```

Restoring has one catch: **`applyPatch` only updates entities that are alive**
(it never creates them). So rebuild the same entity ids first, then patch:

```dart
final restored = World(width: 384, height: 384);
registerCoreComponents(restored);
registerFlutterComponents(restored);

for (final _ in world.entities.all) {
  restored.spawn();                         // ids come back in the same order
}
restored.applyPatch(snapshot);

turnStateOf(restored)!.activeTeam;          // 'blue' — exactly where you left off
```

This assumes no entity was destroyed before the snapshot (so ids are dense).
If some were, `spawn()` then `destroy()` the gaps, or keep the entity ids in
your save file and spawn until they match.

Then register your systems (`installStrategySystems(restored, …)`) — systems
are code, not data, so they aren't part of a snapshot. Don't call
`startTurnBasedGame` again; the clock is already restored.

## What is and isn't saved

| Saved | Not saved |
|---|---|
| Positions, hp, action points, teams | Systems and event handlers (re-register them) |
| `TurnState` (active team, round, winner) | Pending (unflushed) events |
| `OrderQueue` contents | Sprites' loaded images (reload assets) |
| `FogOfWar` visible + explored | `Selected` is saved too — clear it on load if you prefer |

For the player-facing save UI (slots, versioning, migration), see the
[save/load recipe](save-load.md); this page is the turn-based specifics.

*Verified by `doc_examples_test.dart` ("save and restore a turn-based game").*
