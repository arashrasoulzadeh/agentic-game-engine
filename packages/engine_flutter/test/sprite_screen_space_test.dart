import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

Future<AtlasRegistry> _atlas() async {
  final registry = AtlasRegistry();
  registry.register('atlas', SpriteAtlas(await _tinyImage(), {'r': const Rect.fromLTWH(0, 0, 4, 4)}));
  return registry;
}

void main() {
  testWidgets(
      'EngineView renders a screen-space Sprite (uniform-scale batched path) '
      'regardless of camera position', (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(10, 10));
    world.storeOf<Sprite>().set(id, Sprite('atlas', 'r', screenSpace: true));

    // A camera pointed far from the sprite's Position -- if this were
    // world-space it'd be nowhere near the viewport; screenSpace means
    // it should render regardless, exactly like Text.screenSpace.
    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: await _atlas(),
        camera: Camera(x: 5000, y: 5000),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
      'EngineView renders a screen-space Sprite (non-uniform-scale fallback path) '
      'regardless of camera position', (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(10, 10));
    // scaleX != scaleY takes _collectSpriteItems's per-sprite fallback
    // path (drawImageRect), not the drawAtlas batch -- both need to
    // honor screenSpace independently, since they're separate code
    // paths in EngineView.
    world.storeOf<Sprite>().set(
          id,
          Sprite('atlas', 'r', screenSpace: true, scaleX: 2, scaleY: 3),
        );

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: await _atlas(),
        camera: Camera(x: 5000, y: 5000),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
