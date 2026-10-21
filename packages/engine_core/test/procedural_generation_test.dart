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
    test(
      'the same seed gives the same dungeon; another seed a different one',
      () {
        final a = BSPGenerator(seed: 7).generate(w, h);
        final b = BSPGenerator(seed: 7).generate(w, h);
        final c = BSPGenerator(seed: 8).generate(w, h);
        expect(a, b);
        expect(a, isNot(c));
      },
    );

    test(
      'walls (2) and floor (1) are distinct by default, and there are both',
      () {
        // Regression: walls used to default to id 1, the same as the floor, so a
        // default dungeon was one solid colour and generateHybrid turned all floor.
        final tiles = BSPGenerator(seed: 3).generate(w, h);
        expect(tiles.length, w * h);
        expect(tiles.values.toSet(), {1, 2});
      },
    );

    test(
      'every floor tile is reachable from every other: rooms are connected',
      () {
        for (final seed in [1, 2, 3, 4, 5, 6]) {
          final grid = _asList(BSPGenerator(seed: seed).generate(w, h), w * h);
          final start = grid.indexOf(1);
          final floors = [
            for (var i = 0; i < grid.length; i++)
              if (grid[i] == 1) i,
          ];
          expect(
            _reach(grid, w, h, start).length,
            floors.length,
            reason: 'seed $seed',
          );
        }
      },
    );

    test(
      'a second generate on the same generator continues the random sequence',
      () {
        final g = BSPGenerator(seed: 7);
        expect(g.generate(w, h), isNot(g.generate(w, h)));
      },
    );

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

    test('without rules any tile may sit next to any other (noise)', () {
      final g = WFCGenerator(seed: 2, tileIds: [0, 1]).generate(30, 30);
      expect(g.toSet(), {0, 1});
    });

    // A little world: water (0) only touches sand (1); sand touches water or grass (2); grass
    // only touches sand. So water and grass are never neighbours.
    const sample = [
      0, 0, 1, 2, 2, //
      0, 1, 2, 2, 2,
      1, 2, 2, 1, 0,
    ];

    test('learned rules are never broken, in any direction', () {
      final rules = WFCRules.fromSample(sample, 5);
      for (final seed in [1, 2, 3, 4, 5]) {
        final w = 12, h = 9;
        final g = WFCGenerator(
          seed: seed,
          tileIds: [0, 1, 2],
          rules: rules,
        ).generate(w, h);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final t = g[y * w + x];
            if (x + 1 < w)
              expect(
                rules.allows(t, g[y * w + x + 1], 1, 0),
                isTrue,
                reason: 'seed $seed ($x,$y) right',
              );
            if (y + 1 < h)
              expect(
                rules.allows(t, g[(y + 1) * w + x], 0, 1),
                isTrue,
                reason: 'seed $seed ($x,$y) down',
              );
          }
        }
      }
    });

    test('rules constrain the result: water and grass are never adjacent', () {
      final rules = WFCRules.fromSample(sample, 5);
      expect(rules.allows(0, 2, 1, 0), isFalse);
      expect(rules.allows(0, 1, 1, 0), isTrue);
      expect(
        rules.allows(1, 0, -1, 0),
        isTrue,
        reason: 'left is the reverse of right: 0 may be left of 1',
      );
      expect(rules.allows(2, 0, -1, 0), isFalse);
      final g = WFCGenerator(
        seed: 9,
        tileIds: [0, 1, 2],
        rules: rules,
      ).generate(20, 20);
      expect(g.toSet().length, greaterThan(1));
    });

    test('is deterministic for a seed and different for another', () {
      final rules = WFCRules.fromSample(sample, 5);
      List<int> run(int seed) => WFCGenerator(
        seed: seed,
        tileIds: [0, 1, 2],
        rules: rules,
      ).generate(10, 10);
      expect(run(3), run(3));
      expect(run(3), isNot(run(4)));
    });

    test(
      'rules that cannot be satisfied fail loudly instead of returning a broken level',
      () {
        // Tile 0 may not neighbour anything, itself included - impossible on a grid of 2+ cells.
        final rules = WFCRules(right: {}, down: {});
        expect(
          () => WFCGenerator(
            seed: 1,
            tileIds: [0],
            rules: rules,
            config: const WFCConfig(maxIterations: 3),
          ).generate(3, 3),
          throwsStateError,
        );
      },
    );
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
      expect(
        ProceduralLevelGenerator(seed: 1, wfcTileIds: [1]).generateWFC(5, 5),
        isNotNull,
      );
    });
  });
}
