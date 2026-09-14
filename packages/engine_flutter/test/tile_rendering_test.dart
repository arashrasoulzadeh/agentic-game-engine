import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(8, 8);
}

void main() {
  testWidgets('EngineView renders a world containing a TileMap without error',
      (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 4,
            rows: 4,
            tileWidth: 20,
            tileHeight: 20,
            tiles: [
              0, 0, 0, 0, //
              0, 1, 2, 0, //
              0, 0, 0, 0, //
              1, 1, 1, 1, //
            ],
            solidTileIds: {1},
            oneWayTileIds: {2},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
    'a ladder tile renders without error, distinct from solid/one-way/slope tiles',
    (tester) async {
      final world = World(width: 400, height: 400);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 4,
              rows: 1,
              tileWidth: 20,
              tileHeight: 20,
              tiles: [1, 2, 3, 4],
              solidTileIds: {1},
              oneWayTileIds: {2},
              ladderTileIds: {3},
              slopeUpRightTileIds: {4},
            ),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    },
  );

  testWidgets('a tile with a registered atlasId/regionByTileId entry draws the real '
      'texture instead of the flat debug color, without error', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('tileset', SpriteAtlas(await _tinyImage(), {
      'grass': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 2,
            rows: 2,
            tileWidth: 20,
            tileHeight: 20,
            tiles: [1, 0, 0, 1],
            solidTileIds: {1},
            atlasId: 'tileset',
            regionByTileId: {1: 'grass'},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
      'a tile id with no regionByTileId entry falls back to the flat color even '
      'when atlasId is set and loaded', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('tileset', SpriteAtlas(await _tinyImage(), {
      'grass': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 2,
            rows: 1,
            tileWidth: 20,
            tileHeight: 20,
            // Tile id 2 is solid but has no regionByTileId entry.
            tiles: [1, 2],
            solidTileIds: {1, 2},
            atlasId: 'tileset',
            regionByTileId: {1: 'grass'},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
      'atlasId set but not yet registered in AtlasRegistry falls back to flat color, '
      'not a crash', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 1,
            rows: 1,
            tileWidth: 20,
            tileHeight: 20,
            tiles: [1],
            solidTileIds: {1},
            atlasId: 'not-yet-loaded',
            regionByTileId: {1: 'grass'},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      // Empty registry -- 'not-yet-loaded' was never registered.
      home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
    'a TileMap far bigger than the viewport still renders promptly (tile culling)',
    (tester) async {
      // 2000x2000 = 4,000,000 tiles -- without culling to the visible
      // range, EngineView would walk every one of them every frame
      // regardless of how few are actually on screen. With culling,
      // render time depends on the (small, fixed) viewport size, not
      // total map size, so this stays fast even at this scale.
      const cols = 2000;
      const rows = 2000;
      final world = World(width: 400, height: 400);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: cols,
              rows: rows,
              tileWidth: 20,
              tileHeight: 20,
              tiles: List.filled(cols * rows, 1),
              solidTileIds: {1},
            ),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));

      final stopwatch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      stopwatch.stop();

      expect(find.byType(EngineView), findsOneWidget);
      // Generous bound (a culled frame should take low milliseconds) --
      // this is a regression guard against culling silently regressing
      // back into an uncapped per-tile walk, not a precise perf number.
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    },
  );
}
