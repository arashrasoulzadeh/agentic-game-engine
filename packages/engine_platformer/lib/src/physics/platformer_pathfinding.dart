import 'package:engine_core/engine_core.dart';

/// Configuration for platformer-aware pathfinding.
class PlatformerPathfinderConfig {
  /// Maximum horizontal distance a jump can cover (in tiles).
  final int maxJumpHorizontalTiles;

  /// Maximum vertical height a jump can reach (in tiles, upward).
  final int maxJumpHeightTiles;

  /// Maximum vertical distance a jump can fall (in tiles, downward).
  final int maxJumpFallTiles;

  /// Whether the entity can climb ladders.
  final bool canClimbLadders;

  /// Whether the entity can drop through one-way platforms.
  final bool canDropThroughOneWay;

  /// Maximum horizontal distance for a single step/walk action.
  final int maxStepHorizontalTiles;

  /// Maximum vertical distance for a step up/down without jumping.
  final int maxStepVerticalTiles;

  const PlatformerPathfinderConfig({
    this.maxJumpHorizontalTiles = 6,
    this.maxJumpHeightTiles = 4,
    this.maxJumpFallTiles = 10,
    this.canClimbLadders = true,
    this.canDropThroughOneWay = true,
    this.maxStepHorizontalTiles = 1,
    this.maxStepVerticalTiles = 1,
  });
}

/// A path point with platformer-specific movement requirements.
class PlatformerPathPoint extends PathPoint {
  /// The type of movement required to reach this point from the previous point.
  final PlatformerMoveType moveType;

  /// For jumps: the peak height of the jump arc (in world units).
  final double? jumpPeakY;

  /// For ladder climbing: whether this point is on a ladder.
  final bool onLadder;

  PlatformerPathPoint({
    required double x,
    required double y,
    required this.moveType,
    this.jumpPeakY,
    this.onLadder = false,
    bool jumpRequired = false,
    bool climbRequired = false,
  }) : super(x, y, jumpRequired: jumpRequired, climbRequired: climbRequired);

  /// Whether this point requires a fall movement (controlled drop off ledge).
  bool get fallRequired => moveType == PlatformerMoveType.fall;

  /// Whether this point requires dropping through a one-way platform.
  bool get dropThroughOneWay => moveType == PlatformerMoveType.dropThrough;

  @override
  PlatformerPathPoint copyWith({
    double? x,
    double? y,
    bool? jumpRequired,
    bool? climbRequired,
    PlatformerMoveType? moveType,
    double? jumpPeakY,
    bool? onLadder,
  }) {
    return PlatformerPathPoint(
      x: x ?? this.x,
      y: y ?? this.y,
      moveType: moveType ?? this.moveType,
      jumpPeakY: jumpPeakY ?? this.jumpPeakY,
      onLadder: onLadder ?? this.onLadder,
      jumpRequired: jumpRequired ?? this.jumpRequired,
      climbRequired: climbRequired ?? this.climbRequired,
    );
  }
}

/// The type of movement required to reach a path point.
enum PlatformerMoveType {
  /// Simple walking on flat ground or small step up/down.
  walk,

  /// Jumping across a gap or onto a higher platform.
  jump,

  /// Climbing a ladder.
  climb,

  /// Dropping through a one-way platform.
  dropThrough,

  /// Falling down a ledge (controlled fall).
  fall,
}

/// Information about a moving platform for pathfinding.
class MovingPlatformInfo {
  final EntityId entityId;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double speed;

  MovingPlatformInfo({
    required this.entityId,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.speed,
  });
}

/// Internal node for A* priority queue.
class _Node {
  final int col;
  final int row;
  final double fScore;

  _Node(this.col, this.row, this.fScore);
}

/// Simple min-heap for A* open set.
class _MinHeap {
  final List<_Node> _heap = [];

  bool get isNotEmpty => _heap.isNotEmpty;

  void add(_Node node) {
    _heap.add(node);
    _siftUp(_heap.length - 1);
  }

  _Node removeMin() {
    final min = _heap[0];
    final end = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = end;
      _siftDown(0);
    }
    return min;
  }

  void _siftUp(int i) {
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_heap[parent].fScore <= _heap[i].fScore) break;
      _swap(parent, i);
      i = parent;
    }
  }

  void _siftDown(int i) {
    while (true) {
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      var smallest = i;

      if (left < _heap.length && _heap[left].fScore < _heap[smallest].fScore) {
        smallest = left;
      }
      if (right < _heap.length && _heap[right].fScore < _heap[smallest].fScore) {
        smallest = right;
      }
      if (smallest == i) break;
      _swap(i, smallest);
      i = smallest;
    }
  }

  void _swap(int i, int j) {
    final tmp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = tmp;
  }
}

/// Neighbor info for pathfinding expansion.
class _Neighbor {
  final int col;
  final int row;
  final double cost;
  final PlatformerPathPoint moveType;

  _Neighbor(this.col, this.row, this.cost, this.moveType);
}

/// Platformer-aware A* pathfinding.
///
/// Extends the basic tile-based A* with platformer-specific movement:
/// - Jumps (with configurable max height/distance)
/// - One-way platforms (can jump up through, drop down through)
/// - Ladders (vertical movement)
/// - Ledge dropping / controlled falling
///
/// Output: sequence of [PlatformerPathPoint] with [PlatformerMoveType] flags
/// consumable by a platformer movement behavior.
class PlatformerPathfinder {
  final PlatformerPathfinderConfig config;

  PlatformerPathfinder(this.config);

  /// Finds a platformer-aware path from [fromX]/[fromY] to [toX]/[toY].
  ///
  /// Returns a list of [PlatformerPathPoint] from the step after the start
  /// through the goal (inclusive), or empty if no path exists.
  List<PlatformerPathPoint> findPath({
    required TileMap map,
    required Position origin,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required Set<int> ladderTileIds,
    required Set<int> oneWayTileIds,
    List<MovingPlatformInfo> movingPlatforms = const [],
  }) {
    int colOf(double x) => ((x - origin.x) / map.tileWidth).floor();
    int rowOf(double y) => ((y - origin.y) / map.tileHeight).floor();
    int key(int col, int row) => row * map.cols + col;

    bool isSolid(int col, int row) {
      if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return true;
      return map.solidTileIds.contains(map.tileAt(col, row));
    }

    bool isOneWay(int col, int row) {
      if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return false;
      return oneWayTileIds.contains(map.tileAt(col, row));
    }

    bool isLadder(int col, int row) {
      if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return false;
      return ladderTileIds.contains(map.tileAt(col, row));
    }

    bool hasGroundAt(int col, int row) {
      // Check if standing on solid tile below
      if (row + 1 < map.rows) {
        final tileBelow = map.tileAt(col, row + 1);
        if (map.solidTileIds.contains(tileBelow) || oneWayTileIds.contains(tileBelow)) {
          return true;
        }
      }
      // Check if standing ON a one-way platform (current tile is one-way)
      if (oneWayTileIds.contains(map.tileAt(col, row))) {
        return true;
      }
      return false;
    }

    bool isOnOneWay(int col, int row) {
      // Entity is on a one-way platform if the current tile is one-way
      return oneWayTileIds.contains(map.tileAt(col, row));
    }

    bool isPlatform(int col, int row) {
      if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return false;
      final tileId = map.tileAt(col, row);
      return map.solidTileIds.contains(tileId) || oneWayTileIds.contains(tileId);
    }

    // Check if a straight line between two tile centers is blocked by solid tiles.
    bool _lineBlocked(double x1, double y1, double x2, double y2) {
      final x1Tile = colOf(x1);
      final y1Tile = rowOf(y1);
      final x2Tile = colOf(x2);
      final y2Tile = rowOf(y2);

      final dx = (x2Tile - x1Tile).abs();
      final dy = (y2Tile - y1Tile).abs();
      final sx = x1Tile < x2Tile ? 1 : -1;
      final sy = y1Tile < y2Tile ? 1 : -1;
      var err = dx - dy;

      var x = x1Tile;
      var y = y1Tile;

      while (true) {
        if (x == x2Tile && y == y2Tile) break;
        if (isSolid(x, y)) return true;
        final e2 = 2 * err;
        if (e2 > -dy) {
          err -= dy;
          x += sx;
        }
        if (e2 < dx) {
          err += dx;
          y += sy;
        }
      }
      return false;
    }

    double _heuristic(int c1, int r1, int c2, int r2) =>
        (c1 - c2).abs().toDouble() + (r1 - r2).abs().toDouble();

    double _estimateJumpPeakY(int fromRow, int toRow) {
      final dy = fromRow - toRow;
      if (dy <= 0) return origin.y + toRow * map.tileHeight;
      final peakTiles = dy / 2;
      return origin.y + (fromRow - peakTiles) * map.tileHeight;
    }

    List<_Neighbor> _getNeighbors(int col, int row) {
      final neighbors = <_Neighbor>[];

      // Walk left
      if (col > 0 && !isSolid(col - 1, row)) {
        final onGround = hasGroundAt(col, row);
        final targetOnGround = hasGroundAt(col - 1, row);
        if (onGround && targetOnGround) {
neighbors.add(_Neighbor(
              col - 1, row, 1.0,
              PlatformerPathPoint(
                x: origin.x + (col - 1 + 0.5) * map.tileWidth,
                y: origin.y + (row + 0.5) * map.tileHeight,
                moveType: PlatformerMoveType.walk,
                jumpRequired: false,
                climbRequired: false,
              ),
            ));
        }
      }

      // Walk right
      if (col + 1 < map.cols && !isSolid(col + 1, row)) {
        final onGround = hasGroundAt(col, row);
        final targetOnGround = hasGroundAt(col + 1, row);
        if (onGround && targetOnGround) {
neighbors.add(_Neighbor(
              col + 1, row, 1.0,
              PlatformerPathPoint(
                x: origin.x + (col + 1 + 0.5) * map.tileWidth,
                y: origin.y + (row + 0.5) * map.tileHeight,
                moveType: PlatformerMoveType.walk,
                jumpRequired: false,
                climbRequired: false,
              ),
            ));
        }
      }

      // Step up (small height difference) - target must be a platform
      if (row > 0 && !isSolid(col, row - 1) && isPlatform(col, row - 1) && hasGroundAt(col, row)) {
        neighbors.add(_Neighbor(
          col, row - 1, 1.0,
          PlatformerPathPoint(
            x: origin.x + (col + 0.5) * map.tileWidth,
            y: origin.y + (row - 1 + 0.5) * map.tileHeight,
            moveType: PlatformerMoveType.walk,
            jumpRequired: false,
            climbRequired: false,
          ),
        ));
      }

      // Step down - target must be a platform
      if (row + 1 < map.rows && !isSolid(col, row + 1) && isPlatform(col, row + 1)) {
        neighbors.add(_Neighbor(
          col, row + 1, 1.0,
          PlatformerPathPoint(
            x: origin.x + (col + 0.5) * map.tileWidth,
            y: origin.y + (row + 1 + 0.5) * map.tileHeight,
            moveType: PlatformerMoveType.walk,
            jumpRequired: false,
            climbRequired: false,
          ),
        ));
      }

      // Jumps
      for (final dc in [-1, 1]) {
        for (int dj = 1; dj <= config.maxJumpHorizontalTiles; dj++) {
          final nCol = col + dc * dj;
          if (nCol < 0 || nCol >= map.cols) break;
          for (int dr = -config.maxJumpHeightTiles; dr <= config.maxJumpFallTiles; dr++) {
            final nRow = row + dr;
            if (nRow < 0 || nRow >= map.rows) continue;
            if (isSolid(nCol, nRow)) continue;
            if (!hasGroundAt(nCol, nRow)) continue;
            if (!_lineBlocked(
              origin.x + (col + 0.5) * map.tileWidth,
              origin.y + (row + 0.5) * map.tileHeight,
              origin.x + (nCol + 0.5) * map.tileWidth,
              origin.y + (nRow + 0.5) * map.tileHeight,
            )) {
              neighbors.add(_Neighbor(
                nCol, nRow, 1.5,
                PlatformerPathPoint(
                  x: origin.x + (nCol + 0.5) * map.tileWidth,
                  y: origin.y + (nRow + 0.5) * map.tileHeight,
                  moveType: PlatformerMoveType.jump,
                  jumpRequired: true,
                  climbRequired: false,
                  jumpPeakY: _estimateJumpPeakY(row, nRow),
                ),
              ));
            }
          }
        }
      }

      // Ladder climbing
      if (config.canClimbLadders) {
        // Climb up
        if (row > 0 && isLadder(col, row) && isLadder(col, row - 1) && !isSolid(col, row - 1)) {
          neighbors.add(_Neighbor(
            col, row - 1, 1.2,
            PlatformerPathPoint(
              x: origin.x + (col + 0.5) * map.tileWidth,
              y: origin.y + (row - 1 + 0.5) * map.tileHeight,
              moveType: PlatformerMoveType.climb,
              jumpRequired: false,
              climbRequired: true,
              onLadder: true,
            ),
          ));
        }
        // Climb down
        if (row + 1 < map.rows && isLadder(col, row) && isLadder(col, row + 1) && !isSolid(col, row + 1)) {
          neighbors.add(_Neighbor(
            col, row + 1, 1.2,
            PlatformerPathPoint(
              x: origin.x + (col + 0.5) * map.tileWidth,
              y: origin.y + (row + 1 + 0.5) * map.tileHeight,
              moveType: PlatformerMoveType.climb,
              jumpRequired: false,
              climbRequired: true,
              onLadder: true,
            ),
          ));
        }
        // Enter ladder from ground
        if (hasGroundAt(col, row) && isLadder(col, row) && !isSolid(col, row)) {
          neighbors.add(_Neighbor(
            col, row, 1.2,
            PlatformerPathPoint(
              x: origin.x + (col + 0.5) * map.tileWidth,
              y: origin.y + (row + 0.5) * map.tileHeight,
              moveType: PlatformerMoveType.climb,
              jumpRequired: false,
              climbRequired: true,
              onLadder: true,
            ),
          ));
        }
      }

      // Drop through one-way platform
      if (config.canDropThroughOneWay && isOnOneWay(col, row) && !isSolid(col, row + 1)) {
        neighbors.add(_Neighbor(
          col, row + 1, 1.0,
          PlatformerPathPoint(
            x: origin.x + (col + 0.5) * map.tileWidth,
            y: origin.y + (row + 1 + 0.5) * map.tileHeight,
            moveType: PlatformerMoveType.dropThrough,
            jumpRequired: false,
            climbRequired: false,
          ),
        ));
      }

      // Fall off ledge (walk off edge) - check for ground within max fall distance
      final maxFallRows = config.maxJumpFallTiles;
      for (final dc in [-1, 1]) {
        final nCol = col + dc;
        if (nCol < 0 || nCol >= map.cols) continue;
        if (!hasGroundAt(col, row)) continue; // Must be on ground at start
        if (hasGroundAt(nCol, row)) continue; // Target column has ground at same level (not a ledge)
        if (isSolid(nCol, row)) continue; // Target blocked at same level
        // Check for ground below in target column within fall distance
        for (int dr = 1; dr <= maxFallRows; dr++) {
          final nRow = row + dr;
          if (nRow >= map.rows) break;
          if (hasGroundAt(nCol, nRow)) {
            // Found ground below - can fall to this position
            neighbors.add(_Neighbor(
              nCol, nRow, 1.0,
              PlatformerPathPoint(
                x: origin.x + (nCol + 0.5) * map.tileWidth,
                y: origin.y + (nRow + 0.5) * map.tileHeight,
                moveType: PlatformerMoveType.fall,
                jumpRequired: false,
                climbRequired: false,
              ),
            ));
            break; // Only add the first ground found (closest)
          }
          // If we hit a solid tile before finding ground, can't fall through it
          if (isSolid(nCol, nRow)) break;
        }
      }

      return neighbors;
    }

    List<PlatformerPathPoint> _reconstructPath(
      Map<int, int> cameFrom,
      Map<int, PlatformerPathPoint> cameFromMove,
      int startKey,
      int goalKey,
    ) {
      final path = <PlatformerPathPoint>[];
      var currentKey = goalKey;
      while (currentKey != startKey) {
        final move = cameFromMove[currentKey];
        if (move != null) path.add(move);
        currentKey = cameFrom[currentKey]!;
      }
      return path.reversed.toList();
    }

    final startCol = colOf(fromX);
    final startRow = rowOf(fromY);
    final goalCol = colOf(toX);
    final goalRow = rowOf(toY);

    if (startCol == goalCol && startRow == goalRow) return <PlatformerPathPoint>[];
    if (isSolid(goalCol, goalRow)) return <PlatformerPathPoint>[];
    if (isOneWay(goalCol, goalRow) && !config.canDropThroughOneWay) return <PlatformerPathPoint>[];

    final startKey = key(startCol, startRow);
    final goalKey = key(goalCol, goalRow);

    final gScore = <int, double>{startKey: 0};
    final cameFrom = <int, int>{};
    final cameFromMove = <int, PlatformerPathPoint>{};
    final open = _MinHeap()..add(_Node(startCol, startRow, _heuristic(startCol, startRow, goalCol, goalRow)));
    final closed = <int>{};

    while (open.isNotEmpty) {
      final current = open.removeMin();
      final currentKey = key(current.col, current.row);

      if (currentKey == goalKey) {
        return _reconstructPath(cameFrom, cameFromMove, startKey, currentKey);
      }

      if (!closed.add(currentKey)) continue;

      final neighbors = _getNeighbors(current.col, current.row);
      for (final neighbor in neighbors) {
        final nKey = key(neighbor.col, neighbor.row);
        if (closed.contains(nKey)) continue;

        final tentativeG = gScore[currentKey]! + neighbor.cost;
        if (tentativeG < (gScore[nKey] ?? double.infinity)) {
          gScore[nKey] = tentativeG;
          cameFrom[nKey] = currentKey;
          cameFromMove[nKey] = neighbor.moveType;
          open.add(_Node(neighbor.col, neighbor.row, tentativeG + _heuristic(neighbor.col, neighbor.row, goalCol, goalRow)));
        }
      }
    }

    return <PlatformerPathPoint>[];
  }
}

/// Extension on [World] to provide platformer-aware pathfinding.
extension PlatformerPathfindingExtension on World {
  /// Finds a platformer-aware path using the [PlatformerPathfinder].
  ///
  /// This is a convenience method that creates a [PlatformerPathfinder] with
  /// the given [config] (or default) and calls [findPath] with the provided
  /// parameters.
  List<PlatformerPathPoint> findPlatformerPath({
    required TileMap map,
    required Position origin,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required Set<int> ladderTileIds,
    required Set<int> oneWayTileIds,
    List<MovingPlatformInfo> movingPlatforms = const [],
    PlatformerPathfinderConfig? config,
  }) {
    final finder = config != null ? PlatformerPathfinder(config) : PlatformerPathfinder(const PlatformerPathfinderConfig());
    return finder.findPath(
      map: map,
      origin: origin,
      fromX: fromX,
      fromY: fromY,
      toX: toX,
      toY: toY,
      ladderTileIds: ladderTileIds,
      oneWayTileIds: oneWayTileIds,
      movingPlatforms: movingPlatforms,
    );
  }
}