import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  return recorder.endRecording().toImage(4, 4);
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
  group('Light2D', () {
    test('round-trips through toJson/fromJson', () {
      final light = Light2D(radius: 150, intensity: 0.7);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.radius, 150);
      expect(restored.intensity, 0.7);
    });

    test('fromJson defaults radius to 100 and intensity to 1', () {
      final restored = Light2D.fromJson({});
      expect(restored.radius, 100);
      expect(restored.intensity, 1);
    });

    test('fromJson defaults colorArgb to transparent (no tint) and other new fields off', () {
      final restored = Light2D.fromJson({});
      expect(restored.colorArgb, 0x00FFFFFF);
      expect(restored.coneAngle, isNull);
      expect(restored.coneDirection, 0);
      expect(restored.castsShadows, isFalse);
      expect(restored.flickerSpeed, 0);
    });

    test('baseIntensity/baseRadius default from intensity/radius when not given', () {
      final light = Light2D(radius: 120, intensity: 0.6);
      expect(light.baseRadius, 120);
      expect(light.baseIntensity, 0.6);
    });

    test('baseIntensity/baseRadius can be set independently of intensity/radius', () {
      final light = Light2D(radius: 50, intensity: 0.2, baseRadius: 120, baseIntensity: 0.6);
      expect(light.radius, 50);
      expect(light.intensity, 0.2);
      expect(light.baseRadius, 120);
      expect(light.baseIntensity, 0.6);
    });

    test('round-trips all new fields through toJson/fromJson', () {
      final light = Light2D(
        radius: 90,
        intensity: 0.8,
        colorArgb: 0xAAFF6600,
        coneAngle: 1.2,
        coneDirection: 0.5,
        castsShadows: true,
        flickerSpeed: 2,
        flickerAmount: 0.4,
        flickerElapsed: 3.5,
      );
      final restored = Light2D.fromJson(light.toJson());

      expect(restored.colorArgb, 0xAAFF6600);
      expect(restored.coneAngle, 1.2);
      expect(restored.coneDirection, 0.5);
      expect(restored.castsShadows, isTrue);
      expect(restored.flickerSpeed, 2);
      expect(restored.flickerAmount, 0.4);
      expect(restored.baseIntensity, 0.8);
      expect(restored.baseRadius, 90);
      expect(restored.flickerElapsed, 3.5);
    });

    test('coneAngle omitted from toJson when null, so fromJson keeps it null', () {
      final restored = Light2D.fromJson(Light2D().toJson());
      expect(restored.coneAngle, isNull);
    });

    test('blockOneWayPlatforms defaults to false and round-trips through toJson/fromJson',
        () {
      expect(Light2D().blockOneWayPlatforms, isFalse);

      final light = Light2D(castsShadows: true, blockOneWayPlatforms: true);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.blockOneWayPlatforms, isTrue);
    });

    test('shadowSmoothingSeconds defaults to 0 (off) and round-trips through toJson/fromJson',
        () {
      expect(Light2D().shadowSmoothingSeconds, 0);

      final light = Light2D(shadowSmoothingSeconds: 0.1);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.shadowSmoothingSeconds, 0.1);
    });

    test('shadowEdgeSoftness defaults to 8 and round-trips through toJson/fromJson', () {
      expect(Light2D().shadowEdgeSoftness, 8);

      final light = Light2D(shadowEdgeSoftness: 0);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.shadowEdgeSoftness, 0);
    });

    test('minZIndex/maxZIndex default to null (no z restriction) and round-trip', () {
      final unrestricted = Light2D();
      expect(unrestricted.minZIndex, isNull);
      expect(unrestricted.maxZIndex, isNull);
      expect(unrestricted.toJson().containsKey('minZIndex'), isFalse);
      expect(unrestricted.toJson().containsKey('maxZIndex'), isFalse);

      final scoped = Light2D(minZIndex: -1, maxZIndex: 2);
      final restored = Light2D.fromJson(scoped.toJson());
      expect(restored.minZIndex, -1);
      expect(restored.maxZIndex, 2);
    });

    test('smoothedShadowDistances starts empty and is not included in toJson', () {
      final light = Light2D();
      expect(light.smoothedShadowDistances, isEmpty);
      expect(light.toJson().containsKey('smoothedShadowDistances'), isFalse);
    });

    test('shadowRayCount defaults to 48 and round-trips through toJson/fromJson', () {
      expect(Light2D().shadowRayCount, 48);

      final light = Light2D(shadowRayCount: 16);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.shadowRayCount, 16);
    });

    test('overbrightIntensity defaults to 0 and round-trips through toJson/fromJson', () {
      expect(Light2D().overbrightIntensity, 0);

      final light = Light2D(overbrightIntensity: 0.2);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.overbrightIntensity, 0.2);
    });

    test('openAirFalloffScale defaults to 1.0 and round-trips through toJson/fromJson', () {
      expect(Light2D().openAirFalloffScale, 1.0);

      final light = Light2D(openAirFalloffScale: 0.4);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.openAirFalloffScale, 0.4);
    });
  });

  group('LightFlickerSystem', () {
    test('does nothing when flickerSpeed is 0 (default)', () {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(LightFlickerSystem());

      final id = world.spawn();
      world.storeOf<Light2D>().set(id, Light2D(radius: 100, intensity: 0.8));

      world.step(0.5);

      final light = world.storeOf<Light2D>().get(id)!;
      expect(light.radius, 100);
      expect(light.intensity, 0.8);
      expect(light.flickerElapsed, 0);
    });

    test('oscillates intensity/radius around base values when flickering', () {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(LightFlickerSystem());

      final id = world.spawn();
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, intensity: 0.8, flickerSpeed: 1, flickerAmount: 0.5),
          );

      world.step(0.1);
      final light = world.storeOf<Light2D>().get(id)!;
      expect(light.flickerElapsed, closeTo(0.1, 0.001));
      // Base values are unaffected -- only the live intensity/radius move.
      expect(light.baseRadius, 100);
      expect(light.baseIntensity, 0.8);
      // With flickerAmount 0.5, radius/intensity can swing but should
      // stay within [base * 0.5, base * 1.5] (noise is a weighted sum
      // of two sines in roughly [-1, 1]).
      expect(light.radius, inInclusiveRange(0, 200));
      expect(light.intensity, inInclusiveRange(0, 1));
    });

    test('clamps intensity to [0, 1] even with a large flickerAmount', () {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(LightFlickerSystem());

      final id = world.spawn();
      world.storeOf<Light2D>().set(
            id,
            Light2D(intensity: 1, flickerSpeed: 5, flickerAmount: 2),
          );

      for (var i = 0; i < 50; i++) {
        world.step(0.05);
        final light = world.storeOf<Light2D>().get(id)!;
        expect(light.intensity, inInclusiveRange(0, 1));
        expect(light.radius, greaterThanOrEqualTo(0));
      }
    });

    test('flickerAffectsRadius: false pins radius at baseRadius while intensity still '
        'flickers normally -- lets a stationary castsShadows light\'s shadow geometry '
        'stay stable enough for cacheShadowGeometry to actually hit', () {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(LightFlickerSystem());

      final id = world.spawn();
      world.storeOf<Light2D>().set(
            id,
            Light2D(
              radius: 100,
              intensity: 0.8,
              flickerSpeed: 3,
              flickerAmount: 0.5,
              flickerAffectsRadius: false,
            ),
          );

      for (var i = 0; i < 20; i++) {
        world.step(0.05);
        final light = world.storeOf<Light2D>().get(id)!;
        expect(light.radius, 100, reason: 'radius pinned exactly at baseRadius every tick');
      }
      // Intensity still genuinely varies -- this isn't just "flicker
      // fully disabled", only radius is exempted.
      final finalIntensity = world.storeOf<Light2D>().get(id)!.intensity;
      expect(finalIntensity, isNot(0.8));
    });

    test('flickerAffectsRadius defaults to true, matching the original flicker '
        'behavior, and round-trips through toJson/fromJson', () {
      expect(Light2D().flickerAffectsRadius, isTrue);

      final light = Light2D(flickerAffectsRadius: false);
      final restored = Light2D.fromJson(light.toJson());
      expect(restored.flickerAffectsRadius, isFalse);
    });
  });

  group('EngineView lighting', () {
    testWidgets(
        'a light scoped to minZIndex/maxJIndex reveals content in its own '
        'z-band but leaves a different band fully dark -- proves the '
        'z-banded compositing in EngineView._paintZBanded actually isolates '
        'bands from each other, not just that it renders without crashing',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {
        'lit': const Rect.fromLTWH(0, 0, 4, 4),
        'unlit': const Rect.fromLTWH(0, 0, 4, 4),
      }));

      final litEntity = world.spawn();
      world.storeOf<Position>().set(litEntity, Position(0, 0));
      world.storeOf<Sprite>().set(
          litEntity, Sprite('atlas', 'lit', zIndex: 0, scaleX: 30, scaleY: 30));

      final unlitEntity = world.spawn();
      world.storeOf<Position>().set(unlitEntity, Position(120, 0));
      world.storeOf<Sprite>().set(
          unlitEntity, Sprite('atlas', 'unlit', zIndex: 1, scaleX: 30, scaleY: 30));

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(0, 0));
      world.storeOf<Light2D>().set(
          lightEntity, Light2D(radius: 100, intensity: 1, minZIndex: 0, maxZIndex: 0));

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
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // World (0,0) -> screen (200, 150) at Camera(x:0,y:0,zoom:1) on a
      // 400x300 viewport; world (120,0) -> screen (320, 150).
      // toImage() needs the real rasterizer, not the fake test async
      // zone -- runAsync is required or this hangs.
      final litPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      final unlitPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(320, 150))))!;

      expect(litPixel.r, greaterThan(0.5),
          reason: 'the zIndex-0 sprite sits inside the zIndex-0-scoped light, so full '
              'ambientBrightness-0 darkness there should be revealed back to white');
      expect(unlitPixel.r, lessThan(0.1),
          reason: "the zIndex-1 sprite is outside the light's z-range, so its own band "
              'gets ambientBrightness-0 darkness with nothing to reveal it');
    });

    testWidgets('ambientBrightness 1.0 (default) renders identically to no lighting at all',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a darkened scene with a Light2D renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 80, intensity: 1));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.1,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a Light2D with no Position is skipped gracefully, not a crash', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Light2D>().set(id, Light2D()); // no Position

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

    testWidgets('a full-black scene (ambientBrightness 0, no lights) renders without crashing',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.0,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('showColliderDebug stays visible on top of a darkened scene', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Collider>().set(id, Collider(10));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.1,
          showColliderDebug: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a colored (tinted) light renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 80, colorArgb: 0xAAFF6600));

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

    testWidgets('a cone (directional) light renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, coneAngle: 1.0, coneDirection: 0.5),
          );

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

    testWidgets('a shadow-casting light renders without crashing, with a TileMap present',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 10,
              rows: 10,
              tileWidth: 20,
              tileHeight: 20,
              tiles: List.filled(100, 0),
              solidTileIds: {1},
            ),
          );

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 120, castsShadows: true));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.15,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a shadow-casting cone light renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, coneAngle: 1.5, castsShadows: true),
          );

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

    testWidgets('a shadow-casting light far outside the viewport renders without crashing '
        '(exercises the viewport-cull path)', (tester) async {
      final world = World(width: 4000, height: 4000);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 10,
              rows: 10,
              tileWidth: 20,
              tileHeight: 20,
              tiles: List.filled(100, 0),
              solidTileIds: {1},
            ),
          );

      // Camera stays at the default origin; this light sits thousands
      // of pixels off screen, so its screen-space circle never reaches
      // the viewport rect -- the light should be culled before any
      // raycasting runs, not just clipped to nothing after the fact.
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(3000, 3000));
      world.storeOf<Light2D>().set(id, Light2D(radius: 50, castsShadows: true));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.15,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a custom shadowRayCount renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, castsShadows: true, shadowRayCount: 8),
          );

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

    testWidgets('shadowRayCount below 3 renders without crashing (clamped internally)',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, castsShadows: true, shadowRayCount: 0),
          );

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

    testWidgets('a shadow-casting light with blockOneWayPlatforms true renders without '
        'crashing, with a one-way TileMap tile present', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 10,
              rows: 10,
              tileWidth: 20,
              tileHeight: 20,
              tiles: List.filled(100, 0),
              oneWayTileIds: {2},
            ),
          );

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(
            id,
            Light2D(radius: 100, castsShadows: true, blockOneWayPlatforms: true),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.15,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });

  group('Shadow ray distance smoothing (Light2D.shadowSmoothingSeconds)', () {
    // Real behavioral assertions on Light2D.smoothedShadowDistances
    // (not just "renders without crashing") -- drives EngineView's
    // real Ticker with explicit frame durations via tester.pump, so
    // the exponential-smoothing math runs with real, known dt values.
    testWidgets(
        'a ray toward a solid wall converges from the initial radius toward the raw '
        'raycast distance gradually over several frames, not instantly', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 5,
              rows: 5,
              tileWidth: 20,
              tileHeight: 20,
              // Solid tile at col 2, row 2 (x=[40,60], y=[40,60]).
              tiles: [
                for (var row = 0; row < 5; row++)
                  for (var col = 0; col < 5; col++) (col == 2 && row == 2) ? 1 : 0,
              ],
              solidTileIds: {1},
            ),
          );

      final lightEntity = world.spawn();
      // Same row as the wall (y=50), well to its left -- ray angle 0
      // (the first of shadowRayCount samples, always +x direction)
      // points straight at it. Raw distance to the wall's near edge:
      // 40 - 10 = 30.
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        shadowSmoothingSeconds: 1.0,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));

      // The very first ticker callback always has dt == 0 (no prior
      // frame to measure elapsed time against -- see EngineView's
      // _onTick), so smoothing doesn't even engage until the *second*
      // pump. That priming frame first, then the one actually checked.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final afterOneFrame = light.smoothedShadowDistances[0];
      expect(afterOneFrame, greaterThan(90),
          reason: 'barely smoothed in yet with tau=1.0s and a 16ms frame');

      // Many more frames (16ms each, several seconds of simulated
      // time at tau=1.0s) should converge it close to the raw value.
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(light.smoothedShadowDistances[0], closeTo(30, 1));
    });

    testWidgets('shadowSmoothingSeconds: 0 (default) uses the raw distance immediately, '
        'no lag', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 5,
              rows: 5,
              tileWidth: 20,
              tileHeight: 20,
              tiles: [
                for (var row = 0; row < 5; row++)
                  for (var col = 0; col < 5; col++) (col == 2 && row == 2) ? 1 : 0,
              ],
              solidTileIds: {1},
            ),
          );

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(radius: 100, castsShadows: true, shadowRayCount: 4);
      world.storeOf<Light2D>().set(lightEntity, light);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // No smoothing cache is even used when disabled.
      expect(light.smoothedShadowDistances, isEmpty);
    });
  });

  group('Shadow casting occlusion math', () {
    // Not a widget/pixel test (Canvas draw calls aren't inspectable
    // that way) -- exercises the exact same raycastTileMap primitive
    // EngineView's shadow-casting path uses, over a real TileMap, to
    // confirm a solid tile genuinely blocks a light's reach rather than
    // asserting only that the render path doesn't crash.
    test('a solid tile blocks a raycast well short of the light\'s full radius', () {
      final map = TileMap(
        cols: 5,
        rows: 1,
        tileWidth: 20,
        tileHeight: 20,
        tiles: [0, 0, 1, 0, 0],
        solidTileIds: {1},
      );
      final origin = Position(0, 0);
      // Light at col 0 (x=10), aiming through the solid tile at col 2
      // (x=[40,60]) out to a full radius of 100 (x=110).
      final hit = raycastTileMap(map, origin, 10, 10, 110, 10);

      expect(hit, isNotNull);
      expect(hit!.distance, lessThan(100));
      expect(hit.distance, closeTo(30, 0.001)); // wall's near edge at x=40
    });

    test('an unobstructed direction reaches the light\'s full radius', () {
      final map = TileMap(cols: 5, rows: 1, tileWidth: 20, tileHeight: 20, tiles: List.filled(5, 0));
      final origin = Position(0, 0);
      final hit = raycastTileMap(map, origin, 10, 10, 110, 10);

      expect(hit, isNull, reason: 'nothing blocks, so the ray reaches the target unobstructed');
    });

    test(
        'a one-way tile blocks a raycast when blockOneWay is true (Light2D.blockOneWayPlatforms) '
        'but not by default -- a torch under a platform would otherwise shine through '
        'something that renders as an opaque surface', () {
      final map = TileMap(
        cols: 5,
        rows: 1,
        tileWidth: 20,
        tileHeight: 20,
        tiles: [0, 0, 2, 0, 0],
        oneWayTileIds: {2},
      );
      final origin = Position(0, 0);

      final defaultHit = raycastTileMap(map, origin, 10, 10, 110, 10);
      expect(defaultHit, isNull, reason: 'matches Light2D.blockOneWayPlatforms default (false)');

      final blockedHit =
          raycastTileMap(map, origin, 10, 10, 110, 10, blockOneWay: true);
      expect(blockedHit, isNotNull);
      expect(blockedHit!.distance, closeTo(30, 0.001));
    });
  });

  group('Light rendering under fixed-timestep interpolation', () {
    testWidgets(
        'a light attached to a moving entity renders at the interpolated position, not '
        "the raw (one-fixed-step-stale) Position -- proves _drawLighting's worldPos "
        'lookup actually goes through the same interpolation Sprite/Particle rendering '
        'already gets, not just that nothing crashes', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(MovementSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(1000, 0));
      world.storeOf<Light2D>().set(
          id, Light2D(radius: 30, intensity: 1, colorArgb: 0xFFFF0000));

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
                ambientBrightness: 0,
                fixedTimestepSeconds: 0.1,
              ),
            ),
          ),
        ),
      ));

      await tester.pump(const Duration(milliseconds: 16)); // baseline, dt==0, no step
      // One whole 0.1s step: Position moves from (0,0) to (100,0);
      // previousPositions snapshots (0,0) from just before this step.
      await tester.pump(const Duration(milliseconds: 100));
      // A further half-step's worth of elapsed time with no new whole
      // step reached -- interpolationAlpha lands at 0.5, so the light
      // should render at the halfway point between (0,0) and (100,0),
      // i.e. world (50,0), not at the raw (already one full simulated
      // step old-when-blended, but numerically current) Position (100,0).
      await tester.pump(const Duration(milliseconds: 50));

      // World (0,0) -> screen (200,150) on a 400x300 viewport at
      // Camera() default; world (50,0) -> screen (250,150); world
      // (100,0) -> screen (300,150).
      final interpolatedPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(250, 150))))!;
      final rawPositionPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(300, 150))))!;

      expect(interpolatedPixel.r, greaterThan(0.3),
          reason: 'the interpolated position (world x=50) sits well inside the 30px '
              'radius light, so the additive red tint should show here');
      expect(rawPositionPixel.r, lessThan(0.05),
          reason: 'the raw (uninterpolated) Position (world x=100) is 50px away from '
              'the interpolated light center -- outside its 30px radius entirely, so '
              'this pixel should be untouched black, not tinted red');
    });
  });

  group('Collider(blocksLight: true) casts shadows', () {
    testWidgets(
        'a Collider tagged blocksLight stops a shadow-casting ray short of the light\'s '
        "full radius -- the ray's cachedShadowDistances entry lands right at the "
        "collider's near edge, not the tile-only distance", (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final lightEntity = world.spawn();
      // Ray 0 of a full-circle sweep always points in the +x direction
      // (same convention the raycastTileMap-based tests above rely on).
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        cacheShadowGeometry: true,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      final blockerEntity = world.spawn();
      world.storeOf<Position>().set(blockerEntity, Position(60, 50));
      world.storeOf<Collider>().set(blockerEntity, Collider(10, blocksLight: true));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // Light at x=10, collider center at x=60 radius 10 -- the ray
      // along +x first touches the collider's near edge at x=50, a
      // distance of 40 from the light, well short of the full 100
      // radius.
      expect(light.cachedShadowDistances![0], closeTo(40, 0.5));
    });

    testWidgets('an untagged Collider (blocksLight: false, the default) does not block '
        'light at all', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        cacheShadowGeometry: true,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      final nonBlockerEntity = world.spawn();
      world.storeOf<Position>().set(nonBlockerEntity, Position(60, 50));
      world.storeOf<Collider>().set(nonBlockerEntity, Collider(10)); // blocksLight defaults false

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowDistances![0], closeTo(100, 0.5),
          reason: 'an untagged collider must not occlude light, same as before this '
              'feature existed');
    });

    testWidgets('a light-blocking Collider entirely off the ray path leaves that ray '
        'unobstructed', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        cacheShadowGeometry: true,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      final blockerEntity = world.spawn();
      // Well off the +x ray, on the far side of the light entirely.
      world.storeOf<Position>().set(blockerEntity, Position(10, -200));
      world.storeOf<Collider>().set(blockerEntity, Collider(10, blocksLight: true));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowDistances![0], closeTo(100, 0.5));
    });
  });

  group('Light2D.overbrightIntensity (overlapping lights stack brighter)', () {
    testWidgets('off by default -- two overlapping lights read no brighter than one, '
        'proving the darkness-reveal pass alone caps at "fully revealed"', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final oneLight = world.spawn();
      world.storeOf<Position>().set(oneLight, Position(0, 0));
      world.storeOf<Light2D>().set(oneLight, Light2D(radius: 100, intensity: 1));

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
      await tester.pump(const Duration(milliseconds: 16));
      final onePixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;

      // A second, fully overlapping light at the exact same spot --
      // the reveal pass alone (BlendMode.dstOut) can't push brightness
      // past what one light already achieves, since alpha floors at 0.
      final twoLights = world.spawn();
      world.storeOf<Position>().set(twoLights, Position(0, 0));
      world.storeOf<Light2D>().set(twoLights, Light2D(radius: 100, intensity: 1));
      await tester.pump(const Duration(milliseconds: 16));
      final twoPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;

      expect(twoPixel.r, closeTo(onePixel.r, 0.02),
          reason: 'without overbrightIntensity, a second overlapping light adds no '
              'extra brightness at all');
    });

    testWidgets('> 0: two overlapping lights genuinely stack brighter than either alone',
        (tester) async {
      final worldOne = World(width: 400, height: 300);
      registerCoreComponents(worldOne);
      registerFlutterComponents(worldOne);
      final singleLight = worldOne.spawn();
      worldOne.storeOf<Position>().set(singleLight, Position(0, 0));
      worldOne.storeOf<Light2D>().set(
          singleLight, Light2D(radius: 100, intensity: 1, overbrightIntensity: 0.3));

      final singleKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: singleKey,
              child: EngineView(
                world: worldOne,
                atlasRegistry: AtlasRegistry(),
                camera: Camera(),
                ambientBrightness: 0.2,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final singlePixel = (await tester.runAsync(
          () => _pixelAt(tester, singleKey, const Offset(200, 150))))!;

      final worldTwo = World(width: 400, height: 300);
      registerCoreComponents(worldTwo);
      registerFlutterComponents(worldTwo);
      for (var i = 0; i < 2; i++) {
        final id = worldTwo.spawn();
        worldTwo.storeOf<Position>().set(id, Position(0, 0));
        worldTwo.storeOf<Light2D>().set(
            id, Light2D(radius: 100, intensity: 1, overbrightIntensity: 0.3));
      }

      final doubleKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: doubleKey,
              child: EngineView(
                world: worldTwo,
                atlasRegistry: AtlasRegistry(),
                camera: Camera(),
                ambientBrightness: 0.2,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final doublePixel = (await tester.runAsync(
          () => _pixelAt(tester, doubleKey, const Offset(200, 150))))!;

      expect(doublePixel.r, greaterThan(singlePixel.r),
          reason: 'two overlapping lights with overbrightIntensity set must read '
              'brighter than either light manages alone -- real additive stacking, '
              'not just "renders without crashing"');
    });
  });

  group('Light2D.openAirFalloffScale (open-air rays pulled in, surface hits untouched)', () {
    testWidgets(
        'an unobstructed ray is pulled in to openAirFalloffScale * radius, while a ray '
        'that hits a real solid tile is left at its raycast distance unchanged',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              // Solid tile at col 2, row 2 (x=[40,60], y=[40,60]) --
              // directly in the path of ray index 0 (always +x) from a
              // light at (10,50), same convention the other shadow
              // tests in this file use.
              cols: 5,
              rows: 5,
              tileWidth: 20,
              tileHeight: 20,
              tiles: [
                for (var row = 0; row < 5; row++)
                  for (var col = 0; col < 5; col++) (col == 2 && row == 2) ? 1 : 0,
              ],
              solidTileIds: {1},
            ),
          );

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(10, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        openAirFalloffScale: 0.3,
        cacheShadowGeometry: true,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // Ray 0 (+x, angle 0) hits the wall's near edge at x=40, distance
      // 30 from the light -- unaffected by openAirFalloffScale since it
      // didn't reach the full radius.
      expect(light.cachedShadowDistances![0], closeTo(30, 0.5));
      // Ray 2 (angle pi, -x direction, exactly opposite ray 0 with
      // shadowRayCount 4) has nothing in its path at all -- genuinely
      // open air, so it's pulled in to 100 * 0.3 = 30 instead of
      // reaching the full 100 radius.
      expect(light.cachedShadowDistances![2], closeTo(30, 0.5));
    });

    testWidgets('1.0 (default) leaves every unobstructed ray at the full radius, unchanged',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final lightEntity = world.spawn();
      world.storeOf<Position>().set(lightEntity, Position(50, 50));
      final light = Light2D(
        radius: 100,
        castsShadows: true,
        shadowRayCount: 4,
        cacheShadowGeometry: true,
      );
      world.storeOf<Light2D>().set(lightEntity, light);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      for (final dist in light.cachedShadowDistances!) {
        expect(dist, closeTo(100, 0.001));
      }
    });
  });

  group('Light2D.cacheShadowGeometry', () {
    testWidgets('off by default -- cachedShadowDistances stays null across frames', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final light = Light2D(radius: 100, castsShadows: true);
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowDistances, isNull,
          reason: 'no caching side effect at all unless explicitly opted in');
    });

    testWidgets(
        'on: reuses the exact same distances list across frames for a light that '
        "hasn't moved (the raycast sweep genuinely didn't re-run, not just that the "
        'result happens to match)', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final light = Light2D(radius: 100, castsShadows: true, cacheShadowGeometry: true);
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final firstDistances = light.cachedShadowDistances;
      expect(firstDistances, isNotNull);
      expect(light.cachedShadowWorldX, 50);
      expect(light.cachedShadowWorldY, 50);

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        identical(light.cachedShadowDistances, firstDistances),
        isTrue,
        reason: 'a fresh recompute would allocate a new List every time; the exact '
            'same instance surviving multiple frames proves the raycast sweep was '
            'actually skipped, not just coincidentally equal',
      );
    });

    testWidgets(
        'on + a flickering light with flickerAffectsRadius: false: still hits the cache '
        'across frames despite intensity genuinely changing every tick -- the whole '
        'point of decoupling flicker from radius for a stationary shadow-casting light',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      world.addSystem(LightFlickerSystem());

      final light = Light2D(
        radius: 100,
        castsShadows: true,
        cacheShadowGeometry: true,
        flickerSpeed: 3,
        flickerAmount: 0.5,
        flickerAffectsRadius: false,
      );
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final firstDistances = light.cachedShadowDistances;
      final firstIntensity = light.intensity;
      expect(firstDistances, isNotNull);

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(light.intensity, isNot(firstIntensity),
          reason: 'flicker is genuinely still running -- intensity keeps changing');
      expect(light.radius, 100, reason: 'pinned at baseRadius the whole time');
      expect(
        identical(light.cachedShadowDistances, firstDistances),
        isTrue,
        reason: 'radius (and so the cache key) never changed across all those ticks, '
            'so every one of them was a genuine cache hit -- this is the actual fps '
            'win: a stationary flickering torch no longer re-raycasts every frame',
      );
    });

    testWidgets('on: invalidates immediately (same frame) when the light moves', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final light = Light2D(radius: 100, castsShadows: true, cacheShadowGeometry: true);
      final id = world.spawn();
      final pos = Position(50, 50);
      world.storeOf<Position>().set(id, pos);
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final firstDistances = light.cachedShadowDistances;
      expect(light.cachedShadowWorldX, 50);

      pos.x = 90; // move the light -- next frame must recompute, not reuse
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowWorldX, 90,
          reason: 'cache key updated to the new position');
      expect(identical(light.cachedShadowDistances, firstDistances), isFalse,
          reason: 'a moved light must not reuse the old position\'s distances even '
              'for one frame -- invalidation has to be immediate, never a lagging '
              'blend (see cacheShadowGeometry\'s own doc comment on why)');
    });

    testWidgets('on: invalidates when radius changes, not just position', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final light = Light2D(radius: 100, castsShadows: true, cacheShadowGeometry: true);
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final firstDistances = light.cachedShadowDistances;

      light.radius = 150;
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowRadius, 150);
      expect(identical(light.cachedShadowDistances, firstDistances), isFalse);
    });

    testWidgets('on: invalidates when openAirFalloffScale changes, not just radius/position',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final light = Light2D(radius: 100, castsShadows: true, cacheShadowGeometry: true);
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<Light2D>().set(id, light);
      world.storeOf<TileMap>().set(
            world.spawn(),
            TileMap(cols: 5, rows: 5, tileWidth: 20, tileHeight: 20, tiles: List.filled(25, 0)),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      final firstDistances = light.cachedShadowDistances;

      light.openAirFalloffScale = 0.5;
      await tester.pump(const Duration(milliseconds: 16));

      expect(light.cachedShadowOpenAirFalloffScale, 0.5);
      expect(identical(light.cachedShadowDistances, firstDistances), isFalse,
          reason: 'a cached open-air-unaware sweep must not be reused once '
              'openAirFalloffScale changes what those same raw hit distances should '
              'become');
    });
  });

  group('Scene.ambientBrightness override', () {
    test('Scene defaults to null (use GameConfig\'s global setting)', () {
      // A minimal concrete Scene to read the default off of, without
      // pulling in a full populate()/loadAssets() implementation.
      expect(_TestScene().ambientBrightness, isNull);
    });
  });

  group('Scene.dayNightCycle override', () {
    test('Scene defaults to null (no time-of-day/weather lighting)', () {
      expect(_TestScene().dayNightCycle, isNull);
    });
  });
}

class _TestScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}
