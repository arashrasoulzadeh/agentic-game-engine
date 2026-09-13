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
  testWidgets('EngineView batches uniform-positive-scale sprites via drawAtlas',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('atlas', SpriteAtlas(await _tinyImage(), {
      'a': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    // Two sprites on the same atlas, both uniform positive scale --
    // both should go through the drawAtlas batch path.
    final e1 = world.spawn();
    world.storeOf<Position>().set(e1, Position(50, 50));
    world.storeOf<Sprite>().set(e1, Sprite('atlas', 'a', scaleX: 2, scaleY: 2));

    final e2 = world.spawn();
    world.storeOf<Position>().set(e2, Position(100, 50));
    world.storeOf<Sprite>().set(e2, Sprite('atlas', 'a', rotation: 0.5));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('EngineView falls back to per-sprite drawing for negative/non-uniform scale',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('atlas', SpriteAtlas(await _tinyImage(), {
      'a': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    // Negative scaleX (the standard horizontal-flip pattern FacingSystem
    // uses) -- RSTransform can't represent this, must fall back.
    final flipped = world.spawn();
    world.storeOf<Position>().set(flipped, Position(50, 50));
    world.storeOf<Sprite>().set(flipped, Sprite('atlas', 'a', scaleX: -1, scaleY: 1));

    // Non-uniform scale -- also can't be expressed as one RSTransform
    // scale factor, must fall back too.
    final stretched = world.spawn();
    world.storeOf<Position>().set(stretched, Position(100, 50));
    world.storeOf<Sprite>().set(stretched, Sprite('atlas', 'a', scaleX: 2, scaleY: 1));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('EngineView renders sprites across two different atlases (mixed batches)',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('atlasA', SpriteAtlas(await _tinyImage(), {
      'a': const Rect.fromLTWH(0, 0, 8, 8),
    }));
    registry.register('atlasB', SpriteAtlas(await _tinyImage(), {
      'b': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final e1 = world.spawn();
    world.storeOf<Position>().set(e1, Position(50, 50));
    world.storeOf<Sprite>().set(e1, Sprite('atlasA', 'a'));

    final e2 = world.spawn();
    world.storeOf<Position>().set(e2, Position(100, 50));
    world.storeOf<Sprite>().set(e2, Sprite('atlasB', 'b'));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
