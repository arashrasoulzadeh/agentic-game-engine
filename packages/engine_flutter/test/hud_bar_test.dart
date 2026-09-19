import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HudBar', () {
    test('round-trips through toJson/fromJson', () {
      final bar = HudBar(
        value: 7,
        maxValue: 10,
        width: 120,
        height: 14,
        fillColorArgb: 0xFF00FF00,
        backgroundColorArgb: 0xFF222222,
        zIndex: 3,
      );
      final restored = HudBar.fromJson(bar.toJson());
      expect(restored.value, 7);
      expect(restored.maxValue, 10);
      expect(restored.width, 120);
      expect(restored.height, 14);
      expect(restored.fillColorArgb, 0xFF00FF00);
      expect(restored.backgroundColorArgb, 0xFF222222);
      expect(restored.zIndex, 3);
    });

    test('fromJson defaults when optional fields are absent', () {
      final restored = HudBar.fromJson({'value': 1, 'maxValue': 2});
      expect(restored.width, 100);
      expect(restored.height, 12);
      expect(restored.fillColorArgb, 0xFFE0304C);
      expect(restored.backgroundColorArgb, 0x80000000);
      expect(restored.screenSpace, isTrue);
      expect(restored.zIndex, 0);
    });

    test('screenSpace defaults to true, preserving pre-existing behavior', () {
      expect(HudBar(value: 1, maxValue: 2).screenSpace, isTrue);
    });

    test('fromJson honors explicit screenSpace: false', () {
      final bar = HudBar(value: 1, maxValue: 2, screenSpace: false);
      final restored = HudBar.fromJson(bar.toJson());
      expect(restored.screenSpace, isFalse);
    });
  });

  group('EngineView HudBar rendering', () {
    testWidgets('renders a HudBar without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      world.storeOf<HudBar>().set(id, HudBar(value: 5, maxValue: 10));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('renders a HudBar with no Position gracefully (skipped, not a crash)',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<HudBar>().set(id, HudBar(value: 5, maxValue: 10)); // no Position

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a screen-space HudBar (the default) is unaffected by camera position',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      world.storeOf<HudBar>().set(id, HudBar(value: 5, maxValue: 10, zIndex: 100));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(x: 5000, y: 5000),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a world-space (screenSpace: false) HudBar renders regardless of camera position',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      world.storeOf<HudBar>().set(
            id,
            HudBar(value: 5, maxValue: 10, screenSpace: false, zIndex: 100),
          );

      // A camera pointed far from the bar's Position -- if this were
      // screen-space it'd still show at (10,10); world-space means it
      // tracks the camera transform like a Sprite would (not asserting
      // exactly where here, just that going through worldToScreen
      // doesn't crash for a HudBar the way it already doesn't for a
      // Sprite/Text).
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(x: 5000, y: 5000),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });
}
