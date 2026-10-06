import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// A 5x3 map, tileWidth/tileHeight 10, so the cell (c, r) centre is at
/// (c * 10 + 5, r * 10 + 5). Tile id 1 is solid, 0 is empty.
TileMap _map(List<List<int>> rows) {
  final flat = [for (final row in rows) ...row];
  return TileMap.fromJson({
    'cols': 5,
    'rows': rows.length,
    'tileWidth': 10.0,
    'tileHeight': 10.0,
    'tiles': flat,
    'solidTileIds': [1],
    'oneWayTileIds': <int>[],
    'slopeUpRightTileIds': <int>[],
    'slopeUpLeftTileIds': <int>[],
    'ladderTileIds': <int>[],
    'conveyorSpeedByTileId': <String, double>{},
    'frictionByTileId': <String, double>{},
    'regionByTileId': <String, String>{},
    'zIndex': 0,
    'tileAnimationFps': 6.0,
  });
}

bool _reach(TileMap map, int fromCol, int fromRow, int toCol, int toRow) =>
    isTileReachable(
      map,
      startX: fromCol * 10.0 + 5,
      startY: fromRow * 10.0 + 5,
      targetX: toCol * 10.0 + 5,
      targetY: toRow * 10.0 + 5,
    );

void main() {
  group('isTileReachable', () {
    test('walks along an open floor', () {
      final map = _map([
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 0, 1, 4, 1), isTrue);
    });

    test('a wall the full height of the map blocks the way', () {
      final map = _map([
        [0, 0, 1, 0, 0],
        [0, 0, 1, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 1, 1, 4, 1), isFalse);
    });

    test('jumps over a one-tile step', () {
      final map = _map([
        [0, 0, 0, 0, 0],
        [0, 0, 1, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 1, 1, 4, 1), isTrue);
    });

    test(
      'a jump cannot clear a wall taller than its height, nor land past it',
      () {
        // The wall reaches the top of the map, so no jump can rise over it. A
        // teleporting jump would land on the far side regardless.
        final map = _map([
          [0, 0, 1, 0, 0],
          [0, 0, 1, 0, 0],
          [0, 0, 1, 0, 0],
          [1, 1, 1, 1, 1],
        ]);
        expect(_reach(map, 1, 2, 4, 2), isFalse);
      },
    );

    test('lands on top of a wall that a jump can rise over', () {
      final map = _map([
        [0, 0, 0, 0, 0],
        [0, 0, 1, 0, 0],
        [0, 0, 1, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 1, 2, 2, 0), isTrue);
    });

    test('a start or target outside the map is unreachable', () {
      final map = _map([
        [0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 0, 0, 9, 0), isFalse);
    });

    test('a start inside solid ground is unreachable', () {
      final map = _map([
        [0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ]);
      expect(_reach(map, 0, 1, 4, 0), isFalse);
    });
  });

  group('LevelValidator exit reachability', () {
    LevelDocument level(List<List<int>> rows, {required double exitX}) {
      final flat = [for (final row in rows) ...row];
      return LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'position': {'x': 0.0, 'y': 0.0},
              'tileMap': {
                'cols': 5,
                'rows': rows.length,
                'tileWidth': 10.0,
                'tileHeight': 10.0,
                'tiles': flat,
                'solidTileIds': [1],
                'oneWayTileIds': <int>[],
                'slopeUpRightTileIds': <int>[],
                'slopeUpLeftTileIds': <int>[],
                'ladderTileIds': <int>[],
                'conveyorSpeedByTileId': <String, double>{},
                'frictionByTileId': <String, double>{},
                'regionByTileId': <String, String>{},
                'zIndex': 0,
                'tileAnimationFps': 6.0,
              },
            },
          },
          {
            'name': 'player',
            'components': {
              'position': {'x': 15.0, 'y': 15.0},
            },
          },
          {
            'name': 'exit',
            'components': {
              'position': {'x': exitX, 'y': 15.0},
              'roomExit': {'targetSceneId': 'next', 'spawnPoint': 'entrance'},
            },
          },
        ],
      });
    }

    final validator = LevelValidator.forRegistry(() {
      final world = World(width: 800, height: 480);
      registerCoreComponents(world);
      return world.components;
    }());

    test('warns when an exit is walled off from the player', () {
      final doc = level([
        [0, 0, 1, 0, 0],
        [0, 0, 1, 0, 0],
        [1, 1, 1, 1, 1],
      ], exitX: 45);
      final issues = validator.validate(doc);
      expect(issues, hasLength(1));
      expect(issues.single.severity, IssueSeverity.warning);
      expect(issues.single.entityName, 'exit');
    });

    test('reports no reachability issue when the exit is reachable', () {
      final doc = level([
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ], exitX: 45);
      expect(validator.validate(doc), isEmpty);
    });
  });
}
