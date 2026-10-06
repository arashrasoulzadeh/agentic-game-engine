import 'dart:ui';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/level/level_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 100.0, 'y': 50.0},
        'tileMap': {
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['..#', '###'],
        },
      },
    },
    {
      'name': 'player',
      'components': {
        'position': {'x': 120.0, 'y': 60.0},
      },
    },
    {
      'name': 'coin',
      'components': {
        'position': {'x': 120.0, 'y': 60.0},
      },
    },
    {
      'name': 'floating',
      'components': {
        'position': {'x': 'left', 'y': 0.0},
      },
    },
  ],
});

void main() {
  test('reads the tile map and its origin from the document', () {
    final geometry = LevelGeometry.of(_level());
    expect(geometry.tileMap, isNotNull);
    expect(geometry.tileMap!.cols, 3);
    expect(geometry.tileOrigin, const Offset(100, 50));
    expect(geometry.tileSize, const Size(16, 16));
  });

  test(
    'positions every entity whose position is readable, and skips the rest',
    () {
      final geometry = LevelGeometry.of(_level());
      expect(geometry.entityPositions.keys, containsAll([0, 1, 2]));
      expect(
        geometry.entityPositions.containsKey(3),
        isFalse,
        reason: 'a non-numeric position has no place on the canvas',
      );
    },
  );

  test('a level without a tile map still has geometry for its entities', () {
    final doc = LevelDocument.fromJson({
      'entities': [
        {
          'components': {
            'position': {'x': 5.0, 'y': 6.0},
          },
        },
      ],
    });
    final geometry = LevelGeometry.of(doc);
    expect(geometry.tileMap, isNull);
    expect(geometry.entityPositions[0], const Offset(5, 6));
  });

  test(
    'a malformed tile map is treated as absent, so the view still opens',
    () {
      final doc = LevelDocument.fromJson({
        'entities': [
          {
            'components': {
              'tileMap': {'legend': 'nope'},
            },
          },
        ],
      });
      expect(LevelGeometry.of(doc).tileMap, isNull);
    },
  );

  test('entityAt picks the nearest entity within the pick radius', () {
    final geometry = LevelGeometry.of(_level());
    expect(
      geometry.entityAt(const Offset(121, 61)),
      1,
      reason: 'player and coin share a position; the earlier one wins',
    );
    expect(geometry.entityAt(const Offset(0, 0)), isNull);
  });

  test('entityAt returns null just outside the pick radius', () {
    final geometry = LevelGeometry.of(_level());
    expect(geometry.entityAt(const Offset(120, 60 + 13)), isNull);
    expect(geometry.entityAt(const Offset(120, 60 + 11)), 1);
  });
}
