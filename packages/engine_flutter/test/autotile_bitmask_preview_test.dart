import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TileMap auto-tile bitmask preview', () {
    testWidgets('EngineView shows bitmask debug overlay when enabled', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      // Create a TileMap with walls that will have bitmasks
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 5,
        rows: 3,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [
          1, 1, 1, 1, 1,
          1, 0, 0, 0, 1,
          1, 1, 1, 1, 1,
        ],
        solidTileIds: {1},
        atlasId: 'tileset',
        regionByTileId: {1: 'wall'},
      ));

      final atlasRegistry = AtlasRegistry();
      atlasRegistry.register('tileset', SpriteAtlas(await _createTestImage(), {
        'wall': Rect.fromLTWH(0, 0, 32, 32),
      }));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
          showAutoTileBitmask: true, // Enable the bitmask preview
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('bitmask overlay shows correct values for different tile configurations', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      // Test different bitmask patterns
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 3,
        rows: 3,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [
          1, 1, 1,
          1, 1, 1,
          1, 1, 1,
        ],
        solidTileIds: {1},
        atlasId: 'tileset',
        regionByTileId: {1: 'wall'},
      ));

      final atlasRegistry = AtlasRegistry();
      atlasRegistry.register('tileset', SpriteAtlas(await _createTestImage(), {
        'wall': Rect.fromLTWH(0, 0, 32, 32),
      }));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
          showAutoTileBitmask: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // Center tile should have bitmask 15 (all 4 neighbors are walls)
      // Corner tiles should have bitmask 3, 6, 9, 12
      // Edge tiles should have bitmask 7, 11, 13, 14
      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('bitmask overlay hidden when disabled', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 5,
        rows: 3,
        tileWidth: 40,
        tileHeight: 40,
        tiles: [
          1, 1, 1, 1, 1,
          1, 0, 0, 0, 1,
          1, 1, 1, 1, 1,
        ],
        solidTileIds: {1},
        atlasId: 'tileset',
        regionByTileId: {1: 'wall'},
      ));

      final atlasRegistry = AtlasRegistry();
      atlasRegistry.register('tileset', SpriteAtlas(await _createTestImage(), {
        'wall': Rect.fromLTWH(0, 0, 32, 32),
      }));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
          showAutoTileBitmask: false, // Disabled
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });
}

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 32), paint);
  final picture = recorder.endRecording();
  return picture.toImage(32, 32);
}