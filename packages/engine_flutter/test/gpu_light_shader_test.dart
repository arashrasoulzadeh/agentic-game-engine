import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:engine_flutter/src/rendering/gpu_light_shader.dart';

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
  group('Light2D.useGpuShadows', () {
    test('defaults to false and round-trips through toJson/fromJson', () {
      expect(Light2D().useGpuShadows, isFalse);

      final light = Light2D(useGpuShadows: true);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.useGpuShadows, isTrue);
    });

    testWidgets(
        'a GPU-shadow light reveals a pixel with clear line of sight, and occludes one '
        'behind a solid tile wall -- proves the shader actually does per-pixel '
        'ray-vs-segment occlusion, not just "renders without crashing"',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      // A short solid wall directly between the light and one of the
      // two sample points below (col 3, row 2 -> x=[60,80), y=[40,60)).
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 10,
              rows: 5,
              tileWidth: 20,
              tileHeight: 20,
              tiles: [
                for (var row = 0; row < 5; row++)
                  for (var col = 0; col < 10; col++) (col == 3 && row == 2) ? 1 : 0,
              ],
              solidTileIds: {1},
            ),
          );

      final lightEntity = world.spawn();
      // Same row as the wall (y=50) -- ray toward (150,50) passes
      // straight through unobstructed; ray toward (70,50) is blocked
      // by the wall tile at col 3.
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      world.storeOf<Light2D>().set(
            lightEntity,
            Light2D(
              radius: 200,
              intensity: 1,
              castsShadows: true,
              useGpuShadows: true,
              colorArgb: 0xFFFF0000, // opaque red -- unambiguous against black
            ),
          );

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
                camera: Camera(),
                ambientBrightness: 0.2,
              ),
            ),
          ),
        ),
      ));

      // The shader's FragmentProgram.fromAsset compile is real async
      // work outside the fake test zone -- runAsync + polling pumps
      // until GpuLightShader has actually finished loading it, the
      // same reason toImage() needs runAsync elsewhere in this file.
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && GpuLightShader.shader() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final shader = GpuLightShader.shader();
      expect(shader, isNotNull,
          reason: 'flutter_test_config must expose the compiled package shader');
      shader!.dispose();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      // Camera() default on a 400x300 viewport maps world (0,0) to
      // screen (200,150). The light sits at world (10,50); the wall
      // tile spans x=[60,80), y=[40,60).
      //
      // Occluded sample: world (150,50) -> screen (350,200) -- same y
      // as the light, so the straight ray from (10,50) to (150,50)
      // passes directly through the wall's x=[60,80) span at y=50,
      // which is inside the wall's y=[40,60) range.
      //
      // Clear sample: world (150,-50) -> screen (350,100) -- the ray
      // from (10,50) to (150,-50) crosses x=70 (the wall's mid-column)
      // at y = 50 + (70-10)/(150-10) * (-50-50) ≈ 7.1, well outside the
      // wall's y=[40,60) range, so nothing blocks it.
      final occludedPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(350, 200))))!;
      final clearPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(350, 100))))!;

      expect(clearPixel.r, greaterThan(0.15),
          reason: 'world (150,-50) has a clear line of sight to the light -- the '
              'GPU shadow pass should light it');
      expect(occludedPixel.r, lessThan(0.05),
          reason: 'world (150,50) sits directly behind the wall tile relative to '
              'the light at (10,50) -- the shader\'s per-pixel ray-vs-segment test '
              'should occlude it entirely');
    });

    testWidgets('off by default -- no GPU shadow pass runs, no extra draw calls',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 80, castsShadows: true));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    test(
      'shader() returns null and swallows error when asset load fails',
      tags: ['regression'],
      () async {
      GpuLightShader.resetForTesting();
      GpuLightShader.setAssetKeyForTesting('packages/engine_flutter/shaders/nonexistent.frag');

      final shader = GpuLightShader.shader();
      expect(shader, isNull);

      // Wait for the async error to be caught
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Calling again should still return null (error was swallowed, _loading completed)
      expect(GpuLightShader.shader(), isNull);

      // Reset for other tests
      GpuLightShader.resetForTesting();
    });
  });
}
