# Procedural generation

`engine_core` can generate tile levels from a **seed**. The same seed always gives the same
level, on every platform, so a seed is a complete, shareable description of a level (and a
fair thing to put in a save file or a multiplayer handshake). The generators are in
`physics/procedural_generation.dart`; the samples here are checked by
`packages/engine_core/test/procedural_generation_test.dart`.

Tile ids used by the generators: **`1` is floor, `2` is wall**. `ProceduralLevelGenerator.toTileMap`
marks `2` solid.

## Dungeons: `BSPGenerator`

Binary space partitioning: split the area into rectangles, put a room in each leaf, and
join sibling rooms with L-shaped corridors. The result is always one connected set of
floor (every room can reach every other).

```dart
final tiles = BSPGenerator(seed: 7).generate(60, 40);   // Map<int,int>: index -> tile id
```

The key is `y * width + x`. Tune it with `BSPConfig` (min/max room size, `maxDepth`,
`roomPadding`). `generate(..., wallIds: {9})` uses a different wall id.

## Caves: `CellularAutomataGenerator`

Random noise smoothed by a few rounds of "become wall if enough neighbours are walls".
Returns a flat `List<int>` of `width * height`, with a solid wall border.

```dart
final cave = CellularAutomataGenerator(
  seed: 5,
  config: const CellularAutomataConfig(initialWallChance: 0.45, iterations: 4),
).generate(60, 40);
```

More `initialWallChance` gives tighter caves. Unlike the dungeon, a cave is **not guaranteed
connected**: flood-fill from where the player starts and discard or connect the rest.

## Putting it together: `ProceduralLevelGenerator`

One seed for all three, with different sub-seeds so they do not mirror each other:

```dart
final gen = ProceduralLevelGenerator(seed: 11);
final tiles = gen.generateHybrid(60, 40);                // dungeon rooms + cave floor
final map = gen.toTileMap(60, 40, 16, 16, tiles);        // a TileMap, walls solid
```

`toTileMap` takes `atlasId` / `regionByTileId` if you want sprites (default regions are
`floor` and `wall`). To make a level file rather than a runtime map, write the `TileMap`
into a level entity like any other — see [Content as data](content-as-data.md).

!!! warning "Wave Function Collapse is a placeholder"
    `WFCGenerator` currently has **no adjacency rules**: every tile may neighbour every other,
    so it produces seeded random tiles from the ids you give it. It is a hook for real
    rules, not a coherent-output generator yet. Use BSP or cellular automata for levels
    that must make sense.

## Determinism notes

- Each generator owns its `Random(seed)`; do not share one between generators or call a
  generator twice expecting the same result — a second `generate` continues the sequence.
  Make a new generator per level.
- Generation is plain Dart with no `dart:io` or platform calls, so it runs on web.
