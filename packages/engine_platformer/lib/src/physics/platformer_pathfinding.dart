import 'package:engine_core/engine_core.dart';
import 'platformer_controller.dart';

/// Platformer-aware A* pathfinding.
///
/// Extends the tile-based A* in `engine_core/src/physics/pathfinding.dart`
/// with platformer-specific movement capabilities:
/// - Jumps (configurable max jump height/distance)
/// - One-way platforms (can jump through from below, land on top)
/// - Ladders (vertical movement)
/// - Falling (can drop from ledges)
///
/// Output: sequence of [PlatformerPathPoint] with [jumpRequired], [climbRequired],
/// and [fallRequired] flags consumable by a platformer movement behavior.
class _Node {
  final int col;
  final int row;
  final double f;
  _Node(this.col, this.row, this.f);
}

class _MinHeap {
  final List<_Node> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(_Node node) {
    _items.add(node);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_items[i].f >= _items[parent].f) break;
      _swap(i, parent);
      i = parent;
    }
  }

  _Node removeMin() {
    final min = _items[0];
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      final n = _items.length;
      while (true) {
        final left = 2 * i + 1;
        final right = 2 * i + 2;
        var smallest = i;
        if (left < n && _items[left].f < _items[smallest].f) smallest = left;
        if (right < n && _items[right].f < _items[smallest].f) smallest = right;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return min;
  }

  void _swap(int a, int b) {
    final tmp = _items[a];
    _items[a] = _items[b];
    _items[b] = tmp;
  }
}

class PlatformerPathfinder {
  final PlatformerPathfinderConfig config;

  PlatformerPathfinder(this.config);

  /// Finds a path from [fromX]/[fromY] to [toX]/[toY] considering platformer physics.
  ///
  /// Returns waypoints from the step *after* the start cell through the
  /// goal cell (inclusive), as world-space positions with movement flags.
  /// Empty if no path exists or start/goal are in same cell.
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

    final startCol = colOf(fromX);
    final startRow = rowOf(fromY);
    final goalCol = colOf(toX);
    final goalRow = rowOf(toY);

    if (startCol == goalCol && startRow == goalRow) {
      return [];
    }

    // Check if goal is reachable (not inside solid)
    if (_isSolidAt(map, goalCol, goalRow)) {
      return [];
    }

    int key(int col, int row) => row * map.cols + col;
    final startKey = key(startCol, startRow);
    final goalKey = key(goalCol, goalRow);

    final gScore = <int, double>{startKey: 0};
    final cameFrom = <int, int>{};
    final actionToReach = <int, _MovementAction>{};
    final open = _MinHeap()..add(_Node(startCol, startRow, _heuristic(startCol, startRow, goalCol, goalRow)));
    final closed = <int>{};

    while (open.isNotEmpty) {
      final current = open.removeMin();
      final currentKey = key(current.col, current.row);

      if (currentKey == goalKey) {
        return _reconstructPath(cameFrom, actionToReach, startKey, currentKey, map, origin);
      }

      if (!closed.add(currentKey)) continue;

      final neighbors = _getNeighbors(map, current.col, current.row, ladderTileIds, oneWayTileIds);
      for (final neighbor in neighbors) {
        final nKey = key(neighbor.col, neighbor.row);
        if (closed.contains(nKey)) continue;

        final tentativeG = gScore[currentKey]! + neighbor.cost;
        if (tentativeG < (gScore[nKey] ?? double.infinity)) {
          gScore[nKey] = tentativeG;
          cameFrom[nKey] = currentKey;
          actionToReach[nKey] = neighbor.action;
          open.add(_Node(neighbor.col, neighbor.row, tentativeG + _heuristic(neighbor.col, neighbor.row, goalCol, goalRow)));
        }
      }
    }

    return []; // goal unreachable
  }

  /// Gets valid neighboring cells from the current position based on platformer movement rules.
  List<_Neighbor> _getNeighbors(
    TileMap map,
    int col,
    int row,
    Set<int> ladderTileIds,
    Set<int> oneWayTileIds,
  ) {
    final neighbors = <_Neighbor>[];
    final tileWidth = map.tileWidth;
    final tileHeight = map.tileHeight;

    // Helper to check tile types
    bool isSolid(int c, int r) {
      if (c < 0 || c >= map.cols || r < 0 || r >= map.rows) return true;
      return map.solidTileIds.contains(map.tileAt(c, r));
    }

    bool isOneWay(int c, int r) {
      if (c < 0 || c >= map.cols || r < 0 || r >= map.rows) return false;
      return oneWayTileIds.contains(map.tileAt(c, r));
    }

    bool isLadder(int c, int r) {
      if (c < 0 || c >= map.cols || r < 0 || r >= map.rows) return false;
      return ladderTileIds.contains(map.tileAt(c, r));
    }

    // Current cell center
    final cellCenterX = col * tileWidth + tileWidth / 2;
    final cellCenterY = row * tileHeight + tileHeight / 2;

    // 1. Horizontal movement (walk left/right)
    for (final dc in [-1, 1]) {
      final nCol = col + dc;
      final nRow = row;

      // Can walk if:
      // - Target cell is not solid
      // - Current cell has ground (standing on solid or one-way)
      // - Target cell has ground at same level OR can step up/down 1 tile
      if (!_isSolidAt(map, nCol, nRow)) {
        final hasGroundHere = _hasGround(map, col, row, oneWayTileIds);
        final hasGroundThere = _hasGround(map, nCol, nRow, oneWayTileIds);

        if (hasGroundHere && hasGroundThere) {
          neighbors.add(_Neighbor(nCol, nRow, 1.0, _MovementAction.walk));
        }
        // Step up (one tile higher)
        else if (hasGroundHere && !isSolid(nCol, nRow - 1) && _hasGround(map, nCol, nRow - 1, oneWayTileIds)) {
          neighbors.add(_Neighbor(nCol, nRow - 1, 1.2, _MovementAction.walk));
        }
        // Step down (one tile lower)
        else if (hasGroundHere && !isSolid(nCol, nRow + 1) && _hasGround(map, nCol, nRow + 1, oneWayTileIds)) {
          neighbors.add(_Neighbor(nCol, nRow + 1, 1.2, _MovementAction.walk));
        }
        // Walk off ledge: target has no ground, but we can walk there and fall
        else if (hasGroundHere && !hasGroundThere && !_isSolidAt(map, nCol, nRow + 1)) {
          // Target cell is empty and has no ground below - walk off and fall
          // Find landing spot
          int fallRow = nRow + 1;
          while (fallRow < map.rows && !_isSolidAt(map, nCol, fallRow) && !_hasGround(map, nCol, fallRow, oneWayTileIds)) {
            fallRow++;
          }
          if (fallRow < map.rows && !_isSolidAt(map, nCol, fallRow) && _hasGround(map, nCol, fallRow, oneWayTileIds)) {
            final fallDist = fallRow - nRow;
            neighbors.add(_Neighbor(nCol, fallRow, 1.0 + fallDist * 0.1, _MovementAction.walkOffLedge));
          }
        }
      }
    }

    // 2. Jump movement
    if (config.maxJumpHeight > 0) {
      final hasGroundHere = _hasGround(map, col, row, oneWayTileIds);

      if (hasGroundHere) {
        // Try jumping to reachable cells within jump arc
        for (final dc in [-1, 1]) {
          for (int jumpDist = 1; jumpDist <= config.maxJumpHorizontalTiles; jumpDist++) {
            final nCol = col + dc * jumpDist;
            if (nCol < 0 || nCol >= map.cols) break;

            // Check jump arc - can we reach target row?
            for (int verticalOffset = -config.maxJumpHeightTiles; verticalOffset <= 1; verticalOffset++) {
              final nRow = row + verticalOffset;
              if (nRow < 0 || nRow >= map.rows) continue;

              if (!_isSolidAt(map, nCol, nRow) && _hasGround(map, nCol, nRow, oneWayTileIds)) {
                // Verify jump arc doesn't hit ceiling
                if (_isJumpArcClear(map, col, row, nCol, nRow, tileWidth, tileHeight, oneWayTileIds)) {
                  final cost = 1.5 + jumpDist * 0.3 + verticalOffset.abs() * 0.2;
                  neighbors.add(_Neighbor(nCol, nRow, cost, _MovementAction.jump));
                }
              }
            }
          }
        }
      }
    }

    // 3. Ladder climbing
    if (isLadder(col, row)) {
      // Can climb up
      if (!_isSolidAt(map, col, row - 1)) {
        neighbors.add(_Neighbor(col, row - 1, 1.0, _MovementAction.climb));
      }
      // Can climb down
      if (!_isSolidAt(map, col, row + 1)) {
        neighbors.add(_Neighbor(col, row + 1, 1.0, _MovementAction.climb));
      }
      // Can step off ladder horizontally
      for (final dc in [-1, 1]) {
        final nCol = col + dc;
        if (!_isSolidAt(map, nCol, row) && _hasGround(map, nCol, row, oneWayTileIds)) {
          neighbors.add(_Neighbor(nCol, row, 1.0, _MovementAction.walk));
        }
      }
    }

    // 4. Falling / dropping down
    final hasGroundHere = _hasGround(map, col, row, oneWayTileIds);
    // Skip fall logic if on one-way platform (dropThrough handles that)
    final onOneWay = _isOnOneWay(map, col, row, oneWayTileIds);
    if (hasGroundHere && !onOneWay) {
      // Check if we can drop down (fall off ledge)
      if (!_isSolidAt(map, col, row + 1)) {
        // Can fall down - find landing spot
        int fallRow = row + 1;
        while (fallRow < map.rows && !_isSolidAt(map, col, fallRow) && !_hasGround(map, col, fallRow, oneWayTileIds)) {
          fallRow++;
        }
        if (fallRow < map.rows && !_isSolidAt(map, col, fallRow) && _hasGround(map, col, fallRow, oneWayTileIds)) {
          neighbors.add(_Neighbor(col, fallRow, 1.0 + (fallRow - row) * 0.1, _MovementAction.fall));
        }
      }
    }

    // 5. Drop through one-way platform
    if (hasGroundHere && _isOnOneWay(map, col, row, oneWayTileIds)) {
      // Can drop through by pressing down
      if (!_isSolidAt(map, col, row + 1)) {
        int fallRow = row + 1;
        while (fallRow < map.rows && !_isSolidAt(map, col, fallRow) && !_hasGround(map, col, fallRow, oneWayTileIds)) {
          fallRow++;
        }
        if (fallRow < map.rows && !_isSolidAt(map, col, fallRow) && _hasGround(map, col, fallRow, oneWayTileIds)) {
          neighbors.add(_Neighbor(col, fallRow, 1.0 + (fallRow - row) * 0.1, _MovementAction.dropThrough));
        }
      }
    }

    return neighbors;
  }

  bool _isSolidAt(TileMap map, int col, int row) {
    if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return true;
    return map.solidTileIds.contains(map.tileAt(col, row));
  }

  bool _hasGround(TileMap map, int col, int row, Set<int> oneWayTileIds) {
    // Check if there's ground at or below the entity's position.
    // Ground can be:
    // 1. A solid tile directly below (row + 1)
    // 2. A one-way platform directly below (row + 1)
    // 3. A one-way platform at the current row (entity standing on it)
    if (row < 0 || row >= map.rows) return false;
    
    // Check current tile (for standing on one-way platforms)
    final currentTile = map.tileAt(col, row);
    if (oneWayTileIds.contains(currentTile)) {
      return true;
    }
    
    // Check tile below
    if (row + 1 < map.rows) {
      final tileBelow = map.tileAt(col, row + 1);
      if (map.solidTileIds.contains(tileBelow) || oneWayTileIds.contains(tileBelow)) {
        return true;
      }
    }
    
    return false;
  }

  bool _isOnOneWay(TileMap map, int col, int row, Set<int> oneWayTileIds) {
    if (row < 0 || row >= map.rows) return false;
    // Check if current tile is a one-way platform (entity standing on it)
    return oneWayTileIds.contains(map.tileAt(col, row));
  }

  bool _isJumpArcClear(
    TileMap map,
    int fromCol,
    int fromRow,
    int toCol,
    int toRow,
    double tileWidth,
    double tileHeight,
    Set<int> oneWayTileIds,
  ) {
    // Check if direct line of sight exists (no solid tiles blocking)
    // One-way platforms don't block jumps from below, only from above.
    // We use blockOneWay: false to allow jumping through one-way platforms.
    final origin = Position(0, 0);
    return raycastTileMap(
      map,
      origin,
      fromCol * tileWidth + tileWidth / 2,
      fromRow * tileHeight + tileHeight / 2,
      toCol * tileWidth + tileWidth / 2,
      toRow * tileHeight + tileHeight / 2,
      blockOneWay: false,
    ) == null;
  }

  List<PlatformerPathPoint> _reconstructPath(
    Map<int, int> cameFrom,
    Map<int, _MovementAction> actionToReach,
    int startKey,
    int goalKey,
    TileMap map,
    Position origin,
  ) {
    final path = <PlatformerPathPoint>[];
    var k = goalKey;

    while (k != startKey) {
      final col = k % map.cols;
      final row = k ~/ map.cols;
      final action = actionToReach[k] ?? _MovementAction.walk;

      path.add(PlatformerPathPoint(
        origin.x + col * map.tileWidth + map.tileWidth / 2,
        origin.y + row * map.tileHeight + map.tileHeight / 2,
        jumpRequired: action == _MovementAction.jump,
        climbRequired: action == _MovementAction.climb,
        fallRequired: action == _MovementAction.fall ||
            action == _MovementAction.dropThrough ||
            action == _MovementAction.walkOffLedge,
        dropThroughOneWay: action == _MovementAction.dropThrough,
      ));
      k = cameFrom[k]!;
    }

    return path.reversed.toList();
  }

  double _heuristic(int c1, int r1, int c2, int r2) =>
      (c1 - c2).abs().toDouble() + (r1 - r2).abs().toDouble();
}

/// Configuration for platformer pathfinding.
class PlatformerPathfinderConfig {
  /// Maximum horizontal tiles a jump can cover.
  final int maxJumpHorizontalTiles;

  /// Maximum vertical tiles a jump can reach (upwards).
  final int maxJumpHeightTiles;

  /// Maximum jump height in world units (for arc calculation).
  final double maxJumpHeight;

  PlatformerPathfinderConfig({
    this.maxJumpHorizontalTiles = 6,
    this.maxJumpHeightTiles = 4,
    this.maxJumpHeight = 200,
  });
}

/// Movement action type for path reconstruction.
enum _MovementAction {
  walk,
  walkOffLedge,
  jump,
  climb,
  fall,
  dropThrough,
}

/// Neighbor cell with movement cost and action.
class _Neighbor {
  final int col;
  final int row;
  final double cost;
  final _MovementAction action;

  _Neighbor(this.col, this.row, this.cost, this.action);
}

/// A path point with platformer-specific movement flags.
class PlatformerPathPoint extends PathPoint {
  final bool fallRequired;
  final bool dropThroughOneWay;

  PlatformerPathPoint(
    double x,
    double y, {
    bool jumpRequired = false,
    bool climbRequired = false,
    this.fallRequired = false,
    this.dropThroughOneWay = false,
  }) : super(x, y, jumpRequired: jumpRequired, climbRequired: climbRequired);
}

/// Info about a moving platform for pathfinding.
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

/// Extension to provide platformer pathfinding on World.
extension PlatformerPathfindingWorld on World {
  List<PlatformerPathPoint> findPlatformerPath({
    required TileMap map,
    required Position origin,
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required Set<int> ladderTileIds,
    required Set<int> oneWayTileIds,
    PlatformerPathfinderConfig? config,
    List<MovingPlatformInfo> movingPlatforms = const [],
  }) {
    final finder = PlatformerPathfinder(config ?? PlatformerPathfinderConfig());
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