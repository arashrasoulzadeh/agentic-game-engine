import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameStats', () {
    test('starts at zero, toString formats all three fields', () {
      final stats = FrameStats();
      expect(stats.stepMs, 0);
      expect(stats.paintMs, 0);
      expect(stats.lightingMs, 0);
      expect(stats.toString(), contains('step:'));
      expect(stats.toString(), contains('paint:'));
      expect(stats.toString(), contains('light:'));
    });
  });

  group('EngineView.frameStats', () {
    testWidgets('populates stepMs and paintMs with real, positive timing after a frame',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final stats = FrameStats();
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          frameStats: stats,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.stepMs, greaterThanOrEqualTo(0),
          reason: 'a real Stopwatch measurement -- never negative');
      expect(stats.paintMs, greaterThanOrEqualTo(0));
    });

    testWidgets('lightingMs stays 0 when ambientBrightness is 1.0 (lighting pass never runs)',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 80, castsShadows: true));

      final stats = FrameStats();
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 1.0, // default -- lighting pass skipped entirely
          frameStats: stats,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.lightingMs, 0,
          reason: '_drawLighting is never called at all when ambientBrightness is 1.0, '
              'so there is nothing to have measured');
    });

    testWidgets('lightingMs is populated once ambientBrightness actually enables the '
        'lighting pass', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(100, 100));
      world.storeOf<Light2D>().set(id, Light2D(radius: 80, castsShadows: true));

      final stats = FrameStats();
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          ambientBrightness: 0.2,
          frameStats: stats,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.lightingMs, greaterThanOrEqualTo(0),
          reason: '_drawLighting ran this time (ambientBrightness < 1.0), so this field '
              'was actually written to, not left at its untouched default');
    });

    testWidgets('showFpsOverlay works and shows timing even with no frameStats given '
        '(falls back to an internal instance)', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          showFpsOverlay: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.textContaining('step:'), findsOneWidget);
      expect(find.textContaining('paint:'), findsOneWidget);
      expect(find.textContaining('light:'), findsOneWidget);
    });
  });
}
