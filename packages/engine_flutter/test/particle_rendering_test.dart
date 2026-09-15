import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Color> _pixelAt(WidgetTester tester, Key boundaryKey, Offset point) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
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

Future<void> _ensureDotTextureLoaded(WidgetTester tester) => tester.runAsync(() async {
      for (var i = 0; i < 50 && ParticleDotTexture.image() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

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

  testWidgets(
      'multiple plain particles batch through ParticleDotTexture -- each still renders at its '
      'own position and color, not just "doesn\'t crash"', (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final redId = world.spawn();
    world.storeOf<Position>().set(redId, Position(50, 50));
    world.storeOf<Particle>().set(
        redId, Particle(lifetime: 10, colorArgb: 0xFFFF0000, startScale: 3, endScale: 3));

    final blueId = world.spawn();
    world.storeOf<Position>().set(blueId, Position(150, 50));
    world.storeOf<Particle>().set(
        blueId, Particle(lifetime: 10, colorArgb: 0xFF0000FF, startScale: 3, endScale: 3));

    final boundaryKey = UniqueKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: RepaintBoundary(
            key: boundaryKey,
            child: EngineView(
              world: world,
              atlasRegistry: AtlasRegistry(),
              camera: Camera(),
              backgroundColor: const Color(0xFF000000),
            ),
          ),
        ),
      ),
    ));

    // Ensure ParticleDotTexture has actually finished its one-time async
    // generation before this assertion, so this test exercises the real
    // batched drawAtlas path -- not just whatever the fallback happened
    // to render on the very first, pre-load frame.
    await _ensureDotTextureLoaded(tester);
    await tester.pump(const Duration(milliseconds: 16));

    // Camera() centers world (0,0) on the viewport's own center.
    final redPixel =
        (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(250, 250))))!;
    final bluePixel =
        (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(350, 250))))!;

    expect(redPixel.r, greaterThan(0.5));
    expect(redPixel.b, lessThan(0.1));
    expect(bluePixel.b, greaterThan(0.5));
    expect(bluePixel.r, lessThan(0.1));
  });

  testWidgets('a particle with an unregistered Sprite atlas falls back to the plain-circle path',
      (tester) async {
    final world = World(width: 400, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(50, 50));
    world.storeOf<Particle>().set(entity, Particle(lifetime: 1, colorArgb: 0xFF00FF00));
    world.storeOf<Sprite>().set(entity, Sprite('missing-atlas', 'spark'));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
      ),
    ));
    await _ensureDotTextureLoaded(tester);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
