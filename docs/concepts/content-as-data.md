# Content as data

The engine's first design principle: game content (levels, entities,
initial state) is plain JSON, not Dart code — so a human or an AI agent
can author/edit it without recompiling, and so a running `World` can be
inspected/patched from outside.

## Level JSON: `Level.loadInto`

`Level` (`packages/engine_core/lib/src/content/level.dart`) is the
content DSL:

```json
{
  "entities": [
    {
      "name": "player",
      "components": {
        "position": {"x": 100, "y": 200},
        "velocity": {"x": 0, "y": 0},
        "collider": {"radius": 12}
      }
    },
    {
      "components": {
        "position": {"x": 400, "y": 200},
        "collider": {"radius": 8}
      }
    }
  ]
}
```

```dart
final json = jsonDecode(await rootBundle.loadString('assets/level1.json'));
final named = Level.loadInto(world, json); // Map<String, EntityId>
final playerId = named['player']!;
```

Each `components` map's keys are the string ids each component type was
registered under (`registerCoreComponents` etc. — see
[ecs.md](ecs.md)), and values are that type's own `toJson()` shape.
`Level.loadInto` spawns one entity per list item and applies its
`components` via the same path `World.applyPatch` uses — so a level
file and a runtime patch are the same format. An entity with a `"name"`
key comes back in the returned map (keyed by that name); an unnamed
entity is still spawned normally, just not returned.

`Level.validate(json)` runs the same structural validation
`loadInto` does, without spawning anything — this is what
`game_agent lint` calls to check a content file offline. It throws
`LevelLoadException` with a specific, human/agent-readable path to the
bad field (never a generic "invalid JSON") on any structural problem.

## Full world state: `World.toJson()` / `applyPatch()`

Every `World` can be dumped and restored as plain JSON — this is the
save/load format (`SaveGame` in `engine_flutter` builds on it) and also
the agent-facing read/write path for inspecting or editing a live game:

```dart
final snapshot = world.toJson();
// {"tick": 120, "width": 800, "height": 600,
//  "entities": [{"id": 3, "components": {"position": {...}, ...}}, ...]}

world.applyPatch(snapshot); // full restore
world.applyPatch({
  "entities": [
    {"id": 3, "components": {"position": {"x": 250, "y": 200}}}
  ]
}); // partial patch — only entity 3's position changes
```

`applyPatch` accepts a **subset** — only entities/components you
include are touched, everything else is left alone. It throws
`WorldPatchException` on a malformed patch shape (wrong types, missing
`id`) or `ComponentApplyException` if a named component's own JSON
fails that component's `fromJson` — never a bare, contextless
`TypeError`, since a patch may come from an untrusted or fallible
source (a hand-edited file, a tool call from an LLM).

## Why this shape

An unregistered component type can't appear in either direction — it
silently isn't serialized by `toJson()` and silently can't be applied
by `applyPatch()`/`Level.loadInto()`. If a custom component you added
isn't showing up in a snapshot, check it's registered (see
[ecs.md](ecs.md)) before looking anywhere else.

## See also

- [agent-api.md](agent-api.md) — the runtime `Behavior`/`WorldView` sandbox (for driving an entity *during* simulation, as opposed to patching state from outside it).
- [`packages/engine_core/README.md`](../../packages/engine_core/README.md) — full `Level`/`World` API, hot-reload (`LevelHandle`), localization.
- [`packages/engine_cli/README.md`](../../packages/engine_cli/README.md) — `game_agent lint`.
