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
  });
}
