import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_flutter/engine_flutter.dart' as engine show Text, TextAlignment;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

World buildWorld() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

Future<ui.Image> render(WidgetTester tester, World world, AtlasRegistry atlas) async {
  final key = UniqueKey();
  await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
    width: 100, height: 100,
    child: RepaintBoundary(key: key, child: EngineView(
      world: world, atlasRegistry: atlas, camera: Camera(x: 50, y: 50))),
  ))));
  return (await tester.runAsync(() =>
      tester.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage()))!;
}

Future<Color> pixel(ui.Image image, int x, int y) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final index = (y * image.width + x) * 4;
  return Color.fromARGB(bytes.getUint8(index + 3), bytes.getUint8(index),
      bytes.getUint8(index + 1), bytes.getUint8(index + 2));
}

void main() {
  testWidgets('vertical parallax tiling covers the viewport beyond the first strip', (tester) async {
    final world = buildWorld();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.red);
    final picture = recorder.endRecording();
    final texture = await tester.runAsync(() => picture.toImage(8, 8));
    picture.dispose();
    final atlas = AtlasRegistry()..register('sky', SpriteAtlas(texture!, {
      'strip': const Rect.fromLTWH(0, 0, 8, 8),
    }));
    final id = world.spawn();
    world.storeOf<ParallaxLayer>().set(id, ParallaxLayer('sky', 'strip', tileX: true, tileY: true));
    final image = await render(tester, world, atlas);
    final color = await tester.runAsync(() => pixel(image, 50, 90));
    expect(color, Colors.red);
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    texture.dispose();
  });

  testWidgets('untextured background and foreground tiles use their fallback color', (tester) async {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<TileMap>().set(id, TileMap(cols: 2, rows: 1,
      tileWidth: 50, tileHeight: 50, tiles: [0, 0],
      backgroundTiles: [1, 0], foregroundTiles: [0, 2]));
    final image = await render(tester, world, AtlasRegistry());
    expect(await tester.runAsync(() => pixel(image, 25, 25)), const Color(0xFF4A4A4A));
    expect(await tester.runAsync(() => pixel(image, 75, 25)), const Color(0xFF4A4A4A));
    expect(await tester.runAsync(() => pixel(image, 25, 75)), Colors.black);
    image.dispose();
  });

  testWidgets('right-aligned text ends at its authored screen position', (tester) async {
    final world = buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(70, 50));
    world.storeOf<engine.Text>().set(id, engine.Text('ABC', fontSize: 10,
        screenSpace: true, align: engine.TextAlignment.right));
    final image = await render(tester, world, AtlasRegistry());
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final litColumns = <int>{};
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (bytes.getUint8((y * image.width + x) * 4) > 20) litColumns.add(x);
      }
    }
    expect(litColumns, isNotEmpty);
    expect(litColumns.every((x) => x < 70), isTrue);
    expect(litColumns.any((x) => x > 50), isTrue);
    image.dispose();
  });
}
