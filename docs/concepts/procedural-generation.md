# Procedural generation

`engine_core` can generate tile levels from a **seed**. The same seed always gives the same
level, on every platform, so a seed is a complete, shareable description of a level (and a
fair thing to put in a save file or a multiplayer handshake). The generators are in
`physics/procedural_generation.dart`; the samples here are checked by
`packages/engine_core/test/procedural_generation_test.dart`.

Tile ids used by BSP and cellular automata: **`1` is floor, `2` is wall**. `ProceduralLevelGenerator.toTileMap`
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

## Wave Function Collapse: `WFCGenerator`

Fills a grid so that **neighbouring tiles obey rules**. Give it an example and it learns what may
sit next to what:

```dart
const sample = [
  0, 0, 1, 2, 2,      // 0 water, 1 sand, 2 grass
  0, 1, 2, 2, 2,
  1, 2, 2, 1, 0,
];
final rules = WFCRules.fromSample(sample, 5);               // 5 = the sample's width
final map = WFCGenerator(seed: 9, tileIds: [0, 1, 2], rules: rules).generate(40, 25);
```

Water only ever touches sand or water, grass only sand or grass, because the sample never showed
otherwise. You can also state rules by hand: `WFCRules(right: {(0, 1), ...}, down: {...})`, where
`(a, b)` means *b may be immediately right of / below a*; left and up are the reverses.

How it works: every cell starts able to be any tile; the cell with the fewest options is fixed at
random and its consequences are propagated to the neighbours; repeat. If the rules leave a cell
with no option, that attempt is discarded and retried (up to `WFCConfig.maxIterations` attempts);
if none works, `generate` throws a `StateError` rather than return a level that breaks the rules.
Rules that are too strict for the grid size (or contradict themselves) fail this way, so test a
rule set at the sizes you use.

Without `rules`, every pairing is allowed and the result is seeded random noise.
`ProceduralLevelGenerator(wfcTileIds: ..., wfcRules: ...)` passes them through.

## Determinism notes

- Each generator owns its `Random(seed)`; do not share one between generators or call a
  generator twice expecting the same result — a second `generate` continues the sequence.
  Make a new generator per level.
- Generation is plain Dart with no `dart:io` or platform calls, so it runs on web.
