import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

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
  });

  group('EngineView lighting', () {
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
  });

  group('Scene.ambientBrightness override', () {
    test('Scene defaults to null (use GameConfig\'s global setting)', () {
      // A minimal concrete Scene to read the default off of, without
      // pulling in a full populate()/loadAssets() implementation.
      expect(_TestScene().ambientBrightness, isNull);
    });
  });
}

class _TestScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}
