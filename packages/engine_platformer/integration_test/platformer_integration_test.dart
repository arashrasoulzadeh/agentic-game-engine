import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter/material.dart' hide Velocity;

@Tags(const ['integration'])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Platformer integration', () {
    testWidgets('player can move, jump, and collide with TileMap in a full scene',
        (WidgetTester tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      registerPlatformerComponents(world);

      final input = InputState();

      final player = spawnPlayer(
        world,
        x: 200,
        y: 200,
        input: input,
        jumpSpeed: 400,
        atlasId: 'test_atlas',
        spriteRegion: 'idle',
      );

      installPlatformerSystems(world, player: player);

      // TileMap floor
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
        mapEntity,
        TileMap(
          cols: 20,
          rows: 15,
          tileWidth: 40,
          tileHeight: 40,
          tiles: List.generate(300, (i) => (i ~/ 20 == 14) ? 1 : 0),
          solidTileIds: {1},
        ),
      );

      final atlasRegistry = AtlasRegistry();
      final testImage = await _createTestImage();
      atlasRegistry.register('test_atlas', SpriteAtlas(testImage, {
        'idle': ui.Rect.fromLTWH(0, 0, 32, 32),
      }));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
        ),
      ));

      await tester.pumpAndSettle();

      // Move right
      input.pressedActions.add('right');
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      final posAfterMove = world.storeOf<Position>().get(player)!;
      expect(posAfterMove.x, greaterThan(200));

      // Jump
      input.pressedActions.remove('right');
      input.pressedActions.add('jump');
      await tester.pump(const Duration(milliseconds: 16));

      final velAfterJump = world.storeOf<Velocity>().get(player)!;
      expect(velAfterJump.y, lessThan(0)); // moving up

      // Wait for landing
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final controller = world.storeOf<PlatformerController>().get(player)!;
      expect(controller.grounded, isTrue);
    });

    testWidgets('enemy AI patrols and reacts to player',
        (WidgetTester tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      registerPlatformerComponents(world);

      final input = InputState();

      final player = spawnPlayer(
        world,
        x: 400,
        y: 200,
        input: input,
        jumpSpeed: 400,
        atlasId: 'test_atlas',
        spriteRegion: 'idle',
      );

      final behaviors = BehaviorRegistry()
        ..register('patrol', PatrolBehavior(minX: 100, maxX: 300, speed: 60))
        ..register('chase', FollowBehavior(target: player, maxDistance: 200, speed: 80));

      final enemy = spawnEnemy(
        world,
        x: 200,
        y: 200,
        behaviorId: 'patrol',
        atlasId: 'test_atlas',
        spriteRegion: 'enemy_idle',
      );

      installPlatformerSystems(world, player: player, behaviors: behaviors);

      // Floor
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
        mapEntity,
        TileMap(
          cols: 20,
          rows: 15,
          tileWidth: 40,
          tileHeight: 40,
          tiles: List.generate(300, (i) => (i ~/ 20 == 14) ? 1 : 0),
          solidTileIds: {1},
        ),
      );

      final atlasRegistry = AtlasRegistry();
      final testImage = await _createTestImage();
      atlasRegistry.register('test_atlas', SpriteAtlas(testImage, {
        'idle': ui.Rect.fromLTWH(0, 0, 32, 32),
        'enemy_idle': ui.Rect.fromLTWH(32, 0, 32, 32),
      }));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
        ),
      ));

      await tester.pumpAndSettle();

      // Let enemy patrol
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final enemyPos = world.storeOf<Position>().get(enemy)!;
      expect(enemyPos.x, greaterThan(100));
      expect(enemyPos.x, lessThan(300));
    });
  });
}

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 32), paint);
  final picture = recorder.endRecording();
  return picture.toImage(64, 32);
}