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
  test('ParallaxLayer round-trips through toJson/fromJson with defaults', () {
    final layer = ParallaxLayer('bg', 'sky');
    final decoded = ParallaxLayer.fromJson(layer.toJson());

    expect(decoded.atlasId, 'bg');
    expect(decoded.region, 'sky');
    expect(decoded.scrollFactorX, 0.5);
    expect(decoded.scrollFactorY, 0);
    expect(decoded.tileX, isTrue);
    expect(decoded.tileY, isFalse);
  });

  test('ParallaxLayer.fromJson honors explicit non-default values', () {
    final layer = ParallaxLayer(
      'bg',
      'mountains',
      scrollFactorX: 0.2,
      scrollFactorY: 0.1,
      tileX: false,
      tileY: true,
    );
    final decoded = ParallaxLayer.fromJson(layer.toJson());

    expect(decoded.scrollFactorX, 0.2);
    expect(decoded.scrollFactorY, 0.1);
    expect(decoded.tileX, isFalse);
    expect(decoded.tileY, isTrue);
  });

  testWidgets('EngineView renders a tiled parallax layer without error', (tester) async {
    final world = World(width: 2000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('bg', SpriteAtlas(await _tinyImage(), {
      'sky': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(0, 0));
    world.storeOf<ParallaxLayer>().set(entity, ParallaxLayer('bg', 'sky'));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: registry,
        camera: Camera(x: 500, y: 0),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('a parallax layer referencing an unregistered atlas is skipped, not a crash',
      (tester) async {
    final world = World(width: 2000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(0, 0));
    world.storeOf<ParallaxLayer>().set(entity, ParallaxLayer('missing', 'sky'));

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
}
