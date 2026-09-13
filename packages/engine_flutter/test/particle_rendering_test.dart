import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EngineView renders a plain (spriteless) Particle without error',
      (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(50, 50));
    world.storeOf<Particle>().set(entity, Particle(lifetime: 1, colorArgb: 0xFFFF8800));

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

  testWidgets('EngineView renders a sprite-backed Particle without error', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFFFFFFFF));
    final image = await recorder.endRecording().toImage(4, 4);
    registry.register('fx', SpriteAtlas(image, {'spark': const Rect.fromLTWH(0, 0, 4, 4)}));

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(50, 50));
    world.storeOf<Particle>().set(entity, Particle(lifetime: 1));
    world.storeOf<Sprite>().set(entity, Sprite('fx', 'spark'));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: registry,
        camera: Camera(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('a fully expired particle (alpha 0) is skipped without error', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(0, 0));
    final particle = Particle(lifetime: 1, startAlpha: 1, endAlpha: 0);
    particle.age = 1; // fully aged out -> alpha 0
    world.storeOf<Particle>().set(entity, particle);

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
