import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameStats', () {
    test('starts at zero/null, toString formats every field', () {
      final stats = FrameStats();
      expect(stats.stepMs, 0);
      expect(stats.paintMs, 0);
      expect(stats.lightingMs, 0);
      expect(stats.frameMs, 0);
      expect(stats.entities, 0);
      expect(stats.sprites, 0);
      expect(stats.particles, 0);
      expect(stats.followedSpeed, isNull);

      final text = stats.toString();
      expect(text, contains('frame:'));
      expect(text, contains('step:'));
      expect(text, contains('paint:'));
      expect(text, contains('light:'));
      expect(text, contains('entities:'));
      expect(text, contains('sprites:'));
      expect(text, contains('particles:'));
      expect(text, contains('speed: n/a'), reason: 'null speed reads as n/a, not "null"');
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

    testWidgets('frameMs and entity/sprite/particle counts populate after a frame',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final spriteEntity = world.spawn();
      world.storeOf<Position>().set(spriteEntity, Position(10, 10));
      world.storeOf<Sprite>().set(spriteEntity, Sprite('atlas', 'region'));

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
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.frameMs, closeTo(16, 5));
      expect(stats.entities, 1);
      expect(stats.sprites, 1);
      expect(stats.particles, 0);
    });

    testWidgets('followedSpeed reflects cameraFollowEntity\'s real Velocity magnitude',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(0, 0));
      world.storeOf<Velocity>().set(player, Velocity(30, 40)); // 3-4-5 triangle -> speed 50

      final stats = FrameStats();
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          cameraFollowEntity: player,
          frameStats: stats,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.followedSpeed, closeTo(50, 0.01));
    });

    testWidgets('followedSpeed is null with no cameraFollowEntity set', (tester) async {
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

      expect(stats.followedSpeed, isNull);
    });

    testWidgets('followedSpeed is null when the followed entity has no Velocity',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(0, 0)); // no Velocity

      final stats = FrameStats();
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          cameraFollowEntity: player,
          frameStats: stats,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(stats.followedSpeed, isNull);
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
