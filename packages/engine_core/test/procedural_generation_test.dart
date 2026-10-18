import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// Cells reachable from [start] over cells equal to 1 (4-neighbour).
Set<int> _reach(List<int> grid, int w, int h, int start) {
  final seen = <int>{start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    final x = i % w, y = i ~/ w;
    for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final n = ny * w + nx;
      if (grid[n] == 1 && seen.add(n)) queue.add(n);
    }
  }
  return seen;
}

List<int> _asList(Map<int, int> tiles, int n) => [
      for (var i = 0; i < n; i++) tiles[i] ?? 0,
    ];

void main() {
  const w = 60, h = 40;

  group('BSPGenerator', () {
    test('the same seed gives the same dungeon; another seed a different one', () {
      final a = BSPGenerator(seed: 7).generate(w, h);
      final b = BSPGenerator(seed: 7).generate(w, h);
      final c = BSPGenerator(seed: 8).generate(w, h);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('walls (2) and floor (1) are distinct by default, and there are both', () {
      // Regression: walls used to default to id 1, the same as the floor, so a
      // default dungeon was one solid colour and generateHybrid turned all floor.
      final tiles = BSPGenerator(seed: 3).generate(w, h);
      expect(tiles.length, w * h);
      expect(tiles.values.toSet(), {1, 2});
    });

    test('every floor tile is reachable from every other: rooms are connected', () {
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final grid = _asList(BSPGenerator(seed: seed).generate(w, h), w * h);
        final start = grid.indexOf(1);
        final floors = [
          for (var i = 0; i < grid.length; i++)
            if (grid[i] == 1) i,
        ];
        expect(_reach(grid, w, h, start).length, floors.length, reason: 'seed $seed');
      }
    });

    test('a second generate on the same generator continues the random sequence', () {
      final g = BSPGenerator(seed: 7);
      expect(g.generate(w, h), isNot(g.generate(w, h)));
    });

    test('a custom wall id is honoured', () {
      final tiles = BSPGenerator(seed: 3).generate(w, h, wallIds: {9});
      expect(tiles.values.toSet(), {1, 9});
    });
  });

  group('CellularAutomataGenerator', () {
    test('is deterministic and the border is solid wall', () {
      final a = CellularAutomataGenerator(seed: 5).generate(w, h);
      expect(a, CellularAutomataGenerator(seed: 5).generate(w, h));
      for (var x = 0; x < w; x++) {
        expect(a[x], 2);
        expect(a[(h - 1) * w + x], 2);
      }
      for (var y = 0; y < h; y++) {
        expect(a[y * w], 2);
        expect(a[y * w + w - 1], 2);
      }
    });

    test('more initial wall means more wall', () {
      int walls(double chance) => CellularAutomataGenerator(
            seed: 5,
            config: CellularAutomataConfig(initialWallChance: chance),
          ).generate(w, h).where((t) => t == 2).length;
      expect(walls(0.2), lessThan(walls(0.6)));
    });
  });

  group('WFCGenerator', () {
    test('only uses the tile ids it was given, deterministically', () {
      final g = WFCGenerator(seed: 1, tileIds: [3, 4, 5]).generate(20, 10);
      expect(g.length, 200);
      expect(g.toSet().difference({3, 4, 5}), isEmpty);
      expect(g, WFCGenerator(seed: 1, tileIds: [3, 4, 5]).generate(20, 10));
    });

    test('has no adjacency rules yet: any tile may sit next to any other', () {
      // Documented in docs/concepts/procedural-generation.md. When rules are added,
      // replace this with a test asserting them.
      final g = WFCGenerator(seed: 2, tileIds: [0, 1]).generate(30, 30);
      expect(g.toSet(), {0, 1});
    });
  });

  group('ProceduralLevelGenerator', () {
    test('hybrid levels have floor and wall and a solid-wall TileMap', () {
      final gen = ProceduralLevelGenerator(seed: 11);
      final tiles = gen.generateHybrid(w, h);
      expect(tiles.values.toSet(), {1, 2});
      final map = gen.toTileMap(w, h, 16, 16, tiles);
      expect(map.cols, w);
      expect(map.solidTileIds, {2});
      expect(map.tiles.where((t) => t == 2), isNotEmpty);
    });

    test('generateWFC is null unless tile ids were configured', () {
      expect(ProceduralLevelGenerator(seed: 1).generateWFC(5, 5), isNull);
      expect(ProceduralLevelGenerator(seed: 1, wfcTileIds: [1]).generateWFC(5, 5), isNotNull);
    });
  });
}
