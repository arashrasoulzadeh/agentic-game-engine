import 'dart:ui' as ui;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  return recorder.endRecording().toImage(4, 4);
}

Future<ui.Image> _halves() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 4),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(2, 0, 2, 4),
    Paint()..color = const Color(0xFF0000FF),
  );
  return recorder.endRecording().toImage(4, 4);
}

Future<List<Color>> _render(
  WidgetTester tester,
  List<(Sprite, Position)> sprites,
  List<Offset> probes, {
  bool halves = false,
}) async {
  final world = World(width: 400, height: 300);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  final registry = AtlasRegistry()
    ..register(
      'atlas',
      SpriteAtlas(
        halves ? await _halves() : await _solid(const Color(0xFFFFFFFF)),
        {'px': const Rect.fromLTWH(0, 0, 4, 4)},
      ),
    );
  for (final (sprite, pos) in sprites) {
    final e = world.spawn();
    world.componentsOf<Position>().set(e, pos);
    world.componentsOf<Sprite>().set(e, sprite);
  }
  final key = UniqueKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: RepaintBoundary(
            key: key,
            child: EngineView(
              world: world,
              atlasRegistry: registry,
              camera: Camera(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final (image, bytes) = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return (image, bytes);
  }))!;
  return [
    for (final p in probes)
      () {
        final o = (p.dy.round() * image.width + p.dx.round()) * 4;
        return Color.fromARGB(
          bytes.getUint8(o + 3),
          bytes.getUint8(o),
          bytes.getUint8(o + 1),
          bytes.getUint8(o + 2),
        );
      }(),
  ];
}

void main() {
  testWidgets(
    'tinted sprites batch through drawAtlas and still modulate the texture, '
    'matching the per-sprite fallback (flipped sprites cannot batch)',
    (tester) async {
      const tint = 0xFFFF8000;
      // Same sprite twice: upright (batched) and mirrored (fallback path).
      final colors = await _render(
        tester,
        [
          (
            Sprite('atlas', 'px', scaleX: 20, scaleY: 20)..tintArgb = tint,
            Position(-100, 0),
          ),
          (
            Sprite('atlas', 'px', scaleX: -20, scaleY: 20)..tintArgb = tint,
            Position(100, 0),
          ),
          (Sprite('atlas', 'px', scaleX: 20, scaleY: 20), Position(0, 80)),
        ],
        const [Offset(100, 150), Offset(300, 150), Offset(200, 230)],
      );
      expect(colors[0], const Color(tint)); // white * tint == tint
      expect(colors[0], colors[1]); // batched == per-sprite fallback
      expect(colors[2], const Color(0xFFFFFFFF)); // untinted stays white
    },
  );

  testWidgets(
    'a batch past the initial buffer capacity (64 sprites) still draws every '
    'sprite, plain and tinted, in the right place',
    (tester) async {
      final sprites = <(Sprite, Position)>[
        for (var i = 0; i < 70; i++)
          (
            Sprite('atlas', 'px', scaleX: 1, scaleY: 1)
              ..tintArgb = i.isEven ? 0xFF00FF00 : null,
            Position(-175.0 + i * 5, 0),
          ),
      ];
      // Sprite i is 4px wide centred on screen x = 200 + world x.
      final probes = [
        for (final i in [0, 1, 63, 64, 68, 69])
          Offset(200 + (-175.0 + i * 5), 150),
      ];
      final colors = await _render(tester, sprites, probes);
      expect(colors[0], const Color(0xFF00FF00)); // 0: tinted
      expect(colors[1], const Color(0xFFFFFFFF)); // 1: plain
      expect(colors[2], const Color(0xFFFFFFFF)); // 63
      expect(colors[3], const Color(0xFF00FF00)); // 64: past the first buffer
      expect(colors[4], const Color(0xFF00FF00)); // 68
      expect(colors[5], const Color(0xFFFFFFFF)); // 69
    },
  );

  testWidgets(
    'mirrored sprites (negative scaleX) batch through drawVertices with the '
    'texture flipped left-to-right, tinted or not, and keep their position',
    (tester) async {
      // Image: left half red, right half blue. 20x scale => 80px wide sprite.
      final colors = await _render(
        tester,
        [
          (Sprite('atlas', 'px', scaleX: 20, scaleY: 20), Position(-100, 0)),
          (Sprite('atlas', 'px', scaleX: -20, scaleY: 20), Position(100, 0)),
          (
            Sprite('atlas', 'px', scaleX: -20, scaleY: 20)
              ..tintArgb = 0xFF808080,
            Position(0, 80),
          ),
        ],
        const [
          Offset(70, 150), // upright: left half  -> red
          Offset(130, 150), // upright: right half -> blue
          Offset(270, 150), // mirrored: left half  -> blue
          Offset(330, 150), // mirrored: right half -> red
          Offset(170, 230), // mirrored+tinted: left -> blue * grey
          Offset(230, 230), // mirrored+tinted: right -> red * grey
        ],
        halves: true,
      );
      expect(colors[0], const Color(0xFFFF0000));
      expect(colors[1], const Color(0xFF0000FF));
      expect(colors[2], const Color(0xFF0000FF));
      expect(colors[3], const Color(0xFFFF0000));
      expect(colors[4].b, closeTo(0.5, 0.02));
      expect(colors[4].r, closeTo(0, 0.02));
      expect(colors[5].r, closeTo(0.5, 0.02));
      expect(colors[5].b, closeTo(0, 0.02));
    },
  );
}
