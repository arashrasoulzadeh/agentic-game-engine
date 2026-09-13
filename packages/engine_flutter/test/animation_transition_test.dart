import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(8, 8);
}

void main() {
  group('AnimationTransition', () {
    test('round-trips through toJson/fromJson', () {
      final transition = AnimationTransition(
        'atlas',
        'idle_0',
        scaleX: 2,
        scaleY: 1.5,
        rotation: 0.5,
        zIndex: 4,
        remainingSeconds: 0.2,
        totalSeconds: 0.3,
      );
      final restored = AnimationTransition.fromJson(transition.toJson());

      expect(restored.atlasId, 'atlas');
      expect(restored.region, 'idle_0');
      expect(restored.scaleX, 2);
      expect(restored.scaleY, 1.5);
      expect(restored.rotation, 0.5);
      expect(restored.zIndex, 4);
      expect(restored.remainingSeconds, 0.2);
      expect(restored.totalSeconds, 0.3);
    });

    test('fromJson defaults optional fields', () {
      final restored = AnimationTransition.fromJson({
        'atlasId': 'atlas',
        'region': 'idle_0',
        'remainingSeconds': 0.1,
        'totalSeconds': 0.2,
      });
      expect(restored.scaleX, 1);
      expect(restored.scaleY, 1);
      expect(restored.rotation, 0);
      expect(restored.zIndex, 0);
    });
  });

  group('EngineView AnimationTransition rendering', () {
    testWidgets('renders a fading ghost frame without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(), {
        'idle_0': const Rect.fromLTWH(0, 0, 8, 8),
      }));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(50, 50));
      world.storeOf<AnimationTransition>().set(
            id,
            AnimationTransition('atlas', 'idle_0', remainingSeconds: 0.1, totalSeconds: 0.2),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('renders gracefully (skipped) with no Position or an unregistered atlas',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final noPosition = world.spawn();
      world.storeOf<AnimationTransition>().set(
            noPosition,
            AnimationTransition('atlas', 'idle_0', remainingSeconds: 0.1, totalSeconds: 0.2),
          );

      final missingAtlas = world.spawn();
      world.storeOf<Position>().set(missingAtlas, Position(10, 10));
      world.storeOf<AnimationTransition>().set(
            missingAtlas,
            AnimationTransition('missing', 'idle_0', remainingSeconds: 0.1, totalSeconds: 0.2),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });
}
