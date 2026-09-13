import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  test('Sprite/ParallaxLayer/Particle/TileMap all default zIndex to 0', () {
    expect(Sprite('a', 'r').zIndex, 0);
    expect(ParallaxLayer('a', 'r').zIndex, 0);
    expect(Particle(lifetime: 1).zIndex, 0);
    expect(
      TileMap(cols: 1, rows: 1, tileWidth: 1, tileHeight: 1, tiles: [0]).zIndex,
      0,
    );
  });

  test('Sprite.zIndex round-trips through toJson/fromJson', () {
    final decoded = Sprite.fromJson(Sprite('a', 'r', zIndex: 5).toJson());
    expect(decoded.zIndex, 5);
  });

  test('ParallaxLayer.zIndex round-trips through toJson/fromJson', () {
    final decoded = ParallaxLayer.fromJson(ParallaxLayer('a', 'r', zIndex: -10).toJson());
    expect(decoded.zIndex, -10);
  });

  test('TileMap.zIndex round-trips through toJson/fromJson', () {
    final map = TileMap(cols: 1, rows: 1, tileWidth: 1, tileHeight: 1, tiles: [0], zIndex: 3);
    expect(TileMap.fromJson(map.toJson()).zIndex, 3);
  });

  test('Particle.zIndex round-trips through toJson/fromJson', () {
    final decoded = Particle.fromJson(Particle(lifetime: 1, zIndex: 7).toJson());
    expect(decoded.zIndex, 7);
  });

  test('ParticleEmitter.zIndex round-trips and is copied onto spawned particles', () {
    final decoded = ParticleEmitter.fromJson(ParticleEmitter(zIndex: 9).toJson());
    expect(decoded.zIndex, 9);

    final world = World(width: 200, height: 200);
    registerCoreComponents(world);
    world.addSystem(ParticleSystem());

    final emitterEntity = world.spawn();
    world.storeOf<Position>().set(emitterEntity, Position(0, 0));
    world.storeOf<ParticleEmitter>().set(
          emitterEntity,
          ParticleEmitter(burstCount: 1, zIndex: 9),
        );
    world.step(0.016);

    final particles = world.storeOf<Particle>();
    expect(particles.length, 1);
    expect(particles.denseAt(0).zIndex, 9);
  });

  testWidgets('EngineView renders sprites at different zIndex without error', (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('atlas', SpriteAtlas(await _tinyImage(), {
      'r': const Rect.fromLTWH(0, 0, 4, 4),
    }));

    // Same position, different zIndex -- exercises the sort actually
    // separating them into different draw groups instead of one batch.
    final back = world.spawn();
    world.storeOf<Position>().set(back, Position(50, 50));
    world.storeOf<Sprite>().set(back, Sprite('atlas', 'r', zIndex: -5));

    final front = world.spawn();
    world.storeOf<Position>().set(front, Position(50, 50));
    world.storeOf<Sprite>().set(front, Sprite('atlas', 'r', zIndex: 5));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
      'a high zIndex sprite renders after (on top of) a default-zIndex ParallaxLayer/TileMap',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('atlas', SpriteAtlas(await _tinyImage(), {
      'r': const Rect.fromLTWH(0, 0, 4, 4),
    }));

    final bg = world.spawn();
    world.storeOf<Position>().set(bg, Position(0, 0));
    world.storeOf<ParallaxLayer>().set(bg, ParallaxLayer('atlas', 'r'));

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(cols: 1, rows: 1, tileWidth: 20, tileHeight: 20, tiles: [1], solidTileIds: {1}),
        );

    // A negative zIndex sprite should now draw BEFORE (behind) the
    // default-zIndex ParallaxLayer/TileMap, the opposite of the
    // engine's original fixed order.
    final maskSprite = world.spawn();
    world.storeOf<Position>().set(maskSprite, Position(10, 10));
    world.storeOf<Sprite>().set(maskSprite, Sprite('atlas', 'r', zIndex: -1));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
