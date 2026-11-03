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

Future<List<Color>> _render(
  WidgetTester tester,
  List<(Sprite, Position)> sprites,
  List<Offset> probes,
) async {
  final world = World(width: 400, height: 300);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  final registry = AtlasRegistry()
    ..register(
      'atlas',
      SpriteAtlas(await _solid(const Color(0xFFFFFFFF)), {
        'px': const Rect.fromLTWH(0, 0, 4, 4),
      }),
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
}
