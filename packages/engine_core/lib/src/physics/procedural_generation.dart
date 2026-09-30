import 'dart:math';

import 'tile_map.dart';

/// Procedural level generation utilities.
/// Provides seeded, deterministic generation of tile-based levels.

/// Configuration for BSP (Binary Space Partitioning) room generation.
class BSPConfig {
  final int minRoomWidth;
  final int minRoomHeight;
  final int maxRoomWidth;
  final int maxRoomHeight;
  final int maxDepth;
  final double roomPadding; // Fraction of room size to leave as padding

  const BSPConfig({
    this.minRoomWidth = 4,
    this.minRoomHeight = 4,
    this.maxRoomWidth = 12,
    this.maxRoomHeight = 10,
    this.maxDepth = 8,
    this.roomPadding = 0.1,
  });
}

/// A rectangle in grid coordinates.
class GridRect {
  final int x;
  final int y;
  final int w;
  final int h;

  GridRect(this.x, this.y, this.w, this.h);

  int get left => x;
  int get right => x + w - 1;
  int get top => y;
  int get bottom => y + h - 1;
  int get centerX => x + w ~/ 2;
  int get centerY => y + h ~/ 2;

  bool contains(int px, int py) =>
      px >= left && px <= right && py >= top && py <= bottom;

  bool overlaps(GridRect other) =>
      left <= other.right && right >= other.left &&
      top <= other.bottom && bottom >= other.top;
}

/// A node in the BSP tree.
class BSPNode {
  final GridRect rect;
  BSPNode? left;
  BSPNode? right;
  GridRect? room;

  BSPNode(this.rect);

  bool get isLeaf => left == null && right == null;
}

/// Generates a dungeon using Binary Space Partitioning.
class BSPGenerator {
  final Random _rng;
  final BSPConfig _config;

  BSPGenerator({required int seed, BSPConfig? config})
      : _rng = Random(seed),
        _config = config ?? const BSPConfig();

  /// Generates a dungeon layout within the given bounds.
  /// Returns a map of tile positions to tile types (0 = empty, 1 = floor, 2 = wall).
  Map<int, int> generate(int width, int height, {Set<int>? wallIds}) {
    final wallId = wallIds?.first ?? 1;
    final tiles = <int, int>{};

    // Initialize all as walls
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        tiles[y * width + x] = wallId;
      }
    }

    // Build BSP tree
    final root = BSPNode(GridRect(0, 0, width, height));
    _splitNode(root, 0);

    // Carve rooms
    _carveRooms(root, tiles, width, height);

    // Connect rooms with corridors
    _connectRooms(root, tiles, width);

    return tiles;
  }

  void _splitNode(BSPNode node, int depth) {
    if (depth >= _config.maxDepth) return;

    final rect = node.rect;
    final canSplitH = rect.h >= _config.minRoomHeight * 2;
    final canSplitV = rect.w >= _config.minRoomWidth * 2;

    if (!canSplitH && !canSplitV) return;

    final splitHorizontal = canSplitH && (!canSplitV || _rng.nextBool());

    if (splitHorizontal) {
      // Split horizontally (top/bottom)
      final minH = _config.minRoomHeight;
      final maxH = rect.h - minH;
      if (maxH <= minH) return;
      final splitY = _rng.nextInt(maxH - minH + 1) + minH;
      node.left = BSPNode(GridRect(rect.x, rect.y, rect.w, splitY));
      node.right = BSPNode(GridRect(rect.x, rect.y + splitY, rect.w, rect.h - splitY));
    } else {
      // Split vertically (left/right)
      final minW = _config.minRoomWidth;
      final maxW = rect.w - minW;
      if (maxW <= minW) return;
      final splitX = _rng.nextInt(maxW - minW + 1) + minW;
      node.left = BSPNode(GridRect(rect.x, rect.y, splitX, rect.h));
      node.right = BSPNode(GridRect(rect.x + splitX, rect.y, rect.w - splitX, rect.h));
    }

    _splitNode(node.left!, depth + 1);
    _splitNode(node.right!, depth + 1);
  }

  void _carveRooms(BSPNode node, Map<int, int> tiles, int width, int height) {
    if (node.isLeaf) {
      final rect = node.rect;
      final paddingW = (rect.w * _config.roomPadding).round().clamp(1, rect.w ~/ 2);
      final paddingH = (rect.h * _config.roomPadding).round().clamp(1, rect.h ~/ 2);

      final roomW = rect.w - paddingW * 2;
      final roomH = rect.h - paddingH * 2;

      if (roomW < _config.minRoomWidth || roomH < _config.minRoomHeight) {
        // Fallback: use whole rect
        node.room = rect;
      } else {
        final roomX = rect.x + paddingW + _rng.nextInt(rect.w - paddingW * 2 - roomW + 1);
        final roomY = rect.y + paddingH + _rng.nextInt(rect.h - paddingH * 2 - roomH + 1);
        node.room = GridRect(roomX, roomY, roomW, roomH);
      }

      // Carve floor
      final room = node.room!;
      for (int y = room.top; y <= room.bottom; y++) {
        for (int x = room.left; x <= room.right; x++) {
          if (x >= 0 && x < width && y >= 0 && y < height) {
            tiles[y * width + x] = 1; // Floor
          }
        }
      }
    } else {
      _carveRooms(node.left!, tiles, width, height);
      _carveRooms(node.right!, tiles, width, height);
    }
  }

  void _connectRooms(BSPNode node, Map<int, int> tiles, int width) {
    if (node.isLeaf) return;

    _connectRooms(node.left!, tiles, width);
    _connectRooms(node.right!, tiles, width);

    final leftRoom = _findRoom(node.left!);
    final rightRoom = _findRoom(node.right!);

    if (leftRoom != null && rightRoom != null) {
      _carveCorridor(leftRoom, rightRoom, tiles, width);
    }
  }

  GridRect? _findRoom(BSPNode node) {
    if (node.room != null) return node.room;
    if (node.left != null) return _findRoom(node.left!);
    if (node.right != null) return _findRoom(node.right!);
    return null;
  }

  void _carveCorridor(GridRect a, GridRect b, Map<int, int> tiles, int width) {
    int x1 = a.centerX;
    int y1 = a.centerY;
    int x2 = b.centerX;
    int y2 = b.centerY;

    // L-shaped corridor: horizontal then vertical
    if (_rng.nextBool()) {
      _carveLine(x1, y1, x2, y1, tiles, width);
      _carveLine(x2, y1, x2, y2, tiles, width);
    } else {
      _carveLine(x1, y1, x1, y2, tiles, width);
      _carveLine(x1, y2, x2, y2, tiles, width);
    }
  }

  void _carveLine(int x1, int y1, int x2, int y2, Map<int, int> tiles, int width) {
    final dx = (x2 - x1).sign;
    final dy = (y2 - y1).sign;
    int x = x1;
    int y = y1;

    while (x != x2 || y != y2) {
      if (x >= 0 && x < width && y >= 0 && y < (tiles.length ~/ width)) {
        tiles[y * width + x] = 1; // Floor
      }
      if (x != x2) x += dx;
      if (y != y2) y += dy;
    }
  }
}

/// Configuration for Cellular Automata cave generation.
class CellularAutomataConfig {
  final double initialWallChance; // 0.0 to 1.0
  final int iterations;
  final int birthLimit; // Min neighbors to become wall
  final int deathLimit; // Max neighbors to stay wall

  const CellularAutomataConfig({
    this.initialWallChance = 0.45,
    this.iterations = 4,
    this.birthLimit = 5,
    this.deathLimit = 3,
  });
}

/// Generates cave-like levels using Cellular Automata.
class CellularAutomataGenerator {
  final Random _rng;
  final CellularAutomataConfig _config;

  CellularAutomataGenerator({required int seed, CellularAutomataConfig? config})
      : _rng = Random(seed),
        _config = config ?? const CellularAutomataConfig();

  /// Generates a cave layout.
  /// Returns tiles where 0 = empty, 1 = floor, 2 = wall.
  List<int> generate(int width, int height) {
    var grid = _initializeGrid(width, height);

    for (int i = 0; i < _config.iterations; i++) {
      grid = _step(grid, width, height);
    }

    // Ensure borders are walls
    for (int x = 0; x < width; x++) {
      grid[x] = 2;
      grid[(height - 1) * width + x] = 2;
    }
    for (int y = 0; y < height; y++) {
      grid[y * width] = 2;
      grid[y * width + (width - 1)] = 2;
    }

    return grid;
  }

  List<int> _initializeGrid(int width, int height) {
    final grid = List<int>.filled(width * height, 1); // Start as floor
    for (int i = 0; i < width * height; i++) {
      if (_rng.nextDouble() < _config.initialWallChance) {
        grid[i] = 2; // Wall
      }
    }
    return grid;
  }

  List<int> _step(List<int> grid, int width, int height) {
    final newGrid = List<int>.from(grid);

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final idx = y * width + x;
        final wallNeighbors = _countWallNeighbors(grid, width, x, y);

        if (grid[idx] == 2) {
          // Currently wall
          if (wallNeighbors < _config.deathLimit) {
            newGrid[idx] = 1; // Becomes floor
          }
        } else {
          // Currently floor
          if (wallNeighbors > _config.birthLimit) {
            newGrid[idx] = 2; // Becomes wall
          }
        }
      }
    }

    return newGrid;
  }

  int _countWallNeighbors(List<int> grid, int width, int x, int y) {
    int count = 0;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx >= 0 && nx < width && ny >= 0 && ny < (grid.length ~/ width)) {
          if (grid[ny * width + nx] == 2) count++;
        }
      }
    }
    return count;
  }
}

/// Configuration for Wave Function Collapse generation.
class WFCConfig {
  final int maxIterations;
  final bool allowBacktracking;

  const WFCConfig({
    this.maxIterations = 1000,
    this.allowBacktracking = true,
  });
}

/// A tile pattern for Wave Function Collapse.
class TilePattern {
  final List<int> pattern; // 3x3 grid flattened
  final int centerTile; // The tile this pattern represents

  TilePattern(this.pattern, this.centerTile);

  bool matches(List<int> grid, int width, int x, int y) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px < 0 || py < 0 || px >= width || py >= (grid.length ~/ width)) {
          // Out of bounds - treat as matching any pattern
          continue;
        }
        final patternIdx = (dy + 1) * 3 + (dx + 1);
        if (pattern[patternIdx] != grid[py * width + px]) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Generates levels using Wave Function Collapse.
class WFCGenerator {
  final Random _rng;
  final WFCConfig _config;
  final List<int> _tileIds;

  WFCGenerator({
    required int seed,
    required List<int> tileIds,
    WFCConfig? config,
  }) : _rng = Random(seed),
       _config = config ?? const WFCConfig(),
       _tileIds = tileIds;

  /// Generates a level from patterns.
  /// Returns list of tile IDs.
  List<int> generate(int width, int height) {
    // Initialize all cells with all possible tiles
    final possibilities = List<List<int>>.generate(
      width * height,
      (_) => List<int>.from(_tileIds),
    );

    // Constraint propagation
    for (int iter = 0; iter < _config.maxIterations; iter++) {
      // Find cell with minimum entropy (fewest possibilities)
      int minEntropy = _tileIds.length + 1;
      int minIdx = -1;

      for (int i = 0; i < possibilities.length; i++) {
        if (possibilities[i].length > 1 && possibilities[i].length < minEntropy) {
          minEntropy = possibilities[i].length;
          minIdx = i;
        }
      }

      if (minIdx == -1) break; // All collapsed

      // Collapse this cell
      final chosen = possibilities[minIdx][_rng.nextInt(possibilities[minIdx].length)];
      possibilities[minIdx] = [chosen];

      // Propagate constraints
      _propagate(possibilities, width, height, minIdx);
    }

    // Convert to final grid
    final grid = List<int>.filled(width * height, _tileIds.first);
    for (int i = 0; i < possibilities.length; i++) {
      if (possibilities[i].isNotEmpty) {
        grid[i] = possibilities[i].first;
      }
    }

    return grid;
  }

  void _propagate(List<List<int>> possibilities, int width, int height, int startIdx) {
    final queue = <int>[startIdx];
    final inQueue = List<bool>.filled(possibilities.length, false);
    inQueue[startIdx] = true;

    while (queue.isNotEmpty) {
      final idx = queue.removeAt(0);
      inQueue[idx] = false;

      final x = idx % width;
      final y = idx ~/ width;
      final tile = possibilities[idx].first;

      // Check all 4 neighbors
      for (final (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

        final nIdx = ny * width + nx;
        final nPossibilities = possibilities[nIdx];

        // Filter neighbor possibilities based on compatibility
        final compatible = nPossibilities.where((t) => _areCompatible(tile, t, dx, dy)).toList();

        if (compatible.length < nPossibilities.length) {
          possibilities[nIdx] = compatible;
          if (compatible.isEmpty) {
            // Contradiction - could backtrack here
            possibilities[nIdx] = [_tileIds.first];
          }
          if (!inQueue[nIdx]) {
            queue.add(nIdx);
            inQueue[nIdx] = true;
          }
        }
      }
    }
  }

  bool _areCompatible(int tileA, int tileB, int dx, int dy) {
    // Simple compatibility: allow any combination for now
    // In a real implementation, this would check pattern adjacency rules
    return true;
  }
}

/// High-level procedural level generator that combines multiple algorithms.
class ProceduralLevelGenerator {
  final BSPGenerator _bsp;
  final CellularAutomataGenerator _cellular;
  final WFCGenerator? _wfc;

  ProceduralLevelGenerator({
    required int seed,
    BSPConfig? bspConfig,
    CellularAutomataConfig? cellularConfig,
    WFCConfig? wfcConfig,
    List<int>? wfcTileIds,
  }) : _bsp = BSPGenerator(seed: seed, config: bspConfig),
       _cellular = CellularAutomataGenerator(seed: seed + 1, config: cellularConfig),
       _wfc = wfcTileIds != null
           ? WFCGenerator(seed: seed + 2, tileIds: wfcTileIds, config: wfcConfig)
           : null;

  /// Generates a dungeon using BSP.
  Map<int, int> generateDungeon(int width, int height) {
    return _bsp.generate(width, height);
  }

  /// Generates a cave using Cellular Automata.
  List<int> generateCave(int width, int height) {
    return _cellular.generate(width, height);
  }

  /// Generates a level using WFC (if configured).
  List<int>? generateWFC(int width, int height) {
    return _wfc?.generate(width, height);
  }

  /// Generates a hybrid dungeon-cave level.
  Map<int, int> generateHybrid(int width, int height) {
    // Generate BSP dungeon
    final dungeon = _bsp.generate(width, height);

    // Generate cellular automata for cave-like areas
    final cave = _cellular.generate(width, height);

    // Blend: use dungeon rooms, cellular caves for corridors
    final blended = <int, int>{};
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final d = dungeon[idx] ?? 0;
        final c = cave[idx];

        if (d == 1) {
          blended[idx] = 1; // Dungeon room floor
        } else if (c == 1) {
          blended[idx] = 1; // Cave floor
        } else {
          blended[idx] = 2; // Wall
        }
      }
    }

    return blended;
  }

  /// Converts generated tiles to a TileMap.
  TileMap toTileMap(
    int width,
    int height,
    double tileWidth,
    double tileHeight,
    Map<int, int> tiles, {
    String? atlasId,
    Map<int, String>? regionByTileId,
  }) {
    final tileList = List<int>.filled(width * height, 0);
    tiles.forEach((k, v) {
      if (k >= 0 && k < width * height) tileList[k] = v;
    });

    return TileMap(
      cols: width,
      rows: height,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      tiles: tileList,
      solidTileIds: {2}, // Wall tiles are solid
      atlasId: atlasId,
      regionByTileId: regionByTileId ?? {1: 'floor', 2: 'wall'},
    );
  }
}