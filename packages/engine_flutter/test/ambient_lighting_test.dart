import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  return recorder.endRecording().toImage(4, 4);
}

Future<Color> _pixelAt(WidgetTester tester, Key boundaryKey, Offset point) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  final offset = (y * image.width + x) * 4;
  final data = bytes!;
  return Color.fromARGB(data.getUint8(offset + 3), data.getUint8(offset), data.getUint8(offset + 1), data.getUint8(offset + 2));
}

void main() {
  group('EngineView singlePassLighting', () {
    testWidgets('singlePassLighting=true: multiple overlapping lights reveal additively', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<Sprite>().set(entity, Sprite('atlas', 'white', zIndex: 0, scaleX: 100, scaleY: 100));

      // Two overlapping lights at the same position
      final light1 = world.spawn();
      world.storeOf<Position>().set(light1, Position(0, 0));
      world.storeOf<Light2D>().set(light1, Light2D(radius: 100, intensity: 1));

      final light2 = world.spawn();
      world.storeOf<Position>().set(light2, Position(0, 0));
      world.storeOf<Light2D>().set(light2, Light2D(radius: 100, intensity: 1));

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
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0,
                singlePassLighting: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final pixel = (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      // With singlePassLighting, both lights contribute to maxReveal
      // Since they overlap perfectly, maxReveal = max(1, 1) = 1
      // So the area should be fully revealed (white)
      expect(pixel.r, greaterThan(0.9), reason: 'overlapping lights should fully reveal the area');
    });

    testWidgets('singlePassLighting=true: light with color tint applies additively', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<Sprite>().set(entity, Sprite('atlas', 'white', zIndex: 0, scaleX: 100, scaleY: 100));

      // Light with orange tint
      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(0, 0));
      world.storeOf<Light2D>().set(light, Light2D(radius: 100, intensity: 1, colorArgb: 0xFFFF6600));

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
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0.2,
                singlePassLighting: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final pixel = (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      // Should have orange tint
      expect(pixel.r, greaterThan(pixel.g), reason: 'orange tint should have more red than green');
    });

    testWidgets('singlePassLighting=true: falls back to legacy when castsShadows light present', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<Sprite>().set(entity, Sprite('atlas', 'white', zIndex: 0, scaleX: 100, scaleY: 100));

      // Light WITH castsShadows - should trigger legacy path
      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(0, 0));
      world.storeOf<Light2D>().set(light, Light2D(radius: 100, intensity: 1, castsShadows: true));

      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: UniqueKey(),
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0.2,
                singlePassLighting: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget, reason: 'should render without crashing in legacy fallback');
    });

    testWidgets('singlePassLighting=true: falls back to legacy when coneAngle light present', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<Sprite>().set(entity, Sprite('atlas', 'white', zIndex: 0, scaleX: 100, scaleY: 100));

      // Light WITH coneAngle - should trigger legacy path
      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(0, 0));
      world.storeOf<Light2D>().set(light, Light2D(radius: 100, intensity: 1, coneAngle: 1.0, coneDirection: 0.5));

      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: UniqueKey(),
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0.2,
                singlePassLighting: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('singlePassLighting=false (default): legacy path still works', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<Sprite>().set(entity, Sprite('atlas', 'white', zIndex: 0, scaleX: 100, scaleY: 100));

      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(0, 0));
      world.storeOf<Light2D>().set(light, Light2D(radius: 100, intensity: 1));

      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: UniqueKey(),
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0,
                singlePassLighting: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('singlePassLighting: z-banded lights work correctly', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {'white': const Rect.fromLTWH(0, 0, 4, 4)}));

      // Two sprites at different zIndex
      final litEntity = world.spawn();
      world.storeOf<Position>().set(litEntity, Position(0, 0));
      world.storeOf<Sprite>().set(litEntity, Sprite('atlas', 'white', zIndex: 0, scaleX: 50, scaleY: 50));

      final unlitEntity = world.spawn();
      world.storeOf<Position>().set(unlitEntity, Position(100, 0));
      world.storeOf<Sprite>().set(unlitEntity, Sprite('atlas', 'white', zIndex: 1, scaleX: 50, scaleY: 50));

      // Light scoped to zIndex 0 only
      final light = world.spawn();
      world.storeOf<Position>().set(light, Position(0, 0));
      world.storeOf<Light2D>().set(light, Light2D(radius: 80, intensity: 1, minZIndex: 0, maxZIndex: 0));

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
                atlasRegistry: registry,
                camera: Camera(),
                ambientBrightness: 0,
                singlePassLighting: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // World (0,0) -> screen (200,150); world (100,0) -> screen (300,150)
      final litPixel = (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      final unlitPixel = (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(300, 150))))!;

      expect(litPixel.r, greaterThan(0.9), reason: 'zIndex-0 sprite inside light z-range should be revealed');
      expect(unlitPixel.r, lessThan(0.1), reason: 'zIndex-1 sprite outside light z-range should stay dark');
    });
  });

  group('GameConfig singlePassLighting', () {
    test('serializes and deserializes singlePassLighting correctly', () {
      const config = GameConfig(
        worldWidth: 800,
        worldHeight: 600,
        singlePassLighting: true,
      );

      final json = config.toJson();
      final restored = GameConfig.fromJson(json);

      expect(restored.singlePassLighting, isTrue);
      expect(json['singlePassLighting'], isTrue);
    });

    test('defaults singlePassLighting to false', () {
      const config = GameConfig(worldWidth: 800, worldHeight: 600);
      expect(config.singlePassLighting, isFalse);
    });

    test('fromJson handles missing singlePassLighting gracefully', () {
      final json = <String, dynamic>{
        'worldWidth': 800,
        'worldHeight': 600,
      };
      final config = GameConfig.fromJson(json);
      expect(config.singlePassLighting, isFalse);
    });
  });
}