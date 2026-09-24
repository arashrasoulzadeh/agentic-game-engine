import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EngineView integration', () {
    testWidgets('renders a full scene with TileMap, Sprite, Light2D, and Particles',
        (WidgetTester tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      // TileMap
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
        mapEntity,
        TileMap(
          cols: 20,
          rows: 15,
          tileWidth: 40,
          tileHeight: 40,
          tiles: List.generate(300, (i) => (i % 20 < 5 && i ~/ 20 < 5) ? 1 : 0),
          solidTileIds: {1},
        ),
      );

      // Player sprite
      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(400, 300));
      world.storeOf<Sprite>().set(
        player,
        Sprite('test_atlas', 'player_idle', zIndex: 10),
      );

      // Light
      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(400, 300));
      world.storeOf<Light2D>().set(
        light,
        Light2D(
          radius: 200,
          intensity: 0.8,
          colorArgb: 0x88FFFF00,
          castsShadows: true,
        ),
      );

      // Particle emitter
      final emitter = world.spawn();
      world.storeOf<Position>().set(emitter, Position(400, 300));
      world.storeOf<ParticleEmitter>().set(
        emitter,
        ParticleEmitter(
          rate: 10,
          speedMin: 50,
          speedMax: 150,
          lifetimeMin: 0.5,
          lifetimeMax: 1.0,
          colorArgb: 0xFFFF6600,
        ),
      );

      world.addSystem(MovementSystem());
      world.addSystem(ParticleSystem());

      final atlasRegistry = AtlasRegistry();
      final testImage = await _createTestImage();
      atlasRegistry.register('test_atlas', SpriteAtlas(testImage, {'player_idle': ui.Rect.fromLTWH(0, 0, 32, 32)}));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: atlasRegistry,
          camera: Camera(),
          ambientBrightness: 0.3,
        ),
      ));

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('scene switch creates new World but preserves GameState',
        (WidgetTester tester) async {
      final gameState = GameState({'score': 100, 'level': 1});

      final scenes = SceneController();

      final sceneA = _TestSceneA();
      final sceneB = _TestSceneB();

      await tester.pumpWidget(MaterialApp(home: _TestGame(
        config: const GameConfig(worldWidth: 400, worldHeight: 300),
        initialScene: sceneA,
        initialState: gameState,
        scenes: scenes,
      )));
      await tester.pumpAndSettle();

      scenes.loadScene(sceneB);
      await tester.pumpAndSettle();
    });
  });
}

class _TestSceneA extends Scene {
  @override
  Future<void> populate(World world, SceneController sc, GameState state) async {
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final e = world.spawn();
    world.storeOf<Position>().set(e, Position(100, 100));
  }
}

class _TestSceneB extends Scene {
  @override
  Future<void> populate(World world, SceneController sc, GameState state) async {
    registerCoreComponents(world);
    registerFlutterComponents(world);
    expect(state.data['score'], 100);
    expect(state.data['level'], 1);
    final e = world.spawn();
    world.storeOf<Position>().set(e, Position(200, 200));
  }
}

class _TestGame extends Game {
  _TestGame({
    required this.config,
    required this.initialScene,
    required this.initialState,
    required this.scenes,
  });

  @override
  final GameConfig config;

  @override
  final Scene initialScene;

  @override
  final GameState initialState;

  @override
  final SceneController scenes;

  @override
  SceneController createSceneController() => scenes;
}

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 32), paint);
  final picture = recorder.endRecording();
  return picture.toImage(32, 32);
}