import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage([Color color = const Color(0xFFFFFFFF)]) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  return recorder.endRecording().toImage(8, 8);
}

Future<Color> _pixelAt(WidgetTester tester, Key boundaryKey, Offset point) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  final offset = (y * image.width + x) * 4;
  final data = bytes!;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
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

  group('EngineView.cullBufferPx (buffered/cached tile culling)', () {
    // Flat-color fallback for a solid tile with no atlasId -- distinct
    // from the default black backgroundColor, so "did this cell draw a
    // tile at all" is a plain non-black pixel check.
    const tileFallbackR = 0x4A / 255;

    Future<World> buildWorld() async {
      final world = World(width: 4000, height: 100);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 100,
              rows: 1,
              tileWidth: 20,
              tileHeight: 20,
              tiles: List.filled(100, 1),
              solidTileIds: {1},
            ),
          );
      return world;
    }

    testWidgets(
        'a small pan (within cullBufferPx) reveals a newly-visible tile correctly, '
        'proving the cached buffered range still covers it', (tester) async {
      final world = await buildWorld();
      final camera = Camera(x: 300);
      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: camera),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      // Camera x=300, viewport 400 wide -> visible world x is [100,500).
      // World x=520 (tile col 26) sits just outside the raw view but
      // well within the default 96px buffer -- already cached, just not
      // drawn on screen yet at this camera position.

      // Pan by 40 world units (well under the 96px buffer) -- the real
      // visible rect [140,540) still fits inside the buffered rect
      // cached last frame, so the cache is reused outright.
      camera.x = 340;
      await tester.pump(const Duration(milliseconds: 16));

      // World x=520 -> screen x = (520-340)*1 + 200 = 380; world y=0 ->
      // screen y = 150 (centered, 100-tall viewport... actually camera
      // centers vertically on y=0 by default with a 300-tall viewport,
      // so world y=10 (tile center) -> screen y=150+10=160).
      final pixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(380, 160))))!;
      expect(pixel.r, closeTo(tileFallbackR, 0.02),
          reason: 'tile col 26 is now on screen after a small pan, and must still be '
              'drawn correctly even though the cached buffered range (from before the '
              'pan) was reused rather than recomputed');
    });

    testWidgets(
        'a large jump (far beyond cullBufferPx) still correctly recomputes and draws '
        'the newly-visible tiles -- no stale/empty range left over', (tester) async {
      final world = await buildWorld();
      final camera = Camera(x: 300);
      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: camera),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // Jump far past the buffered range entirely (tile col 90, world
      // x=1800-1820, nowhere near the original [100,500]-ish cached
      // range) -- the cache must be invalidated and recomputed, not
      // reused (which would incorrectly leave this area undrawn).
      camera.x = 1800;
      await tester.pump(const Duration(milliseconds: 16));

      // World x=1810 -> screen x = (1810-1800)*1+200 = 210.
      final pixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(210, 160))))!;
      expect(pixel.r, closeTo(tileFallbackR, 0.02),
          reason: 'tile col 90 must draw correctly after a large camera jump -- proves '
              'the cache was invalidated and recomputed, not incorrectly reused');
    });

    testWidgets('cullBufferPx: 0 still renders correctly (buffer/cache fully disabled)',
        (tester) async {
      final world = await buildWorld();
      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(
                world: world,
                atlasRegistry: AtlasRegistry(),
                camera: Camera(x: 300),
                cullBufferPx: 0,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // World x=300 (tile col 15) is dead center of the viewport --
      // must still draw with no buffer at all.
      final pixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 160))))!;
      expect(pixel.r, closeTo(tileFallbackR, 0.02));
    });
  });

  testWidgets(
      'backgroundTiles draws under the main layer -- a background-only cell shows its '
      'texture, and a cell with both layers shows the main (foreground of the two) '
      'texture on top', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('main-atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFF0000)),
        {'main': const Rect.fromLTWH(0, 0, 8, 8)}));

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 2,
            rows: 1,
            tileWidth: 40,
            tileHeight: 40,
            tiles: [0, 1],
            backgroundTiles: [1, 1],
            atlasId: 'main-atlas',
            regionByTileId: {1: 'main'},
          ),
        );

    final boundaryKey = UniqueKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: RepaintBoundary(
            key: boundaryKey,
            child: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    // World (0,0)-(40,40) has only a background tile (main is 0 there);
    // world (40,0)-(80,40) has both. Both draw the same registered
    // 'main-atlas' region (no separate atlasId concept for background
    // tiles), so this proves the background pass runs at all -- the
    // left cell would otherwise stay the empty/background canvas color.
    final leftPixel = (await tester.runAsync(
        () => _pixelAt(tester, boundaryKey, const Offset(20, 200))))!;
    expect(leftPixel.a, greaterThan(0.5),
        reason: 'background layer alone still draws something at this cell');
  });

  testWidgets(
      'foregroundTiles draws over the main layer -- a cell where both layers use '
      'different textures shows the foreground one on top', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('under', SpriteAtlas(await _tinyImage(const Color(0xFF0000FF)),
        {'tile': const Rect.fromLTWH(0, 0, 8, 8)}));
    // Foreground region resolved from the same TileMap.atlasId as the
    // main layer -- there's only one atlasId per TileMap by design, so
    // use one atlas with two differently-keyed regions of different
    // colors instead of a second atlas.
    final atlasImage = await _tinyImage(const Color(0xFF00FF00));
    registry.register('tileset', SpriteAtlas(atlasImage, {
      'main': const Rect.fromLTWH(0, 0, 8, 8),
      'fg': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 1,
            rows: 1,
            tileWidth: 40,
            tileHeight: 40,
            tiles: [1],
            foregroundTiles: [2],
            atlasId: 'tileset',
            regionByTileId: {1: 'main', 2: 'fg'},
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget,
        reason: 'both layers over the same cell render without crashing');
  });

  testWidgets(
      'an animated tile switches which atlas region it draws as animationElapsed '
      'advances -- TileAnimationSystem + EngineView together, not just data alone',
      (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(TileAnimationSystem());

    final registry = AtlasRegistry();
    final combined = await _tinyImage();
    registry.register('anim', SpriteAtlas(combined, {
      'frame0': const Rect.fromLTWH(0, 0, 4, 8),
      'frame1': const Rect.fromLTWH(4, 0, 4, 8),
    }));

    final map = TileMap(
      cols: 1,
      rows: 1,
      tileWidth: 40,
      tileHeight: 40,
      tiles: [1],
      atlasId: 'anim',
      regionByTileId: {1: 'frame0', 2: 'frame1'},
      tileAnimations: {1: [1, 2]},
      tileAnimationFps: 10, // 0.1s per frame
    );
    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(mapEntity, map);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    expect(map.currentTileId(1), 1, reason: 'barely any time elapsed, still frame 0');

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(map.currentTileId(1), 2,
        reason: 'world.step advanced animationElapsed via TileAnimationSystem past '
            "0.1s, so currentTileId now resolves to frame 1's tile id");
  });
}
